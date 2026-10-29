# m87 daemon handoff activation

The Home Manager step `m87DaemonHandoff` runs
`scripts/m87-remove-npm-daemon.py <nix m87> <generation plist>`. When an npm m87
worker (`com.m87.daemon.*` running `~/.local/lib/node_modules/@kunchenguid/m87`)
still owns `~/.m87`, the step repoints the plugin binaries to Nix, boots the
worker out, bootstraps `org.nix-community.home.m87`, and verifies the daemon,
socket, and a GitHub sync. It then retires the npm files, or rolls everything
back on failure. A failure in this step fails the whole `just rebuild`.

## Sub-features

- `noop`: a normal rebuild with no npm m87 exits 0 silently and changes nothing.
- `dry-run`: with `DRY_RUN=1` and an npm worker present, the step prints the
  plan and changes nothing.
- `handoff`: the full cutover. The Nix daemon owns `~/.m87`, the github plugin
  points into the Nix package, its config and items survive, and the npm
  plist, package, and `~/.local/bin/m87` shim are gone.
- `slow-sync`: the same cutover when GitHub syncs take longer than the 15 s
  that `m87 plugin sync` waits (6 list calls at 4 s each). This is the
  real-machine race in which the CLI returns `sync_requested`, the handoff sees
  no new `last_sync_at`, and every rebuild rolls back and fails. A failure that
  leaves the npm worker in charge is reported as `rollback intact`.
- The `m87GithubDiscovery` block runs before the handoff in the
  `handoff`/`slow-sync` scenarios, as it does on every rebuild.

## How to get to it (user POV)

Run `just rebuild` on a Mac that still has the npm m87 LaunchAgent. On a
migrated Mac, every rebuild runs the step as a no-op.

## Driving it with m87-handoff.py

```bash
python3 .claude/skills/verify/scripts/m87-handoff.py "$GENERATION" "$OUT" noop dry-run handoff slow-sync
```

Each scenario runs in its own `/tmp/dfv.*` HOME. The script reads the exact
python, handoff script, Nix m87 root, plist, and discovery block from
`$GENERATION/activate`. For the cutover, it installs a real npm-layout copy of
the Nix m87 package and starts it as the legacy worker through
`fake-launchctl.py`. It waits for that worker's first sync, then calls the
store script's `migrate()` with `launchctl=fake-launchctl.py`. Both daemons are
real `m87 daemon run` processes. The fake `gh` returns no items after
`M87_FAKE_GH_DELAY` seconds.

A pass requires the end state in `after.json` (`managed_pid == daemon_pid`, no
`legacy_pid`, a repointed `binary`, a newer `last_sync_at`) and the
`Managed M87 daemon and GitHub sync verified` line in `transcript.log`.

## Gotchas

- `slow-sync` is the regression check for #84 ("wait for M87 plugin sync to
  complete"). Before #84 (389f4c4) it FAILS with
  `GitHub sync did not complete successfully` and `rollback intact`, the
  rebuild blocker. With #84 it passes in about 65 s.
- macOS limits Unix socket paths to 104 bytes. The scratch HOME must stay
  short, so it lives under `/tmp`, not in the evidence directory.
- `noop` and `dry-run` run the real `/bin/launchctl` code path. They are safe
  only because the script returns before any launchctl call when no npm
  package and plist exist, or when `DRY_RUN` is set. Never add an exact-command
  scenario that gets past those returns.
- The fake launchd does not restart a job that exits (KeepAlive). After a
  failed handoff, the restored worker is already running because the rollback
  bootstraps it.
- A stub `gh` that returns `[]` for every list call yields zero items, so
  agent triage never runs and the `items` count stays 0. Seeding real items
  would need more of the fake GitHub.
