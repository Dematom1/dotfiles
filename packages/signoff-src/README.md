# signoff

`signoff` posts the `local-signoff` check run that pull requests in `dematom-labs` repositories are meant to require. It posts only after it has itself run the repository's trusted `just signoff` recipe on a fresh checkout of the exact pull request head. The check run comes from a dedicated GitHub App whose private key never leaves the macOS Keychain.

It is a local tool, not a reusable workflow. It does not widen the shared CI contract.

## Commands

```bash
signoff run <owner/repo> <sha>   # sign one open pull request head
signoff watch                    # sign every unsigned open pull request head once
```

| Flag | Environment | Default | Meaning |
|---|---|---|---|
| `--app-id` | `SIGNOFF_APP_ID` | `5460531` | GitHub App id of `dematom-local-signoff` |
| `--installation-id` | `SIGNOFF_INSTALLATION_ID` | `174959222` | The App's `dematom-labs` installation |
| `--key-fingerprint` | `SIGNOFF_KEY_FINGERPRINT` | `SHA256:tlF5N8zgxWi5AR2FZdYPcRdbm8C1Dk4LkwsMp77A4Uk=` | GitHub fingerprint of the App private key in the login Keychain |
| `--timeout` | | `30m` | Limit for one `just signoff` run |

Reads (repository, pull request, and default-branch facts) use the captain's token from `GH_TOKEN`, `GITHUB_TOKEN`, or `gh auth token`. Cloning uses the git credential helper configured in `~/.gitconfig`, such as `gh auth setup-git`. The home directory comes from the user database, not `$HOME`. Mirrors live in `~/.cache/signoff/mirrors`. Full logs are kept in `~/.local/state/signoff/<owner>/<repo>/<sha>.log`. `XDG_*` variables are ignored.

## Environment

`git`, `just`, and the recipe never inherit the caller's environment. Each gets only these variables: `PATH` (the trusted `PATH`), `HOME` (the home directory), `TMPDIR` (a per-run directory), and `LANG` and `LC_ALL` (`C.UTF-8`). `git` also gets `GIT_TERMINAL_PROMPT=0`. No caller variable passes through, so the caller's `PATH`, `GIT_*`, `DYLD_*`, `NODE_OPTIONS`, `GH_TOKEN`, and `GITHUB_TOKEN` have no effect.

The trusted `PATH` is `/run/current-system/sw/bin:/etc/profiles/per-user/<user>/bin:/usr/bin:/bin`, with `<user>` from the user database. Override it at build time with `-ldflags "-X main.trustedPath=<dir>:<dir>"`. `git`, `just`, and the versioned tools resolve to absolute paths on the trusted `PATH` only, and `run` fails when `git` or `just` is missing there.

`run` exits 0 only when it posted `success`. A posted `failure`, a refusal, and an error all exit non-zero. A refusal posts nothing and never touches the App key.

## What `run` does

1. **Refuses** unless all of these hold:
   - the repository is in the `dematom-labs` org;
   - the SHA is a full commit SHA;
   - the SHA is the current head of an open, same-repository pull request. A stale head and a fork pull request are both refused; fork code is never run.
2. **Reads the trusted recipe.** It fetches `justfile` from the default branch head through the API, never from the pull request, and refuses when there is no justfile or no `signoff` recipe (the repository is not onboarded). The trusted justfile runs from outside the checkout, so it must be self-contained: `import` and `mod` are refused because they do not load.
3. **Makes a fresh checkout.** It updates a per-repository `git clone --mirror`, runs `git clone --shared` into a temporary directory, and checks out the SHA detached. It refuses unless `HEAD` equals the SHA and `git status --porcelain --untracked-files=all --ignored` is empty. For example, a case collision on case-insensitive APFS makes a fresh checkout dirty. Git hooks are disabled for every git call.
4. **Runs** `just --justfile <trusted> --working-directory <checkout> signoff` in its own process group. The timeout kills the whole group.
5. **Posts** a completed `local-signoff` check run on the SHA, with conclusion `success` or `failure` and a random `external_id`. A failure is posted too, so silence never reads as "never ran". An interrupted run (SIGINT or SIGTERM) posts nothing. The summary records:
   - the pull request, head SHA, and tree SHA;
   - the default branch and the commit the recipe came from;
   - `config_sha256` and the manifest it hashes;
   - the recipe's exit code and duration, and `log_sha256` of the full log;
   - the absolute path and version of each tool (`git`, `just`, `ast-grep`, `bun`, `node`, `uv`, `python3`, `go`, `ruby`, whichever are on the trusted `PATH`), the host, and the signer's build revision.

   A failure also carries the last 100 log lines, with every occurrence of the read token replaced by `***`.

