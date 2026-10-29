# `av` Firstmate-policy launcher

Home Manager installs an `av` wrapper (`home.nix` `avProjectPolicy`) ahead of
the signed `/usr/local/bin/av`. The wrapper unsets `AV_VENDOR_CLI`, then runs
`scripts/av-firstmate-policy.sh`. The policy execs the vendor CLI unchanged
only inside a registered canonical clone, `~/Code/dotfiles`, the canonical
`~/Code/infrastructure` (dematom-labs origin, no task), or a Firstmate worker
copy bound by `$FM_HOME/state/<task>.meta` and Git's worktree record.
Everywhere else it exits 126 with `av unavailable: <reason>`.

## Sub-features

- The wrapper drops a caller-supplied `AV_VENDOR_CLI`, and its store policy is
  byte-identical to the repo copy.
- Allow cases: the canonical dotfiles clone, a registered project, a
  symlinked spelling of an allowed path, a bound isolated worktree including
  subdirectories, and the canonical infrastructure clone with an HTTPS or SSH
  origin. Arguments are forwarded unchanged.
- Refuse cases: an arbitrary directory, an unregistered repo, a lookalike, an
  isolated copy without a task, path, symlink, or common-dir spoofed task
  metadata, a task-marked infrastructure clone, a wrong, old, or ambiguous
  infrastructure origin, a symlinked or linked-worktree infrastructure clone,
  and every Git environment escape (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_CONFIG*`,
  `GIT_CONFIG_PARAMETERS`, `GIT_COMMON_DIR`, and others).

## How to get to it (user POV)

In any shell after `just rebuild`, `command -v av` prints the Home Manager
wrapper. Running `av --version` or `av inject ...` inside or outside a project
either reaches Automic Vault or prints `av unavailable: ...`.

## Driving it with av-launcher.sh

```bash
.claude/skills/verify/scripts/av-launcher.sh "$GENERATION" "$OUT/av"
```

1. Reads `$GENERATION/home-path/bin/av` and checks the `unset AV_VENDOR_CLI`
   line and the store policy path.
2. Runs `AV_POLICY=<store policy> tests/av-project-policy.sh`: the full
   allow/refuse fixture on synthetic repos against the built script, with a
   recording vendor stub.
3. Runs the installed wrapper itself under `env -i HOME=<synthetic>` for
   refusals. Each must exit 126 with `av unavailable:`.

## Gotchas

- Allow cases never go through the wrapper. The wrapper always execs the real
  signed `/usr/local/bin/av`, which this skill does not run. They run the
  built policy with `AV_VENDOR_CLI=<stub>` instead.
- If a wrapper refusal regresses into an allow, the wrapper execs the real
  vendor with only `--version`. The journey then fails on exit 0.
- The policy suite at commit 389f4c4^ (before the Git environment hardening)
  fails with `environment override GIT_CONFIG was allowed`. That proves the
  suite catches the escape.
