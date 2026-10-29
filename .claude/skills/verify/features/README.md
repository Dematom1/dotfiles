# Feature map

Each feature is a user-facing behavior of `just rebuild` and the environment it
installs. Each file lists the feature's sub-features, how a user reaches it,
how to drive it with this skill's scripts, and the gotchas.

| Feature | File | Driven by |
| --- | --- | --- |
| Rebuild build and activation wiring | [rebuild-build.md](rebuild-build.md) | `build.sh` |
| m87 daemon handoff activation | [m87-handoff.md](m87-handoff.md) | `m87-handoff.py` + `fake-launchctl.py` |
| `av` Firstmate-policy launcher | [av-launcher.md](av-launcher.md) | `av-launcher.sh` + `tests/av-project-policy.sh` |

These features are not mapped yet: Homebrew/nix-homebrew activation, the
signoff watcher (covered only by the `signoff-install` flake check), the
agentTooling reconcile step, m87-notify, Neovim tooling, and the Linux
`homeConfigurations`/`nixosConfigurations.sandbox` outputs.