The config manifest uses `sha256sum` format. Its first line is the trusted justfile, as `<sha256>  <default-branch-sha>:justfile`. One line follows for each tracked pin or lock file at the head: `.bun-version`, `.node-version`, `.nvmrc`, `.python-version`, `.tool-versions`, `bun.lock`, `bun.lockb`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `uv.lock`, `poetry.lock`, `go.sum`, `Cargo.lock`, or `Gemfile.lock`. These are hashed before the recipe runs. `config_sha256` is the sha256 of the manifest text, so a reviewer or the push-to-main backstop can recompute it.

## What `watch` does

`watch` runs one GraphQL search for `is:pr is:open -is:draft archived:false org:dematom-labs`. For each pull request whose head commit has no `local-signoff` check run from this App, it calls `run`, two at a time. A posted failure counts as signed, so a failing head is not rerun every pass; rerun it with `signoff run`. Run `watch` from a launchd agent with `StartInterval` 120. launchd never overlaps passes of the same job. The search reads the first 100 results only.

## Trust model

The required check is pinned to the App's `integration_id` in the ruleset. Agents hold the captain's `gh` token, which can post any commit status and trigger any workflow. Because of the pin, neither a status nor a GitHub Actions check run named `local-signoff` counts. Only this App's check runs do.

| Attempt | Result |
|---|---|
| Post a status or check run named `local-signoff` with the captain's token or `GITHUB_TOKEN` | Does not satisfy the App-pinned requirement |
| Read the App private key | The key is a non-extractable Keychain item, so no process can export it. The signer signs the App JWT in place with `SecKeyCreateSignature` (RSA PKCS#1 v1.5, SHA-256). Using the key needs the Keychain access list to name the signer binary; any other process gets a GUI prompt an agent cannot click |
| Run `signoff run` | Allowed by design. The only path to `success` is the trusted recipe passing on a fresh checkout of that SHA |
| Run `signoff run` with a fake `just` or `git` first on `PATH`, or with `GIT_*`, `DYLD_*`, or `XDG_*` variables | The caller's environment is ignored. Tools come from the compiled-in trusted `PATH`, and mirrors and logs from the home directory in the user database |
| Redefine `signoff` inside the pull request | The recipe comes from the default branch. Edits to the tests and scripts it calls are in the diff, for review, as in any CI |
| Point the signer at a fake API or another org | The API base URL and the org are compiled in. Flags only select the App id, installation, key fingerprint, and timeout |
| Edit or replace the signer binary | It is installed read-only in `/nix/store`. A rebuilt binary has a different code signature, so the Keychain prompts again |
| Reuse a green check after a new push | The check run is bound to `head_sha`. A new head has no check until it is signed |
| Disable the ruleset or merge with bypass using the captain's admin token | **Not prevented.** That is the ceiling of any design while agents share the owner's token |

The installation token is minted per post, scoped to the one repository, with only `checks: write`, after the recipe has finished. The recipe's processes never see the App key, that token, or the captain's read token.

This stops "claim green without running the checks". It is not a boundary against a hostile process running as the captain. Local signoff also cannot guarantee Linux or x86 parity, a clean machine, or checks that need Actions secrets. The push-to-main cloud backstop catches those after merge, and cloud CI keeps deploy, secret, and Linux-only work.

## App key setup

The App needs `Checks: write` and `Metadata: read` only. Import its private key as a non-extractable key, then delete the downloaded file:

```bash
security import dematom-local-signoff.<date>.private-key.pem -k ~/Library/Keychains/login.keychain-db -t priv -x
rm dematom-local-signoff.<date>.private-key.pem
```

The signer finds the key by the exact fingerprint GitHub shows for it on the App settings page (`SHA256:` and the base64 SHA-256 of the public key's SubjectPublicKeyInfo DER), so the key's label does not matter. It lists the RSA private keys in `~/Library/Keychains/login.keychain-db` without reading key data, reads only each key's public half (`SecKeyCopyPublicKey`), and computes their fingerprints. It signs with the one match and refuses when none matches. It never trial-signs with a candidate, so only the selected key can raise a Keychain prompt. After a key rotation, set the new fingerprint (or update the compiled-in default) and delete the old key.

Once the signer binary is installed, add it to the key's access list, and remove any other entry. Until then, every signature raises a Keychain prompt.

## Development

```bash
cd signoff
gofmt -l .
go vet ./...
go test ./...
```

The tests need `git` and `just` on `PATH`; they pass those directories to the signer as its trusted `PATH`. They use a fake GitHub API, a local origin repository, and a throwaway RSA key in place of the Keychain. On macOS, `keychain_darwin.go` uses cgo with the Security framework. Other platforms build a stub that refuses to sign. CI runs the same commands in [`signoff.yml`](../.github/workflows/signoff.yml).
