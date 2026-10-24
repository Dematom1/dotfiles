package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"regexp"
	"runtime"
	"runtime/debug"
	"slices"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	checkName        = "local-signoff"
	fleetOrg         = "dematom-labs"
	recipe           = "signoff"
	watchConcurrency = 2
)

var (
	shaPattern  = regexp.MustCompile(`\A[0-9a-f]{40}\z`)
	namePattern = regexp.MustCompile(`\A[A-Za-z0-9_.-]+\z`)

	// configFiles are hashed with the trusted justfile into config_sha256.
	configFiles = []string{
		".bun-version", ".node-version", ".nvmrc", ".python-version", ".tool-versions",
		"bun.lock", "bun.lockb", "package-lock.json", "pnpm-lock.yaml", "yarn.lock",
		"uv.lock", "poetry.lock", "go.sum", "Cargo.lock", "Gemfile.lock",
	}
	versionedTools = []string{"git", "just", "ast-grep", "bun", "node", "uv", "python3", "go", "ruby"}
)

// refusal means the signer declined to sign; no check run was posted.
type refusal string

func (r refusal) Error() string { return "refused: " + string(r) }

func refusef(format string, args ...any) error { return refusal(fmt.Sprintf(format, args...)) }

type Signer struct {
	APIBase        string
	ReadToken      string // captain's gh token, used for reads only
	GitBase        string // clone URL prefix; "owner/repo.git" is appended
	AppID          int64
	InstallationID int64
	Sign           func([]byte) ([]byte, error) // RS256 with the App key
	Path           string                       // trusted PATH; the only one git, just, and the recipe see
	Home           string                       // HOME for git, just, and the recipe
	MirrorDir      string
	LogDir         string
	Timeout        time.Duration
	Out            io.Writer
}

type Result struct {
	Conclusion string
	CheckURL   string
	LogPath    string
}

type pullRequest struct {
	Number  int
	State   string
	HTMLURL string `json:"html_url"`
	Head    struct {
		SHA  string
		Repo *struct {
			FullName string `json:"full_name"`
		}
	}
}

type checkOutput struct {
	Title   string `json:"title"`
	Summary string `json:"summary"`
	Text    string `json:"text,omitempty"`
}

type checkRun struct {
	Name        string      `json:"name"`
	HeadSHA     string      `json:"head_sha"`
	Status      string      `json:"status"`
	Conclusion  string      `json:"conclusion"`
	ExternalID  string      `json:"external_id"`
	StartedAt   time.Time   `json:"started_at"`
	CompletedAt time.Time   `json:"completed_at"`
	Output      checkOutput `json:"output"`
}

// record is everything the check run reports about one signoff.
type record struct {
	sha, tree       string
	pr              pullRequest
	branch, mainSHA string
	manifest        string
	exitCode        int
	timedOut        bool
	started         time.Time
	duration        time.Duration
	logSHA256       string
	logTail         string
	tools           []tool
	host            string
}

func (s *Signer) Run(ctx context.Context, repo, sha string) (*Result, error) {
	owner, name, _ := strings.Cut(repo, "/")
	if !namePattern.MatchString(owner) || !namePattern.MatchString(name) || name == "." || name == ".." {
		return nil, refusef("%q is not owner/repo", repo)
	}
	if !strings.EqualFold(owner, fleetOrg) {
		return nil, refusef("%s is not a fleet repo (owner must be %s)", repo, fleetOrg)
	}
	repo = fleetOrg + "/" + name
	if !shaPattern.MatchString(sha) {
		return nil, refusef("%q is not a full lowercase commit SHA", sha)
	}
	read := &api{base: s.APIBase, auth: "Bearer " + s.ReadToken}

	var meta struct {
		DefaultBranch string `json:"default_branch"`
	}
	if err := read.do(ctx, http.MethodGet, "/repos/"+repo, nil, &meta); err != nil {
		return nil, err
	}
	pr, err := openPullRequest(ctx, read, repo, sha)
	if err != nil {
		return nil, err
	}
	justfile, mainSHA, err := trustedJustfile(ctx, read, repo, meta.DefaultBranch)
	if err != nil {
		return nil, err
	}

	work, err := os.MkdirTemp("", "signoff-")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(work)
	tc, err := s.toolchain(filepath.Join(work, "tmp"))
	if err != nil {
		return nil, err
	}
	justPath := filepath.Join(work, "justfile")
	if err := os.WriteFile(justPath, justfile, 0o600); err != nil {
		return nil, err
	}
	if err := tc.requireRecipe(ctx, justPath); err != nil {
		return nil, err
	}
	src := filepath.Join(work, "src")
	if err := s.checkout(ctx, tc, repo, sha, src); err != nil {
		return nil, err
	}
	if err := tc.verifyCheckout(ctx, src, sha); err != nil {
		return nil, err
	}

	rec := record{sha: sha, pr: pr, branch: meta.DefaultBranch, mainSHA: mainSHA}
	if rec.tree, err = tc.git(ctx, src, "rev-parse", "HEAD^{tree}"); err != nil {
		return nil, err
	}
	if rec.manifest, err = tc.configManifest(ctx, src, justfile, mainSHA); err != nil {
		return nil, err
	}
	rec.tools = tc.versions(ctx, src)
	hostname, _ := os.Hostname()
	rec.host = fmt.Sprintf("%s (%s/%s)", hostname, runtime.GOOS, runtime.GOARCH)

	logPath := filepath.Join(s.LogDir, repo, sha+".log")
	fmt.Fprintf(s.Out, "%s@%s: running just %s (log: %s)\n", repo, sha[:12], recipe, logPath)
	if err := s.runRecipe(ctx, tc, justPath, src, logPath, &rec); err != nil {
		return nil, err
	}

	run := buildCheckRun(rec)
	url, err := s.post(ctx, repo, run)
	if err != nil {
		return nil, fmt.Errorf("checks %s but posting failed (log: %s): %w", run.Conclusion, logPath, err)
	}
	return &Result{Conclusion: run.Conclusion, CheckURL: url, LogPath: logPath}, nil
}

