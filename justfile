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

# All-in-one: refresh EVERY skill from its source (see .agents/SKILLS.md),
# then run `just check-skills` and review with `git diff` before committing.
update-skills:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "==> learning-opportunities  (git: DrCatHicks/learning-opportunities)"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    git clone --quiet --depth 1 git@github.com:DrCatHicks/learning-opportunities.git "$tmp/lo"
    skillmd=$(find "$tmp/lo" -name SKILL.md -not -path '*/.git/*' | head -1)
    [[ -n "$skillmd" ]] || { echo "ERROR: no SKILL.md found in the repo"; exit 1; }
    rsync -a --delete --exclude '.git' "$(dirname "$skillmd")/" {{skills-dir}}/learning-opportunities/

    echo "==> memtrace-* skills  (opencode; memtrace owns these)"
    # memtrace's documented reinstall path. NOTE: also resets its runtime state,
    # so you may need `memtrace start` afterwards. Adjust if you have a lighter cmd.
    memtrace doctor --fix --repair-install

    echo "==> ui.sh skill  (authed npx installer; token from ~/.secrets)"
    [[ -f ~/.secrets ]] && source ~/.secrets
    : "${UIDOTSH_TOKEN:?UIDOTSH_TOKEN not set - run refresh-secrets first}"
    npx -y @uidotsh/install --token="$UIDOTSH_TOKEN"

    echo "==> whathappened skill (skills CLI)"
    npx -y skills add kunchenguid/whathappened -g

    echo "==> wire shared skills into opencode (regenerated, not committed)"
    for d in {{skills-dir}}/*/; do
      [[ -d "$d" ]] || continue
      n=$(basename "$d")
      ln -sfn "../../{{skills-dir}}/$n" "opencode/skills/$n"
    done

    echo
    echo "All updated (skill content is gitignored). Validate:  just check-skills"

# Refresh ONLY the ui.sh skill (authed npx installer). Token from ~/.secrets.
update-ui-skill:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -f ~/.secrets ]] && source ~/.secrets
    : "${UIDOTSH_TOKEN:?UIDOTSH_TOKEN not set - run refresh-secrets first}"
    npx -y @uidotsh/install --token="$UIDOTSH_TOKEN"
    echo "Done. Review:  git status {{skills-dir}}"

# ---------------------------------------------------------------------------
# FirstMate + Herdr + Pi agent stack. These are npm globals + curl installers
# that self-update; the base deps (git/gh/jq/node/curl) come from nix. Tools
# install to ~/.local/bin (already on PATH via zsh/init.zsh).
# ---------------------------------------------------------------------------

# Update EVERYTHING in one shot - skills + the FirstMate stack.
update: update-skills update-firstmate
    @echo "Everything updated."

# One-time setup of the FirstMate stack. Re-runnable. Run `gh auth login` after.
setup-firstmate:
    #!/usr/bin/env bash
    set -euo pipefail
    set +h   # don't cache command locations - we install tools then use them
    for c in git gh jq node npm curl; do
      command -v "$c" >/dev/null || { echo "missing base dep: $c (add in nix + ./rebuild.sh)"; exit 1; }
    done

    # keep global npm installs user-owned (nix's node can't write to its store)
    mkdir -p "$HOME/.local/bin"
    npm config set prefix "$HOME/.local"

    echo "==> Pi + Herdr"
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
    curl -fsSL https://herdr.dev/install.sh | sh
    herdr integration install pi

    echo "==> Treehouse + No Mistakes + AXI tools"
    curl -fsSL https://kunchenguid.github.io/treehouse/install.sh | sh
    curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh
    npm install -g gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi
    gh-axi setup hooks
    chrome-devtools-axi setup hooks
    lavish-axi setup hooks

    echo "==> extra global npm tools"
    npm install -g gnhf

    ws="$HOME/kun-agent-workspace"
    echo "==> workspace: $ws"
    if [[ ! -d "$ws/.git" ]]; then
      git clone https://github.com/kunchenguid/firstmate.git "$ws"
    fi
    mkdir -p "$ws/config"
    printf 'herdr\n' > "$ws/config/backend"
    printf 'pi\n'    > "$ws/config/crew-harness"

    echo
    echo "Done. Next:  gh auth login   then   cd $ws && herdr   (run 'pi' in pane 1)"

# Update the FirstMate stack via each tool's native updater (guide's order).
update-firstmate:
    #!/usr/bin/env bash
    set -euo pipefail
    set +h   # don't cache command locations (updaters may replace binaries)
    ws="$HOME/kun-agent-workspace"
    if [[ -d "$ws/.git" ]]; then git -C "$ws" pull --ff-only; fi
    pi update --self
    herdr update
    treehouse update
    no-mistakes update
    npm update -g gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi gnhf
    herdr integration install pi   # refresh Pi integration after a herdr update
    echo "FirstMate stack updated."
