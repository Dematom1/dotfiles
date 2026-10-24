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

## Declared, not committed

The skill *content* is gitignored (`.agents/skills/*`, `opencode/skills/*`). The
declared set lives in [agent-tooling.json](../agent-tooling.json): each
`skills.sources` entry names a public source, its skills, and the agents it
targets. Bundles shared by Codex, OpenCode, and Pi omit `claude-code` to keep
Claude's budget-capped skill listing small. `skills.keep` lists skills that a
tool writes itself and that must survive: `rex` (the Rex app), `synced`
(claude.ai account skills). Rex is an explicit app-owned installation exception.
The 16 legacy per-command Impeccable directories are removed with backups;
`pbakaus/impeccable` installs the consolidated `impeccable` skill instead.

`just rebuild` removes any undeclared entry from `~/.claude/skills`,
`~/.agents/skills`, `~/.codex/skills`, and `~/.pi/agent/skills`, backs it up
first, and installs missing declared skills. Before any installer runs, existing
skill directories and the skills CLI lock are snapshotted so a bundle reinstall
cannot overwrite the only copy of a sibling skill. Pi-root skills (`pi.skills`) are
linked by Home Manager from a pinned source. See README.md
"Declarative agent tooling".

Reproduce on a fresh machine:

1. `./rebuild.sh`     # nix: install tools, activate symlinks, install declared skills
2. `op signin`        # 1Password
3. `just bootstrap`   # secrets + FirstMate stack + skills

## Maintaining

- `just skills`        - list installed skills + descriptions
- `just check-skills`  - validate each has a SKILL.md with name + description
- `just update-skills` - reinstall every declared source and re-wire only the opencode links that target `.agents/skills`

## Adding or removing a skill

Add a `skills.sources` entry to `agent-tooling.json` (or delete one), then run
`just rebuild`. Tool-owned skills that dotfiles does not install go in
`skills.keep`. Ponytail's skills come with its plugin and Pi package. The
claude.ai account skills stay on claude.ai.
For a hand-authored skill you want to keep, `git add -f .agents/skills/<name>`
and add its name to `skills.keep.claude`. The dir is gitignored, so tracking a
first-party skill is a deliberate force-add.
