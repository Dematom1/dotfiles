package main

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

const (
	testRepo = "dematom-labs/app"
	mainSHA  = "1111111111111111111111111111111111111111"
	otherSHA = "2222222222222222222222222222222222222222"
)

var (
	testKey *rsa.PrivateKey
	// testPath is the signer's trusted PATH: the git and just under test, then the OS.
	testPath         string
	gitPath, justBin string
)

func TestMain(m *testing.M) {
	// Isolate git from the developer's config (signing, hooks, templates).
	os.Setenv("GIT_CONFIG_GLOBAL", os.DevNull)
	os.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	for _, k := range []string{"GIT_AUTHOR_NAME", "GIT_COMMITTER_NAME"} {
		os.Setenv(k, "signoff test")
	}
	for _, k := range []string{"GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"} {
		os.Setenv(k, "signoff@example.invalid")
	}
	var err error
	if testKey, err = rsa.GenerateKey(rand.Reader, 2048); err != nil {
		panic(err)
	}
	if gitPath, err = exec.LookPath("git"); err != nil {
		panic(err)
	}
	if justBin, err = exec.LookPath("just"); err != nil {
		panic(err)
	}
	testPath = strings.Join([]string{filepath.Dir(gitPath), filepath.Dir(justBin), "/usr/bin", "/bin"}, ":")
	os.Exit(m.Run())
}

type fakeGitHub struct {
	t        *testing.T
	pulls    []map[string]any
	justfile string // "" serves a 404
	graphql  string
	vars     map[string]any
	query    string
	tokenReq map[string]any
	posted   []checkRun
}

func (f *fakeGitHub) serve() *httptest.Server {
	mux := http.NewServeMux()
	read := func(h http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			if got := r.Header.Get("Authorization"); got != "Bearer read-token" {
				f.t.Errorf("%s %s used %q, want the read token", r.Method, r.URL.Path, got)
			}
			h(w, r)
		}
	}
	mux.HandleFunc("GET /repos/{owner}/{repo}", read(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{"default_branch": "main"})
	}))
	mux.HandleFunc("GET /repos/{owner}/{repo}/commits/{sha}/pulls", read(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(f.pulls)
	}))
	mux.HandleFunc("GET /repos/{owner}/{repo}/commits/{ref}", read(func(w http.ResponseWriter, r *http.Request) {
		if r.PathValue("ref") != "main" {
			f.t.Errorf("default branch commit lookup used %q", r.PathValue("ref"))
		}
		json.NewEncoder(w).Encode(map[string]any{"sha": mainSHA})
	}))
	mux.HandleFunc("GET /repos/{owner}/{repo}/contents/justfile", read(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("ref") != mainSHA {
			f.t.Errorf("justfile read from ref %q, want the default branch head", r.URL.Query().Get("ref"))
		}
		if f.justfile == "" {
			http.Error(w, `{"message":"Not Found"}`, http.StatusNotFound)
			return
		}
		json.NewEncoder(w).Encode(map[string]any{"content": base64.StdEncoding.EncodeToString([]byte(f.justfile))})
	}))
	mux.HandleFunc("POST /graphql", read(func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Query     string
			Variables map[string]any
		}
		json.NewDecoder(r.Body).Decode(&body)
		f.query, f.vars = body.Query, body.Variables
		io.WriteString(w, f.graphql)
	}))
	mux.HandleFunc("POST /app/installations/42/access_tokens", func(w http.ResponseWriter, r *http.Request) {
		f.verifyJWT(r.Header.Get("Authorization"))
		json.NewDecoder(r.Body).Decode(&f.tokenReq)
		json.NewEncoder(w).Encode(map[string]any{"token": "installation-token"})
	})
	mux.HandleFunc("POST /repos/dematom-labs/app/check-runs", func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer installation-token" {
			f.t.Errorf("check run posted with %q, want the installation token", got)
		}
		var run checkRun
		json.NewDecoder(r.Body).Decode(&run)
		f.posted = append(f.posted, run)
		json.NewEncoder(w).Encode(map[string]any{"html_url": "https://github.com/dematom-labs/app/runs/1"})
	})
	server := httptest.NewServer(mux)
	f.t.Cleanup(server.Close)
	return server
}

func (f *fakeGitHub) verifyJWT(auth string) {
	token, ok := strings.CutPrefix(auth, "Bearer ")
	parts := strings.Split(token, ".")
	if !ok || len(parts) != 3 {
		f.t.Fatalf("access token request auth %q is not a JWT", auth)
	}
	sig, _ := base64.RawURLEncoding.DecodeString(parts[2])
	sum := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if err := rsa.VerifyPKCS1v15(&testKey.PublicKey, crypto.SHA256, sum[:], sig); err != nil {
		f.t.Fatalf("JWT signature: %v", err)
	}
	claims, _ := base64.RawURLEncoding.DecodeString(parts[1])
	var c struct {
		Iss      string
		Iat, Exp int64
	}
	json.Unmarshal(claims, &c)
	if c.Iss != "7" || c.Exp-c.Iat > 600 || c.Iat > time.Now().Unix() {
		f.t.Errorf("JWT claims %s", claims)
	}
}

