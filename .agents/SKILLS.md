# Skills

One agent-agnostic skill set lives in `.agents/skills/` (SKILL.md dirs). Every
agent reads the same source:

- Claude   -> `~/.claude/skills` symlinks to `.agents/skills` (see `home.nix`)
- opencode -> per-skill symlinks in `opencode/skills/`

Edit a skill and both agents see it live (no rebuild - it's `mkOutOfStoreSymlink`).

## Maintaining

- `just skills`        - list installed skills + descriptions
- `just check-skills`  - validate each has a SKILL.md with name + description
- `just update-skills` - refresh EVERY skill from source, then `git diff` + commit

Vendored skills are excluded from the whitespace/eof pre-commit hooks, so a
re-fetch produces a clean diff (only real upstream changes) instead of noise.

## Provenance

| Skill | Type | Source | Update with |
|---|---|---|---|
| learning-opportunities | git repo | `git@github.com:DrCatHicks/learning-opportunities.git` | `just update-skills` |
| memtrace-* (opencode)  | tool-generated | memtrace (`memtrace doctor --fix --repair-install`) | `just update-skills` |
| ui.sh (pending)        | authed npx | `@uidotsh/install` (token in `~/.secrets`) | `just update-skills` |

The memtrace-* skills declare `compatibility: opencode` and stay in
`opencode/skills/`; memtrace owns them, so they are not shared into Claude.

## Adding a new skill

All shared skills land in `.agents/skills` so they stay agent-agnostic. Pick the
lane by how the skill is delivered, then add its refresh step to
`just update-skills`:

1. **Public git repo** -> clone + rsync into `.agents/skills/<name>` inside
   `update-skills` (keeps everything one command). Alternative: pin it as a flake
   input and `nix flake update <name>` - more reproducible, but no longer one command.
2. **Authed / npx installer** (like ui.sh) -> a step that sources the token from
   `~/.secrets` and runs the installer.
3. **Tool-generated** (like memtrace) -> call the tool's reinstall command.
4. **Your own** -> create `.agents/skills/<name>/SKILL.md` and edit in place.

Then add a row to the Provenance table so it is never lost.
