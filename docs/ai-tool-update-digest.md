# AI tool update digest

This is a read-only, allowlisted release collector. It reports candidate
versions and release notes; it never installs, updates, rebuilds, restarts,
logs in, injects credentials, or executes release-note text.

## What is tracked

`ai-tool-update-inventory.json` is the committed source of truth for the
tracked tools. Each entry records its version command, owner, release adapter,
release source, risk, and rollback note. The collector uses only the adapters
listed there:

- global npm packages: `npm list -g --depth=0 --json` and the public npm registry;
- Homebrew: `HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --json=v2`;
- allowlisted GitHub latest releases;
- the four supported native AXI checks: `update --check` for `gh-axi`,
  `lavish-axi`, `quota-axi`, and `chrome-devtools-axi`.

`tasks-axi` has no supported native check and is compared through npm metadata.
Absent or unverified sources remain visible under `Unknown source`.

Release bodies are fetched only after a candidate version is detected. They are
normalized and Markdown-escaped before rendering. Links are taken from the
allowlisted inventory or validated GitHub responses. No release text is passed
to a shell, interpreter, installer, or updater.

## State and output

The state is outside the repository at:

```text
~/.local/state/ai-tool-update-digest/state.json
```

It is mode `0600` and keys observations by `tool|source|version`. A candidate
is recorded when first seen and is marked notified only after its digest is
written. This prevents duplicate notifications while retaining a pending
candidate until the next grouped run.

The scheduled output is:

```text
~/.local/state/ai-tool-update-digest/digest.md
```

The launch agent runs daily at 09:00. Detection is daily, but pending changes
are grouped on Monday. A release whose notes contain security or compatibility
terms produces an immediate alert line. Every digest has these sections:

- `Action required` - security, compatibility, ownership, or runtime-boundary risk;
- `Review` - a candidate needing human inspection;
- `Informational` - low-risk metadata or patch drift;
- `Unknown source` - absent, unreliable, or unavailable release metadata.

## Install the schedule

The launch agent is declared in `configuration.nix` through
`launchd.user.agents`. It is not installed by the collector itself. On the
captain's personal Apple Silicon Mac, from the canonical checkout:

```bash
cd "$HOME/Code/dotfiles"
just rebuild personal
```

For the work profile, use `just rebuild work`. The rebuild is an attended
nix-darwin activation and must be approved separately. It does not run an
update for any tracked tool.

## Verify without changing anything

Run the script self-check and a disposable-state live collection:

```bash
cd "$HOME/Code/dotfiles"
python3 scripts/ai-tool-update-digest.py --self-test
sample_state="$(mktemp -d)"
python3 scripts/ai-tool-update-digest.py \
  --inventory ai-tool-update-inventory.json \
  --state "$sample_state/state.json" \
  --output "$sample_state/digest.md" \
  --force
jq empty "$sample_state/state.json"
grep -E '^## (Action required|Review|Informational|Unknown source)$' "$sample_state/digest.md"
```

Confirm the declarative agent is loaded and the persisted output is readable:

```bash
launchctl print "gui/$(id -u)" | grep -F ai-tool-update-digest
stat -f '%Sp %N' "$HOME/.local/state/ai-tool-update-digest/state.json"
cat "$HOME/.local/state/ai-tool-update-digest/digest.md"
```

The expected state permission starts with `-rw-------`. If the source check is
offline, the digest reports the source under `Unknown source` instead of
retrying with credentials or taking a mutating fallback.

## Manual run and rollback

A manual weekly preview can use a disposable state file:

```bash
cd "$HOME/Code/dotfiles"
tmp="$(mktemp -d)"
python3 scripts/ai-tool-update-digest.py --force \
  --state "$tmp/state.json" \
  --output "$tmp/digest.md"
less "$tmp/digest.md"
```

There is no collector rollback operation because the collector does not modify
tools. To remove the schedule, revert the `launchd.user.agents` declaration and
run the normal attended nix-darwin rebuild. Keep the prior tool binary, package
pin, cask, or Nix closure and follow the rollback note in the digest before any
approved manual change.
