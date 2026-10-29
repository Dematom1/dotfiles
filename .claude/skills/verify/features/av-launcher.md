# `av` Firstmate-policy launcher

Home Manager installs an `av` wrapper (`home.nix` `avProjectPolicy`) ahead of
the signed `/usr/local/bin/av`. The wrapper unsets `AV_VENDOR_CLI`, then runs
`scripts/av-firstmate-policy.sh`. The policy execs the vendor CLI unchanged
only inside a registered canonical clone, `~/Code/dotfiles`, the canonical
`~/Code/infrastructure` (dematom-labs origin, no task), or a Firstmate worker
copy bound by `$FM_HOME/state/<task>.meta` and Git's worktree record.
Everywhere else it exits 126 with `av unavailable: <reason>`.

## Sub-features

- The wrapper drops a caller-supplied `AV_VENDOR_CLI`; the allowed-path
  wrapper journey proves it reaches the signed CLI exec without running it.
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

1. Reads `$GENERATION/home-path/bin/av` to locate its store policy path.
2. Runs `AV_POLICY=<store policy> tests/av-project-policy.sh`: the full
   allow/refuse fixture on synthetic repos against the built script, with a
   recording vendor stub.
3. Runs the installed wrapper from an allowed synthetic canonical dotfiles
   clone under a sandbox that denies `/usr/local/bin/av`. It must not invoke
   the caller's recording stub and must show the denied vendor exec.
4. Runs the installed wrapper under `env -i HOME=<synthetic>` for refusals.
   Each must exit 126 with `av unavailable:`.

## Gotchas

- The allowed wrapper case stops at the signed `/usr/local/bin/av` exec,
  which the sandbox denies. The caller's `AV_VENDOR_CLI` stub must not run.
- Wrapper refusal cases expect exit 126 with `av unavailable:`.
- The policy suite at commit 389f4c4^ (before the Git environment hardening)
  fails with `environment override GIT_CONFIG was allowed`. That proves the
  suite catches the escape.
