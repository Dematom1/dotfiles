// Command signoff runs a repository's trusted `just signoff` recipe on a fresh
// checkout of a pull request head and posts the result as the App-signed
// `local-signoff` check run. See README.md for the trust model.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// The dematom-local-signoff App, its dematom-labs installation, and the
// GitHub fingerprint of its private key.
const (
	defaultAppID          = 5460531
	defaultInstallationID = 174959222
	defaultKeyFingerprint = "SHA256:tlF5N8zgxWi5AR2FZdYPcRdbm8C1Dk4LkwsMp77A4Uk="
)

// trustedPath replaces the default trusted PATH when set at build time with
// -ldflags "-X main.trustedPath=<dir>:<dir>".
var trustedPath string

// defaultTrustedPath is the nix-darwin system and per-user profiles, then the OS.
func defaultTrustedPath(username string) string {
	return strings.Join([]string{"/run/current-system/sw/bin", "/etc/profiles/per-user/" + username + "/bin", "/usr/bin", "/bin"}, ":")
}

const usage = `usage:
  signoff run <owner/repo> <sha>   sign one open pull request head
  signoff watch                    sign every unsigned open pull request head once`

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := cli(ctx, os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "signoff:", err)
		os.Exit(1)
	}
}

func cli(ctx context.Context, args []string) error {
	if len(args) == 0 || (args[0] != "run" && args[0] != "watch") {
		return errors.New(usage)
	}
	fs := flag.NewFlagSet("signoff "+args[0], flag.ContinueOnError)
	appID := fs.Int64("app-id", envInt("SIGNOFF_APP_ID", defaultAppID), "GitHub App id (env SIGNOFF_APP_ID)")
	installationID := fs.Int64("installation-id", envInt("SIGNOFF_INSTALLATION_ID", defaultInstallationID), "GitHub App installation id (env SIGNOFF_INSTALLATION_ID)")
	keyFingerprint := fs.String("key-fingerprint", envOr("SIGNOFF_KEY_FINGERPRINT", defaultKeyFingerprint), "GitHub fingerprint (SHA256:...) of the App private key in the login Keychain (env SIGNOFF_KEY_FINGERPRINT)")
	timeout := fs.Duration("timeout", 30*time.Minute, "limit for one `just signoff` run")
	if err := fs.Parse(args[1:]); err != nil {
		return err
	}
	wantArgs := map[string]int{"run": 2, "watch": 0}[args[0]]
	if fs.NArg() != wantArgs {
		return errors.New(usage)
	}
	if *appID <= 0 || *installationID <= 0 {
		return errors.New("--app-id and --installation-id must be positive")
	}
	if *keyFingerprint == "" {
		return errors.New("--key-fingerprint (or SIGNOFF_KEY_FINGERPRINT) is required: copy the private key's SHA256 fingerprint from the App settings page")
	}
	token, err := readToken(ctx)
	if err != nil {
		return err
	}
	u, err := user.Current()
	if err != nil {
		return err
	}
	path := trustedPath
	if path == "" {
		path = defaultTrustedPath(u.Username)
	}
	s := &Signer{
		APIBase:        apiBase,
		ReadToken:      token,
		GitBase:        "https://github.com/",
		AppID:          *appID,
		InstallationID: *installationID,
		Sign:           keychainSigner(filepath.Join(u.HomeDir, "Library/Keychains/login.keychain-db"), *keyFingerprint),
		Path:           path,
		Home:           u.HomeDir,
		MirrorDir:      filepath.Join(u.HomeDir, ".cache/signoff/mirrors"),
		LogDir:         filepath.Join(u.HomeDir, ".local/state/signoff"),
		Timeout:        *timeout,
		Out:            os.Stderr,
	}
	if args[0] == "watch" {
		return s.Watch(ctx)
	}
	res, err := s.Run(ctx, fs.Arg(0), fs.Arg(1))
	if err != nil {
		return err
	}
	fmt.Printf("%s %s\nlog: %s\n", res.Conclusion, res.CheckURL, res.LogPath)
	if res.Conclusion != "success" {
		return errors.New("checks failed")
	}
	return nil
}

// readToken returns the captain's gh token, used only to read PR and repo facts.
func readToken(ctx context.Context) (string, error) {
	for _, name := range []string{"GH_TOKEN", "GITHUB_TOKEN"} {
		if token := os.Getenv(name); token != "" {
			return token, nil
		}
	}
	out, err := exec.CommandContext(ctx, "gh", "auth", "token").Output()
	if err != nil {
		return "", fmt.Errorf("gh auth token: %w", err)
	}
	return strings.TrimSpace(string(out)), nil
}

func envInt(name string, fallback int64) int64 {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	n, _ := strconv.ParseInt(value, 10, 64)
	return n
}

func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