func openPullRequest(ctx context.Context, read *api, repo, sha string) (pullRequest, error) {
	var pulls []pullRequest
	if err := read.do(ctx, http.MethodGet, "/repos/"+repo+"/commits/"+sha+"/pulls", nil, &pulls); err != nil {
		return pullRequest{}, err
	}
	var stale []string
	for _, pr := range pulls {
		if pr.State != "open" {
			continue
		}
		if pr.Head.SHA != sha {
			stale = append(stale, fmt.Sprintf("#%d is at %s", pr.Number, pr.Head.SHA))
			continue
		}
		if pr.Head.Repo == nil || !strings.EqualFold(pr.Head.Repo.FullName, repo) {
			return pullRequest{}, refusef("#%d is a fork pull request; fork code is never run", pr.Number)
		}
		return pr, nil
	}
	if len(stale) > 0 {
		return pullRequest{}, refusef("%s is a stale head (%s)", sha, strings.Join(stale, ", "))
	}
	return pullRequest{}, refusef("%s is not the head of an open pull request in %s", sha, repo)
}

// trustedJustfile reads the justfile from the default branch, never from the PR.
func trustedJustfile(ctx context.Context, read *api, repo, branch string) ([]byte, string, error) {
	var commit struct{ SHA string }
	if err := read.do(ctx, http.MethodGet, "/repos/"+repo+"/commits/"+branch, nil, &commit); err != nil {
		return nil, "", err
	}
	var file struct{ Content string }
	err := read.do(ctx, http.MethodGet, "/repos/"+repo+"/contents/justfile?ref="+commit.SHA, nil, &file)
	var httpErr *httpError
	if errors.As(err, &httpErr) && httpErr.status == http.StatusNotFound {
		return nil, "", refusef("%s has no justfile on %s; the repo is not onboarded", repo, branch)
	}
	if err != nil {
		return nil, "", err
	}
	content, err := base64.StdEncoding.DecodeString(strings.ReplaceAll(file.Content, "\n", ""))
	return content, commit.SHA, err
}

// toolchain runs git, just, and the recipe from the trusted PATH with a
// constructed environment; nothing is inherited from the caller.
type toolchain struct {
	path, home, tmp string
	gitBin, justBin string
}

func (s *Signer) toolchain(tmp string) (*toolchain, error) {
	if err := os.Mkdir(tmp, 0o700); err != nil {
		return nil, err
	}
	tc := &toolchain{path: s.Path, home: s.Home, tmp: tmp}
	for name, bin := range map[string]*string{"git": &tc.gitBin, "just": &tc.justBin} {
		if *bin = tc.lookPath(name); *bin == "" {
			return nil, fmt.Errorf("%s is not on the trusted PATH %s", name, s.Path)
		}
	}
	return tc, nil
}