func openPR(sha, headRepo string) map[string]any {
	return map[string]any{
		"number": 5, "state": "open", "html_url": "https://github.com/dematom-labs/app/pull/5",
		"head": map[string]any{"sha": sha, "repo": map[string]any{"full_name": headRepo}},
	}
}

func run(t *testing.T, dir string, name string, args ...string) string {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s %v: %v\n%s", name, args, err, out)
	}
	return strings.TrimSpace(string(out))
}

// origin creates <base>/dematom-labs/app.git with one commit of files.
func origin(t *testing.T, files map[string]string) (base, sha string) {
	t.Helper()
	base = t.TempDir()
	work := filepath.Join(base, "work")
	os.MkdirAll(work, 0o700)
	run(t, work, "git", "init", "--quiet", "--initial-branch=main")
	for name, content := range files {
		os.WriteFile(filepath.Join(work, name), []byte(content), 0o600)
	}
	run(t, work, "git", "add", ".")
	run(t, work, "git", "commit", "--quiet", "-m", "init")
	run(t, base, "git", "clone", "--quiet", "--bare", work, filepath.Join(base, testRepo+".git"))
	return base + "/", run(t, work, "git", "rev-parse", "HEAD")
}

type harness struct {
	signer *Signer
	gh     *fakeGitHub
	signs  int
	sha    string
}

func newHarness(t *testing.T, files map[string]string, trusted string) *harness {
	t.Helper()
	gitBase, sha := origin(t, files)
	h := &harness{gh: &fakeGitHub{t: t, justfile: trusted}, sha: sha}
	h.gh.pulls = []map[string]any{openPR(sha, testRepo)}
	state := t.TempDir()
	h.signer = &Signer{
		APIBase:        h.gh.serve().URL,
		ReadToken:      "read-token",
		GitBase:        gitBase,
		AppID:          7,
		InstallationID: 42,
		Sign: func(msg []byte) ([]byte, error) {
			h.signs++
			sum := sha256.Sum256(msg)
			return rsa.SignPKCS1v15(nil, testKey, crypto.SHA256, sum[:])
		},
		Path:      testPath,
		Home:      t.TempDir(),
		MirrorDir: filepath.Join(state, "mirrors"),
		LogDir:    filepath.Join(state, "logs"),
		Timeout:   time.Minute,
		Out:       io.Discard,
	}
	return h
}

func TestRunPostsSuccess(t *testing.T) {
	h := newHarness(t, map[string]string{"README.md": "hi\n", "uv.lock": "lock\n"}, "signoff:\n    test -f README.md\n    echo checked\n")
	res, err := h.signer.Run(context.Background(), testRepo, h.sha)
	if err != nil {
		t.Fatal(err)
	}
	if res.Conclusion != "success" || res.CheckURL != "https://github.com/dematom-labs/app/runs/1" {
		t.Fatalf("result %+v", res)
	}
	if len(h.gh.posted) != 1 {
		t.Fatalf("posted %d check runs", len(h.gh.posted))
	}
	got := h.gh.posted[0]
	if got.Name != "local-signoff" || got.HeadSHA != h.sha || got.Status != "completed" || got.Conclusion != "success" || got.ExternalID == "" {
		t.Errorf("check run %+v", got)
	}
	if got.Output.Text != "" {
		t.Errorf("success should not carry the log tail: %q", got.Output.Text)
	}
	if fmt.Sprint(h.gh.tokenReq) != "map[permissions:map[checks:write] repositories:[app]]" {
		t.Errorf("installation token request %v", h.gh.tokenReq)
	}

	logData, err := os.ReadFile(res.LogPath)
	if err != nil || !strings.Contains(string(logData), "checked") {
		t.Fatalf("log %q: %v", logData, err)
	}
	trustedSum := sha256.Sum256([]byte(h.gh.justfile))
	manifest := fmt.Sprintf("%x  %s:justfile\n%x  uv.lock\n", trustedSum, mainSHA, sha256.Sum256([]byte("lock\n")))
	for _, want := range []string{
		"[#5](https://github.com/dematom-labs/app/pull/5)",
		"`" + h.sha + "`",
		"`main` at `" + mainSHA + "`",
		fmt.Sprintf("config_sha256 | `%x`", sha256.Sum256([]byte(manifest))),
		manifest,
		fmt.Sprintf("log_sha256 | `%x`", sha256.Sum256(logData)),
		"`just signoff`: exit 0",
		"| git | `" + gitPath + "` | `git version",
		"| just | `" + justBin + "` | `just ",
	} {
		if !strings.Contains(got.Output.Summary, want) {
			t.Errorf("summary lacks %q:\n%s", want, got.Output.Summary)
		}
	}
}

