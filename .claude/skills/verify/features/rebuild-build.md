# Rebuild build and activation wiring

`just rebuild` resolves the profile, checks the macOS account, then runs
`sudo darwin-rebuild switch --flake ~/Code/dotfiles#<profile>`. This feature
covers everything that switch would build, without the switch.

## Sub-features

- Profile selection from `~/.config/dotfiles-profile`, with `personal` as the default.
- The account guard: `darwinConfigurations.<profile>.config.system.primaryUser`
  must equal `id -un`.
- The `darwinConfigurations.<profile>.system` closure builds.
- The flake `checks.<arch>.*` build: `kubernetes-axi-doctor`,
  `agent-tools-layout`, and `signoff-install`.
- The generated `activate` program is the exact program `darwin-rebuild switch`
  executes; its Home Manager activation headers give execution order. The check
  requires `writeBoundary` -> `m87GithubDiscovery` -> `m87DaemonHandoff` ->
  `setupLaunchAgents`, so the managed job is not loaded before daemon handoff.
- The m87 plist is parsed semantically and must have the expected label, state
  directory, and final `m87 daemon run` arguments.
- The generation ships `LaunchAgents/org.nix-community.home.m87.plist` with
  state in `~/.m87`, plus the `home-path/bin/av` wrapper.

## How to get to it (user POV)

From the dotfiles checkout, run `just rebuild` (or `just rebuild work`). The
user sees a sudo prompt, then the nix-darwin and Home Manager activation logs.

## Driving it with build.sh

```bash
.claude/skills/verify/scripts/build.sh "$OUT/build" personal
```

The journey passes when every `build ...: PASS` line prints and
`$OUT/build/build.env` names `SYSTEM` and `GENERATION`. The script also reports
whether `/run/current-system` matches the build, to show what a rebuild would
change.

## Gotchas

- `nix build` of `.system` is what `darwin-rebuild build` does. Neither command
  activates anything, and neither needs sudo.
- Only Git-tracked files enter the flake. `git add` new files first, or they
  are silently missing from the build.
- Building `work` on the personal Mac works, but the account guard prints a
  NOTE because `just rebuild work` would refuse there.
- The system-level activation (`configuration.nix` `system.activationScripts`,
  Homebrew, and the `/usr/local/bin/av` copy) is built but never executed here.
