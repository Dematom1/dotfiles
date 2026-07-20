# Dotfiles maintenance tasks - run `just` (or `just --list`).

skills-dir := ".agents/skills"

# Show available tasks.
default:
    @just --list

# List every shared skill with its one-line description.
skills:
    #!/usr/bin/env bash
    set -euo pipefail
    for d in {{skills-dir}}/*/; do
      [[ -f "$d/SKILL.md" ]] || continue
      name=$(basename "$d")
      desc=$(sed -n 's/^description:[[:space:]]*//p' "$d/SKILL.md" | head -1)
      printf '%-30s %s\n' "$name" "${desc:0:70}"
    done

# Health check: every skill dir must have a SKILL.md with name + description.
check-skills:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    for d in {{skills-dir}}/*/; do
      name=$(basename "$d")
      f="$d/SKILL.md"
      if [[ ! -f "$f" ]]; then echo "FAIL $name: no SKILL.md"; fail=1; continue; fi
      grep -q '^name:'        "$f" || { echo "FAIL $name: missing 'name:'"; fail=1; }
      grep -q '^description:' "$f" || { echo "FAIL $name: missing 'description:'"; fail=1; }
    done
    if [[ $fail -eq 0 ]]; then echo "all skills OK"; else exit 1; fi

# Refresh EVERY managed skill from its source (see .agents/SKILLS.md), then
# review with `git diff .agents/skills` and commit.
update-skills: update-ui-skill
    @echo "flake-pinned skills: nix flake update <name>   (none configured yet)"
    @echo "review:  git diff {{skills-dir}}   then commit"

# Refresh the ui.sh skill (authed npx installer). Token is read from ~/.secrets
# (never hardcoded/committed). ~/.claude/skills is a symlink to .agents/skills,
# so a Claude-targeted install lands in the shared dir. Run ./rebuild.sh first.
update-ui-skill:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -f ~/.secrets ]] && source ~/.secrets
    : "${UIDOTSH_TOKEN:?UIDOTSH_TOKEN not set - run refresh-secrets first}"
    npx -y @uidotsh/install --token="$UIDOTSH_TOKEN"
    echo
    echo "Done. Review:  git status {{skills-dir}}"