func TestRunUsesTrustedRecipeAndPostsFailure(t *testing.T) {
	// The PR's own justfile would pass; the default branch's recipe decides.
	h := newHarness(t, map[string]string{"justfile": "signoff:\n    true\n"}, "signoff:\n    echo boom read-token\n    exit 3\n")
	res, err := h.signer.Run(context.Background(), testRepo, h.sha)
	if err != nil {
		t.Fatal(err)
	}
	got := h.gh.posted[0]
	if res.Conclusion != "failure" || got.Conclusion != "failure" {
		t.Fatalf("result %+v, posted %+v", res, got)
	}
	if !strings.Contains(got.Output.Title, "exit 3") || !strings.Contains(got.Output.Text, "boom ***") {
		t.Errorf("failure output %+v", got.Output)
	}
	if strings.Contains(got.Output.Text, "read-token") {
		t.Errorf("posted log tail leaks the read token:\n%s", got.Output.Text)
	}
}

func TestRunIgnoresCallerPath(t *testing.T) {
	// A fake just first on the caller's PATH would pass any recipe.
	fake := t.TempDir()
	os.WriteFile(filepath.Join(fake, "just"), []byte("#!/bin/sh\necho signoff\nexit 0\n"), 0o700)
	t.Setenv("PATH", fake+string(filepath.ListSeparator)+os.Getenv("PATH"))

	h := newHarness(t, map[string]string{"README.md": "hi\n"}, "signoff:\n    exit 3\n")
	res, err := h.signer.Run(context.Background(), testRepo, h.sha)
	if err != nil {
		t.Fatal(err)
	}
	if res.Conclusion != "failure" || len(h.gh.posted) != 1 || h.gh.posted[0].Conclusion != "failure" {
		t.Fatalf("result %+v, posted %+v", res, h.gh.posted)
	}
	if !strings.Contains(h.gh.posted[0].Output.Summary, "| just | `"+justBin+"` |") {
		t.Errorf("summary does not record the trusted just:\n%s", h.gh.posted[0].Output.Summary)
	}
}

func TestRunDoesNotPassCallerEnvironment(t *testing.T) {
	h := newHarness(t, map[string]string{"README.md": "hi\n"}, "signoff:\n    env\n")
	for k, v := range map[string]string{
		"GH_TOKEN": "read-token", "GITHUB_TOKEN": "read-token", "GIT_CONFIG_PARAMETERS": "'core.pager=evil'",
		"NODE_OPTIONS": "--require=evil", "DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib", "SIGNOFF_CALLER": "evil",
	} {
		t.Setenv(k, v)
	}
	res, err := h.signer.Run(context.Background(), testRepo, h.sha)
	if err != nil {
		t.Fatal(err)
	}
	logData, err := os.ReadFile(res.LogPath)
	if err != nil {
		t.Fatal(err)
	}
	env := map[string]string{}
	for _, line := range strings.Split(strings.TrimSpace(string(logData)), "\n") {
		k, v, _ := strings.Cut(line, "=")
		env[k] = v
	}
	if env["PATH"] != testPath || env["HOME"] != h.signer.Home || env["LC_ALL"] != "C.UTF-8" || !strings.HasPrefix(env["TMPDIR"], os.TempDir()) {
		t.Errorf("recipe environment %v", env)
	}
	for k := range env {
		if strings.HasPrefix(k, "GIT_") || slices.Contains([]string{"GH_TOKEN", "GITHUB_TOKEN", "NODE_OPTIONS", "DYLD_INSERT_LIBRARIES", "SIGNOFF_CALLER"}, k) {
			t.Errorf("caller variable %s reached the recipe", k)
		}
	}
	if strings.Contains(string(logData), "evil") || strings.Contains(string(logData), "read-token") {
		t.Errorf("caller values reached the recipe:\n%s", logData)
	}
}

