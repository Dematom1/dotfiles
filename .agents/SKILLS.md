# Skills

One agent-agnostic skill set lives in `.agents/skills/` (SKILL.md dirs). Every
agent reads the same source:

- Claude   -> `~/.claude/skills` symlinks to `.agents/skills` (see `home.nix`)
- opencode -> per-skill symlinks in `opencode/skills/` (created by `just update-skills`)

## Not committed - regenerated from source

The skill *content* is gitignored (`.agents/skills/*`, `opencode/skills/*`); only
the recipe, wiring, and this doc are committed - like committing `package.json`,
not `node_modules`. This keeps the authed/licensed skills (ui.sh, memtrace) out of
this public repo, with 1Password + the update recipe as the reproducible source.

Reproduce on a fresh machine:

1. `./rebuild.sh`     # nix: install tools, activate symlinks
2. `op signin`        # 1Password
3. `just bootstrap`   # secrets + FirstMate stack + fetch every skill

## Maintaining

- `just skills`        - list installed skills + descriptions
- `just check-skills`  - validate each has a SKILL.md with name + description
- `just update-skills` - refresh EVERY skill from source (and re-wire opencode)

## Provenance

| Skill | Type | Source | Auth |
|---|---|---|---|
| learning-opportunities | git repo | `https://github.com/DrCatHicks/learning-opportunities.git` | none (public) |
| ui.sh (design, ideas, ...) | authed npx | `@uidotsh/install` | `UIDOTSH_TOKEN` (1Password) |
| whathappened | git repo (skills CLI) | `kunchenguid/whathappened` via `npx skills add -g` | none |
| vercel-labs skills | skills CLI | `vercel-labs/agent-skills`, `vercel-labs/skills` via `npx skills add -g` | none |
| memtrace-* (opencode) | tool-generated | `memtrace doctor --fix --repair-install` | memtrace license |

The memtrace-* skills declare `compatibility: opencode` and stay in
`opencode/skills/`; memtrace owns them, so they are not shared into Claude.

## Adding a new skill

Add its refresh step to `just update-skills` so one command keeps everything
current, then add a Provenance row. Sources fall into: public git repo (clone),
authed/npx installer (token from `~/.secrets`), or tool-generated (call the tool).
For a hand-authored skill you want to keep, `git add -f .agents/skills/<name>` -
the dir is gitignored, so tracking a first-party skill is a deliberate force-add.