// lookPath resolves name on the trusted PATH only, never the process PATH.
func (tc *toolchain) lookPath(name string) string {
	for _, dir := range filepath.SplitList(tc.path) {
		if !filepath.IsAbs(dir) {
			continue
		}
		bin := filepath.Join(dir, name)
		if info, err := os.Stat(bin); err == nil && info.Mode().IsRegular() && info.Mode().Perm()&0o111 != 0 {
			return bin
		}
	}
	return ""
}

func (tc *toolchain) command(ctx context.Context, dir, bin string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Dir = dir
	cmd.Env = []string{"PATH=" + tc.path, "HOME=" + tc.home, "TMPDIR=" + tc.tmp, "LANG=C.UTF-8", "LC_ALL=C.UTF-8"}
	return cmd
}

func (tc *toolchain) requireRecipe(ctx context.Context, justfile string) error {
	cmd := tc.command(ctx, "", tc.justBin, "--justfile", justfile, "--summary")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return refusef("trusted justfile does not load: %v: %s", err, strings.TrimSpace(stderr.String()))
	}
	if !slices.Contains(strings.Fields(string(out)), recipe) {
		return refusef("trusted justfile has no %q recipe; the repo is not onboarded", recipe)
	}
	return nil
}

// checkout makes a fresh clone of sha from a per-repo mirror.
func (s *Signer) checkout(ctx context.Context, tc *toolchain, repo, sha, dst string) error {
	mirror := filepath.Join(s.MirrorDir, repo+".git")
	if err := os.MkdirAll(filepath.Dir(mirror), 0o700); err != nil {
		return err
	}
	lock, err := os.OpenFile(mirror+".lock", os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return err
	}
	defer lock.Close()
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	if _, err := os.Stat(mirror); errors.Is(err, os.ErrNotExist) {
		tmp := mirror + ".tmp"
		os.RemoveAll(tmp)
		if _, err := tc.git(ctx, "", "clone", "--quiet", "--mirror", s.GitBase+repo+".git", tmp); err != nil {
			return err
		}
		if err := os.Rename(tmp, mirror); err != nil {
			return err
		}
	} else if _, err := tc.git(ctx, mirror, "fetch", "--quiet", "--prune", "origin"); err != nil {
		return err
	}
	if _, err := tc.git(ctx, "", "clone", "--quiet", "--shared", "--no-checkout", mirror, dst); err != nil {
		return err
	}
	_, err = tc.git(ctx, dst, "checkout", "--quiet", "--detach", sha)
	return err
}

func (tc *toolchain) verifyCheckout(ctx context.Context, dir, sha string) error {
	head, err := tc.git(ctx, dir, "rev-parse", "HEAD")
	if err != nil {
		return err
	}
	if head != sha {
		return refusef("checkout HEAD %s does not match %s", head, sha)
	}
	status, err := tc.git(ctx, dir, "status", "--porcelain", "--untracked-files=all", "--ignored")
	if err != nil {
		return err
	}
	if status != "" {
		return refusef("fresh checkout of %s is not clean:\n%s", sha, truncate([]byte(status), 2000))
	}
	return nil
}

