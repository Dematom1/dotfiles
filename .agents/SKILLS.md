# Skills

One agent-agnostic skill set lives in `.agents/skills/` (SKILL.md dirs). Every
agent reads the same source:

- Claude   -> `~/.claude/skills` symlinks to `.agents/skills` (see `home.nix`)
- opencode -> per-skill symlinks in `opencode/skills/`

Edit a skill and both agents see it live (no rebuild - it's `mkOutOfStoreSymlink`).

## Maintaining

- `just skills`        - list installed skills + descriptions
- `just check-skills`  - validate each has a SKILL.md with name + description
- `just update-skills` - refresh everything from source, then `git diff` + commit

Vendored skills are excluded from the whitespace/eof pre-commit hooks, so a
re-fetch produces a clean diff (only real upstream changes) instead of noise.

## Provenance

| Skill | Type | Source | Update with |
|---|---|---|---|
| learning-opportunities | vendored | TODO: fill in upstream | edit in place / re-vendor || ui.sh skill (pending)  | authed npx | `@uidotsh/install` (token in `~/.secrets`) | `just update-ui-skill` |
| memtrace-* (opencode)  | 34 skills | TODO: repo (flake pin) or tokensave-generated? | TBD |

## Adding a new skill

Pick the lane by how the skill is delivered - all three land in `.agents/skills`
so they stay agent-agnostic:

1. **Public git repo** -> pin it in `flake.nix`:
   `inputs.<name> = { url = "github:owner/repo"; flake = false; };`
   symlink it into `.agents/skills`, update with `nix flake update <name>`.
2. **Authed / npx installer** (like ui.sh) -> add a `just update-<name>` recipe
   that sources the token from `~/.secrets` and installs into `~/.claude/skills`.
3. **Your own** -> create `.agents/skills/<name>/SKILL.md` and edit in place.

Then add a row to the table above so provenance is never lost.