func TestRunRefusals(t *testing.T) {
	ok := "signoff:\n    true\n"
	cases := []struct {
		name, repo, sha, justfile, want string
		pulls                           func(sha string) []map[string]any
	}{
		{name: "non-fleet repo", repo: "someone/app", justfile: ok, want: "not a fleet repo"},
		{name: "malformed repo", repo: "dematom-labs/../x", justfile: ok, want: "not owner/repo"},
		{name: "short sha", sha: "abc123", justfile: ok, want: "not a full lowercase commit SHA"},
		{name: "no open pull request", justfile: ok, want: "not the head of an open pull request",
			pulls: func(sha string) []map[string]any {
				closed := openPR(sha, testRepo)
				closed["state"] = "closed"
				return []map[string]any{closed}
			}},
		{name: "stale head", justfile: ok, want: "stale head (#5 is at " + otherSHA,
			pulls: func(string) []map[string]any { return []map[string]any{openPR(otherSHA, testRepo)} }},
		{name: "fork pull request", justfile: ok, want: "fork pull request",
			pulls: func(sha string) []map[string]any { return []map[string]any{openPR(sha, "someone/app")} }},
		{name: "no trusted justfile", want: "no justfile on main"},
		{name: "missing recipe", justfile: "test:\n    true\n", want: `no "signoff" recipe`},
		{name: "unloadable justfile", justfile: "import 'ci.just'\n", want: "trusted justfile does not load"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			h := newHarness(t, map[string]string{"README.md": "hi\n"}, tc.justfile)
			if tc.pulls != nil {
				h.gh.pulls = tc.pulls(h.sha)
			}
			repo, sha := tc.repo, tc.sha
			if repo == "" {
				repo = testRepo
			}
			if sha == "" {
				sha = h.sha
			}
			_, err := h.signer.Run(context.Background(), repo, sha)
			var r refusal
			if !errors.As(err, &r) || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("got %v, want refusal containing %q", err, tc.want)
			}
			if len(h.gh.posted) != 0 || h.signs != 0 {
				t.Errorf("a refusal must not touch the App key or post: posted=%d signs=%d", len(h.gh.posted), h.signs)
			}
		})
	}
}

func TestVerifyCheckout(t *testing.T) {
	ctx := context.Background()
	base, sha := origin(t, map[string]string{"a.txt": "a\n"})
	dir := filepath.Join(t.TempDir(), "src")
	run(t, "", "git", "clone", "--quiet", base+testRepo+".git", dir)

	tc, err := (&Signer{Path: testPath, Home: t.TempDir()}).toolchain(filepath.Join(t.TempDir(), "tmp"))
	if err != nil {
		t.Fatal(err)
	}
	if err := tc.verifyCheckout(ctx, dir, sha); err != nil {
		t.Fatalf("clean checkout: %v", err)
	}
	var r refusal
	if err := tc.verifyCheckout(ctx, dir, otherSHA); !errors.As(err, &r) || !strings.Contains(err.Error(), "does not match") {
		t.Errorf("SHA mismatch: %v", err)
	}
	os.WriteFile(filepath.Join(dir, "a.txt"), []byte("changed\n"), 0o600)
	if err := tc.verifyCheckout(ctx, dir, sha); !errors.As(err, &r) || !strings.Contains(err.Error(), "M a.txt") {
		t.Errorf("modified file: %v", err)
	}
	run(t, dir, "git", "checkout", "--quiet", "a.txt")
	os.WriteFile(filepath.Join(dir, "new.txt"), []byte("x\n"), 0o600)
	if err := tc.verifyCheckout(ctx, dir, sha); !errors.As(err, &r) || !strings.Contains(err.Error(), "?? new.txt") {
		t.Errorf("untracked file: %v", err)
	}
}

func TestUnsignedSelectsHeadsWithoutAppCheck(t *testing.T) {
	h := newHarness(t, map[string]string{"README.md": "hi\n"}, "")
	pr := func(repo, oid string, runs ...int) string {
		var suites []string
		for _, n := range runs {
			suites = append(suites, fmt.Sprintf(`{"checkRuns":{"totalCount":%d}}`, n))
		}
		return fmt.Sprintf(`{"repository":{"nameWithOwner":%q},"commits":{"nodes":[{"commit":{"oid":%q,"checkSuites":{"nodes":[%s]}}}]}}`,
			repo, oid, strings.Join(suites, ","))
	}
	h.gh.graphql = `{"data":{"search":{"nodes":[` + strings.Join([]string{
		pr("dematom-labs/signed", mainSHA, 0, 1),
		pr("dematom-labs/empty-suite", otherSHA, 0),
		pr("dematom-labs/no-suite", h.sha),
	}, ",") + `]}}}`

	targets, err := h.signer.unsigned(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	want := []target{{"dematom-labs/empty-suite", otherSHA}, {"dematom-labs/no-suite", h.sha}}
	if fmt.Sprint(targets) != fmt.Sprint(want) {
		t.Errorf("targets %v, want %v", targets, want)
	}
	if h.gh.vars["q"] != "is:pr is:open -is:draft archived:false org:dematom-labs" || h.gh.vars["app"] != float64(7) {
		t.Errorf("search variables %v", h.gh.vars)
	}
	if !strings.Contains(h.gh.query, `checkName: "local-signoff"`) {
		t.Errorf("query does not filter on the check name:\n%s", h.gh.query)
	}
}
