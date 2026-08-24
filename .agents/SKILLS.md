# Skills

The shared agent-agnostic skill set lives in `.agents/skills/` (SKILL.md dirs).
Each configured agent reads that source:

- Claude   -> `~/.claude/skills` resolves to `.agents/skills` (see `home.nix`)
- Pi        -> the skills CLI copies compatible skills into Pi's global discovery surface
- opencode -> managed per-skill symlinks in `opencode/skills/` (created by `just update-skills`, without replacing tool-managed entries)

All all-agent `skills add` commands use `--copy`. Claude's Home Manager-owned
skills root is itself a symlink, so generated relative leaf links can point back
to themselves; physical generated copies avoid that self-loop.

## Not committed - regenerated from source

The skill *content* is gitignored (`.agents/skills/*`, `opencode/skills/*`); only
the recipe, wiring, and this doc are committed - like committing `package.json`,
not `node_modules`. This keeps authenticated or licensed skills (ui.sh) out
of this public repo. The update recipe is reproducible, while ui.sh
authentication stays a manual entry in the installer's masked prompt.

Reproduce on a fresh machine:

1. `./rebuild.sh`     # nix: install tools, activate symlinks
2. `op signin`        # 1Password
3. `just bootstrap`   # secrets + FirstMate stack + skills

Enter the ui.sh token manually when its masked prompt appears.

## Maintaining

- `just skills`        - list installed skills + descriptions
- `just check-skills`  - validate each has a SKILL.md with name + description
- `just update-skills` - refresh EVERY skill from source and re-wire only the opencode links that target `.agents/skills`

## Provenance

| Skill | Type | Source | Auth |
|---|---|---|---|
| learning-opportunities | git repo | `https://github.com/DrCatHicks/learning-opportunities.git` | none (public) |
| ui.sh (design, ideas, ...) | authenticated npx | `@uidotsh/install` | manual entry in the masked prompt |
| vision | git repo (skills CLI) | `npx -y skills add kunchenguid/vision -g -y --agent '*' --copy` | none (MIT) |
| teach | git repo (skills CLI) | `mattpocock/skills:teach` via `npx -y skills add mattpocock/skills --skill teach -g -y --agent '*' --copy` | none |
| show-me | git repo (skills CLI) | `humanlayer/skills:show-me` via `npx -y skills add humanlayer/skills --skill show-me -g -y --agent '*' --copy` | none |
| whathappened | git repo (skills CLI) | `npx -y skills add kunchenguid/whathappened -g -y --agent '*' --copy` | none |
| vercel-labs skills | skills CLI | `npx -y skills add <source> -g -y --agent '*' --copy` for `vercel-labs/agent-skills` and `vercel-labs/skills` | none |
## Adding a new skill

Add its refresh step to `just update-skills` so one command keeps everything
current, then add a Provenance row. Sources fall into: public git repo (clone),
authenticated npx installer (manual masked prompt), or tool-generated (call the tool).
For a hand-authored skill you want to keep, `git add -f .agents/skills/<name>` -
the dir is gitignored, so tracking a first-party skill is a deliberate force-add.