func (tc *toolchain) git(ctx context.Context, dir string, args ...string) (string, error) {
	cmd := tc.command(ctx, dir, tc.gitBin, append([]string{"-c", "core.hooksPath=/dev/null"}, args...)...)
	cmd.Env = append(cmd.Env, "GIT_TERMINAL_PROMPT=0")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("git %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return strings.TrimSpace(string(out)), nil
}

// configManifest lists sha256sum-style lines for the trusted justfile and the
// head's pin and lock files; config_sha256 is the sha256 of this text.
func (tc *toolchain) configManifest(ctx context.Context, src string, justfile []byte, mainSHA string) (string, error) {
	files, err := tc.git(ctx, src, "ls-files")
	if err != nil {
		return "", err
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%x  %s:justfile\n", sha256.Sum256(justfile), mainSHA)
	for _, file := range strings.Split(files, "\n") {
		if !slices.Contains(configFiles, path.Base(file)) {
			continue
		}
		data, err := os.ReadFile(filepath.Join(src, file))
		if err != nil {
			return "", err
		}
		fmt.Fprintf(&b, "%x  %s\n", sha256.Sum256(data), file)
	}
	return b.String(), nil
}

type tool struct{ name, path, version string }

func (tc *toolchain) versions(ctx context.Context, dir string) []tool {
	var tools []tool
	for _, name := range versionedTools {
		bin := tc.lookPath(name)
		if bin == "" {
			continue
		}
		out, err := tc.command(ctx, dir, bin, "--version").Output()
		if err != nil {
			continue
		}
		first, _, _ := strings.Cut(strings.TrimSpace(string(out)), "\n")
		tools = append(tools, tool{name, bin, first})
	}
	return tools
}

func (s *Signer) runRecipe(ctx context.Context, tc *toolchain, justfile, src, logPath string, rec *record) error {
	if err := os.MkdirAll(filepath.Dir(logPath), 0o700); err != nil {
		return err
	}
	logFile, err := os.OpenFile(logPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer logFile.Close()

	runCtx, cancel := context.WithTimeout(ctx, s.Timeout)
	defer cancel()
	cmd := tc.command(runCtx, src, tc.justBin, "--justfile", justfile, "--working-directory", src, recipe)
	cmd.Stdout, cmd.Stderr = logFile, logFile
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = 10 * time.Second

	rec.started = time.Now()
	runErr := cmd.Run()
	rec.duration = time.Since(rec.started)
	if ctx.Err() != nil {
		return ctx.Err() // interrupted: post nothing rather than a false failure
	}
	rec.timedOut = runCtx.Err() != nil
	rec.exitCode = -1
	if cmd.ProcessState != nil {
		rec.exitCode = cmd.ProcessState.ExitCode()
	}
	if runErr != nil && rec.exitCode == 0 {
		rec.exitCode = -1
	}
	if rec.timedOut {
		fmt.Fprintf(logFile, "\nsignoff: timed out after %s\n", s.Timeout)
	}
	if err := logFile.Sync(); err != nil {
		return err
	}
	data, err := os.ReadFile(logPath)
	if err != nil {
		return err
	}
	rec.logSHA256 = fmt.Sprintf("%x", sha256.Sum256(data))
	logText := string(data)
	if s.ReadToken != "" {
		logText = strings.ReplaceAll(logText, s.ReadToken, "***")
	}
	rec.logTail = tail(logText, 100, 60000)
	return nil
}

func tail(s string, lines, maxBytes int) string {
	parts := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(parts) > lines {
		parts = parts[len(parts)-lines:]
	}
	out := strings.Join(parts, "\n")
	if len(out) > maxBytes {
		out = out[len(out)-maxBytes:]
	}
	return out
}

func buildCheckRun(rec record) checkRun {
	conclusion, verdict := "success", "passed"
	if rec.exitCode != 0 {
		conclusion, verdict = "failure", "failed"
	}
	outcome := fmt.Sprintf("exit %d", rec.exitCode)
	if rec.timedOut {
		outcome = "timed out"
	}
	duration := rec.duration.Round(time.Second)
	configSum := sha256.Sum256([]byte(rec.manifest))

	var b strings.Builder
	fmt.Fprintf(&b, "**`just %s` %s** on a fresh checkout of `%s`.\n\n", recipe, verdict, rec.sha)
	fmt.Fprintf(&b, "| Field | Value |\n|---|---|\n")
	row := func(k, v string) { fmt.Fprintf(&b, "| %s | %s |\n", k, v) }
	row("Pull request", fmt.Sprintf("[#%d](%s)", rec.pr.Number, rec.pr.HTMLURL))
	row("Head SHA", "`"+rec.sha+"`")
	row("Tree SHA", "`"+rec.tree+"`")
	row("Recipe source", fmt.Sprintf("`%s` at `%s`", rec.branch, rec.mainSHA))
	row("config_sha256", fmt.Sprintf("`%x`", configSum))
	row("Recipe result", fmt.Sprintf("`just %s`: %s in %s", recipe, outcome, duration))
	row("log_sha256", "`"+rec.logSHA256+"`")
	row("Host", "`"+rec.host+"`")
	row("Signer", "`"+signerVersion()+"`")
	fmt.Fprintf(&b, "\n**Config manifest** (`config_sha256` is its sha256):\n\n```text\n%s```\n", rec.manifest)
	fmt.Fprintf(&b, "\n**Tools** (from the trusted `PATH`)\n\n| Tool | Path | Version |\n|---|---|---|\n")
	for _, t := range rec.tools {
		fmt.Fprintf(&b, "| %s | `%s` | `%s` |\n", t.name, t.path, strings.ReplaceAll(t.version, "|", "\\|"))
	}

	run := checkRun{
		Name:        checkName,
		HeadSHA:     rec.sha,
		Status:      "completed",
		Conclusion:  conclusion,
		ExternalID:  newID(),
		StartedAt:   rec.started.UTC().Truncate(time.Second),
		CompletedAt: rec.started.Add(rec.duration).UTC().Truncate(time.Second),
		Output: checkOutput{
			Title:   fmt.Sprintf("just %s %s (%s, %s)", recipe, verdict, outcome, duration),
			Summary: string(truncate([]byte(b.String()), 65000)),
		},
	}
	if conclusion == "failure" {
		run.Output.Text = "Last lines of the signoff log:\n\n`````text\n" + rec.logTail + "\n`````\n"
	}
	return run
}

func signerVersion() string {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return "unknown"
	}
	version := info.Main.Version
	for _, setting := range info.Settings {
		switch setting.Key {
		case "vcs.revision":
			version += " " + setting.Value
		case "vcs.modified":
			if setting.Value == "true" {
				version += " (modified)"
			}
		}
	}
	return version
}

func newID() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// post is the only use of the App key: mint a JWT, exchange it for a
// checks-only installation token scoped to repo, and create the check run.
func (s *Signer) post(ctx context.Context, repo string, run checkRun) (string, error) {
	jwt, err := appJWT(s.AppID, s.Sign, time.Now())
	if err != nil {
		return "", err
	}
	app := &api{base: s.APIBase, auth: "Bearer " + jwt}
	_, name, _ := strings.Cut(repo, "/")
	var token struct{ Token string }
	body := map[string]any{"repositories": []string{name}, "permissions": map[string]string{"checks": "write"}}
	if err := app.do(ctx, http.MethodPost, fmt.Sprintf("/app/installations/%d/access_tokens", s.InstallationID), body, &token); err != nil {
		return "", err
	}
	installation := &api{base: s.APIBase, auth: "Bearer " + token.Token}
	var created struct {
		HTMLURL string `json:"html_url"`
	}
	if err := installation.do(ctx, http.MethodPost, "/repos/"+repo+"/check-runs", run, &created); err != nil {
		return "", err
	}
	return created.HTMLURL, nil
}

type target struct{ repo, sha string }

type checkSuite struct {
	CheckRuns struct{ TotalCount int }
}

const unsignedQuery = `query($q: String!, $app: Int!) {
  search(query: $q, type: ISSUE, first: 100) {
    nodes {
      ... on PullRequest {
        repository { nameWithOwner }
        commits(last: 1) {
          nodes {
            commit {
              oid
              checkSuites(first: 10, filterBy: {appId: $app}) {
                nodes { checkRuns(filterBy: {checkName: "local-signoff"}) { totalCount } }
              }
            }
          }
        }
      }
    }
  }
}`

// unsigned lists open, non-draft fleet PR heads without a local-signoff check from the App.
func (s *Signer) unsigned(ctx context.Context) ([]target, error) {
	read := &api{base: s.APIBase, auth: "Bearer " + s.ReadToken}
	var data struct {
		Search struct {
			Nodes []struct {
				Repository struct{ NameWithOwner string }
				Commits    struct {
					Nodes []struct {
						Commit struct {
							OID         string
							CheckSuites struct{ Nodes []checkSuite }
						}
					}
				}
			}
		}
	}
	// ponytail: first 100 results only; paginate if the org ever has more open PRs.
	vars := map[string]any{"q": "is:pr is:open -is:draft archived:false org:" + fleetOrg, "app": s.AppID}
	if err := read.graphql(ctx, unsignedQuery, vars, &data); err != nil {
		return nil, err
	}
	var targets []target
	for _, pr := range data.Search.Nodes {
		for _, c := range pr.Commits.Nodes {
			signed := slices.ContainsFunc(c.Commit.CheckSuites.Nodes, func(suite checkSuite) bool {
				return suite.CheckRuns.TotalCount > 0
			})
			if !signed {
				targets = append(targets, target{pr.Repository.NameWithOwner, c.Commit.OID})
			}
		}
	}
	return targets, nil
}

// Watch signs every unsigned head once; launchd schedules the next pass.
func (s *Signer) Watch(ctx context.Context) error {
	targets, err := s.unsigned(ctx)
	if err != nil {
		return err
	}
	sem := make(chan struct{}, watchConcurrency)
	var wg sync.WaitGroup
	for _, t := range targets {
		sem <- struct{}{}
		wg.Go(func() {
			defer func() { <-sem }()
			res, err := s.Run(ctx, t.repo, t.sha)
			if err != nil {
				fmt.Fprintf(s.Out, "%s@%s: %v\n", t.repo, t.sha, err)
				return
			}
			fmt.Fprintf(s.Out, "%s@%s: %s %s\n", t.repo, t.sha, res.Conclusion, res.CheckURL)
		})
	}
	wg.Wait()
	return nil
}
