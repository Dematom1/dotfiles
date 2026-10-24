# Skills

The shared agent-agnostic skill set lives in `.agents/skills/` (SKILL.md dirs).
The maintained agent surfaces discover those skills as follows:

- Claude   -> `~/.claude/skills` resolves to `.agents/skills` (see `home.nix`)
- Codex    -> reads `.agents/skills` directly
- Pi        -> reads the skills CLI's shared global copies in `~/.agents/skills`
- opencode -> managed per-skill symlinks in `opencode/skills/` (created by `just update-skills`, without replacing tool-managed entries)

Every `skills add` command targets only Claude Code, Codex, OpenCode, and Pi and
uses `--copy`. Eve and PromptScript are intentionally excluded. Claude's Home
Manager-owned skills root is itself a symlink, so generated relative leaf links
can point back to themselves; physical generated copies avoid that self-loop.
Bundles shared by Codex, OpenCode, and Pi omit Claude Code (`skill-agents-shared`) to
keep Claude's budget-capped skill listing small.

## Not committed - regenerated from source

The skill *content* is gitignored (`.agents/skills/*`, `opencode/skills/*`); only
the recipe, wiring, and this doc are committed - like committing `package.json`,
not `node_modules`. The sources installed by `just update-skills` are public;
the recipe fetches their current content rather than pinning a snapshot.

Reproduce on a fresh machine:

1. `./rebuild.sh`     # nix: install tools, activate symlinks
2. `op signin`        # 1Password
3. `just bootstrap`   # secrets + FirstMate stack + skills

## Maintaining

- `just skills`        - list installed skills + descriptions
- `just check-skills`  - validate each has a SKILL.md with name + description
- `just update-skills` - refresh the sources below and re-wire only the opencode links that target `.agents/skills`

## Provenance

All rows are installed by `just update-skills` through the skills CLI.

| Skill | Agents | Source | Auth |
|---|---|---|---|
| no-mistakes | all four | `kunchenguid/no-mistakes` | none |
| vision | all four | `kunchenguid/vision` | none (MIT) |
| teach, codebase-design, diagnosing-bugs, domain-modeling, grill-me, grill-with-docs, grilling, improve-codebase-architecture | all four | `mattpocock/skills` (`mattpocock-skills` in `justfile`) | none |
| show-me | all four | `humanlayer/skills:show-me` | none |
| whathappened | all four | `kunchenguid/whathappened` | none |
| lavish | all four | `kunchenguid/lavish-axi:lavish` | none |
| axi | Codex, OpenCode, Pi | `kunchenguid/axi:axi` | none |
| impeccable | Codex, OpenCode, Pi | `pbakaus/impeccable` | none |

Tool-owned skills stay with their owner: `rex` (written by the Rex app),
Ponytail (`just _setup-ponytail`), and the claude.ai account skills.

## Adding a new skill

Add its refresh step to `just update-skills` so one command keeps everything
current, then add a Provenance row. Sources fall into: public git repo (skills
CLI) or tool-generated (call the tool).
For a hand-authored skill you want to keep, `git add -f .agents/skills/<name>` -
the dir is gitignored, so tracking a first-party skill is a deliberate force-add.
