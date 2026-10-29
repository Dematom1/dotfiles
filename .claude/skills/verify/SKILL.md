---
name: verify
description: Verify this nix-darwin + Home Manager dotfiles repo the way `just rebuild` uses it - build the darwin system without switching, drive the m87 daemon handoff activation step against a scratch HOME with real Nix m87 daemons, and drive the managed `av` Firstmate-policy launcher on synthetic repos. Use before shipping any change to flake.nix, home.nix, configuration.nix, hosts/, modules/, scripts/m87-*, scripts/av-*, or rebuild.sh, and whenever a rebuild breaks.
---

# Verify the dotfiles

The product is `just rebuild` (`rebuild.sh` -> `sudo darwin-rebuild switch`).
Its failures show up only at activation on the real Mac, so this skill builds
the exact system that rebuild would switch to and drives its activation steps
in isolation. It never switches or activates the live system, never touches the
live `~/.m87` or `~/Code/infrastructure`, never runs the signed `/usr/local/bin/av`,
and never reads secrets.

Hard rules for every run:

- Never run `just rebuild`, `./rebuild.sh`, `darwin-rebuild switch|activate`, the
  generation's `activate` script, or `/bin/launchctl` against `gui/<uid>`.
- Run the m87 handoff only through `scripts/m87-handoff.py`. Its exact-command
  scenarios run only where the script provably returns before any launchctl call.
  The full cutover goes through `scripts/fake-launchctl.py`, which refuses any
  job that still references the real home.
- Untracked files are invisible to the flake. `git add` new Nix inputs before
  building.

## Launch

There is no server. Launch means building the system closure once:

```bash
.claude/skills/verify/scripts/build.sh OUT_DIR [personal|work]
```

The profile defaults to `~/.config/dotfiles-profile`, as `rebuild.sh` uses it.
The build is ready when it prints `build darwin system: PASS (/nix/store/...)`
and writes `OUT_DIR/build.env` with `SYSTEM=` and `GENERATION=`, the Home
Manager generation inside that system. Each later journey takes `GENERATION`.
To verify another commit without a second checkout, build it from its git ref:
`nix build "git+file://$PWD?rev=<sha>#darwinConfigurations.personal.system" --no-link --print-out-paths`,
then take its generation with `nix-store -qR <system> | grep -- '-home-manager-generation$'`.

## Doctor

Run these read-only checks first, and again whenever anything looks off:

```bash
nix --version && git -C "$PWD" rev-parse --show-toplevel   # nix present, inside this repo
readlink /run/current-system                                # live system, for comparison only
test "$(nix eval --raw .#darwinConfigurations.personal.config.system.primaryUser)" = "$(id -un)"
```

If the last check fails, this Mac uses the other profile. Pass `work` or
`personal` explicitly. Building still works, but `just rebuild` would refuse.

## Drive

Run everything with one command. It prints one `PASS`/`FAIL` line per journey
and exits non-zero on any failure:

```bash
DOTFILES_VERIFY_OUT=/some/evidence/dir .claude/skills/verify/scripts/verify.sh [personal|work]
```

Or run one journey against a built generation:

```bash
python3 .claude/skills/verify/scripts/m87-handoff.py "$GENERATION" OUT_DIR [noop dry-run handoff slow-sync]
.claude/skills/verify/scripts/av-launcher.sh "$GENERATION" OUT_DIR
```

Each feature is described in [features/README.md](features/README.md). The
fast unit layer is `just check-regressions`. It tests the working-tree scripts,
not the built generation, so it does not replace these journeys.

Expected runtime is about 2 minutes when the closure is cached. The
`slow-sync` scenario alone takes about 65 s by design.

## Evidence

`verify.sh` writes to `$DOTFILES_VERIFY_OUT/<UTC stamp>/`. The default is
`~/.cache/dotfiles-verify`. Keep evidence outside the repo.

- `summary.txt`: every PASS/FAIL line. Paste this into a PR.
- `build/`: `build.env`, `build.log`, `activation-order.txt`, and `checks.log`.
- `m87-<scenario>/`: `transcript.log` (every command and its output),
  `before.json`/`after.json` (plugin rows, daemon PIDs, plist, package, and shim
  presence), `launchctl-calls.log`, `gh-calls.log`, daemon logs, and `result.json`.
- `av/`: `av-wrapper.sh`, `policy-suite.log`, and `wrapper-refusals.log`.

Proof standard: a journey passes only on the observed end state. For m87, the
observed state is which PID owns `~/.m87/daemon.pid`, the repointed plugin rows,
and the retired files. For av, it is the exit code 126, the refusal message, and
whether the vendor stub was reached. GitHub is faked only through m87's own
`M87_GH_BIN` boundary. launchd is faked because the real one is the live
system. If a journey fails, report it with its evidence. Never weaken a journey
to make it pass.

## Cleanup

Each m87 scenario creates a scratch HOME at `/tmp/dfv.*`, and its teardown boots
out only the jobs it bootstrapped. Its last resort kills only processes whose
command line contains that unique scratch path, then removes the scratch HOME
after copying the logs into the evidence directory. `av-launcher.sh` and the
policy suite remove their `mktemp` trees on exit. Builds use `--no-link`, so
they leave no `result` symlink. If a run was interrupted, clean up with:

```bash
for h in /tmp/dfv.*; do pgrep -f "$h" | xargs -r kill; rm -rf "$h"; done
```

Evidence directories are never removed by cleanup.

## Helpers

All of these live in `.claude/skills/verify/scripts/` and are executable:

| Script | Invocation |
| --- | --- |
| `verify.sh` | `verify.sh [profile]` runs all journeys |
| `build.sh` | `build.sh OUT_DIR [profile]` builds the system and checks, writes `build.env` |
| `m87-handoff.py` | `m87-handoff.py GENERATION OUT_DIR [scenario...]` |
| `fake-launchctl.py` | used by `m87-handoff.py` through `FAKE_LAUNCHD_*` env, never run by hand |
| `av-launcher.sh` | `av-launcher.sh GENERATION OUT_DIR` |

Keep the feature map honest with `/maintain-verification-skill`.
