# Dotfiles maintenance tasks - run `just --list`.

# Refresh the ui.sh skill (authed npx installer). The token is read from
# ~/.secrets (never hardcoded, never committed). Because ~/.claude/skills is a
# symlink to .agents/skills, a Claude-targeted install lands in the shared,
# agent-agnostic dir and opencode picks it up too.
#
# IMPORTANT: run `./rebuild.sh` first so ~/.claude/skills is the symlink,
# otherwise the skill installs into a plain dir and won't be shared/tracked.
# After running, review + commit:  git diff .agents/skills
update-ui-skill:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -f ~/.secrets ]] && source ~/.secrets
    : "${UIDOTSH_TOKEN:?UIDOTSH_TOKEN not set - run refresh-secrets first}"
    npx -y @uidotsh/install --token="$UIDOTSH_TOKEN"
    echo
    echo "Done. Review what changed:  git status .agents/skills"
