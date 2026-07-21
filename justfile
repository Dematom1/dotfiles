# Dotfiles maintenance tasks - run `just` (or `just --list`).

skills-dir := ".agents/skills"

# AXI agent tools (npm globals, https://axi.md) relevant to this stack:
# github, chrome, k8s, postgres, docker, npm + FirstMate's lavish/tasks/quota.
axi-tools := "gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi kubernetes-axi pg-axi docker-axi npm-axi"

# work-machine-only AXI tools - installed by setup/update-firstmate only when
# ~/.config/dotfiles-profile says "work" (the same marker rebuild.sh reads).
axi-tools-work := "slack-axi aws-axi gws-axi notion-axi"

# AXI tools installed from GitHub (npm install owner/repo). The binary name is
# the repo (basename of the spec), which is what `setup hooks` runs.
axi-tools-git := "nikolauska/linear-axi"

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
    git clone --quiet --depth 1 https://github.com/DrCatHicks/learning-opportunities.git "$tmp/lo"
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

    echo "==> npx skills CLI (whathappened + vercel-labs)"
    npx -y skills add kunchenguid/whathappened -g
    npx -y skills add vercel-labs/agent-skills -g
    npx -y skills add vercel-labs/skills -g

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

# Refresh ~/.secrets from 1Password (needs `op signin` first).
refresh-secrets:
    op inject -f -i ~/Code/dotfiles/zsh/secrets.tpl -o ~/.secrets
    @echo "✓ ~/.secrets refreshed"

# Bring a fresh machine fully online. Run the two interactive prereqs first:
#   ./rebuild.sh          # nix: install tools + activate symlinks (needs sudo)
#   op signin             # 1Password
# then `just bootstrap` does the rest: secrets + FirstMate stack + every skill.
bootstrap: refresh-secrets setup-firstmate update-skills
    @echo "Bootstrap done. If GitHub isn't authed yet: gh auth login"

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
    npm install -g {{axi-tools}}
    # each AXI tool installs its agent hooks via `setup hooks`; report per tool
    # (a few legitimately have no such subcommand)
    echo "==> AXI setup hooks"
    for t in {{axi-tools}}; do
      "$t" setup hooks >/dev/null 2>&1 && echo "    ✓ $t" || echo "    - $t (no setup hooks)"
    done

    # AXI tools installed from GitHub (npm spec != binary name)
    echo "==> GitHub AXI tools"
    for spec in {{axi-tools-git}}; do
      npm install -g "$spec"
      bin="$(basename "$spec")"
      "$bin" setup hooks >/dev/null 2>&1 && echo "    ✓ $bin" || echo "    - $bin (no setup hooks)"
    done

    # work-only AXI tools (same ~/.config/dotfiles-profile marker rebuild.sh reads)
    profile=personal
    if [[ -f ~/.config/dotfiles-profile ]]; then profile="$(<~/.config/dotfiles-profile)"; fi
    if [[ "$profile" == work ]]; then
      echo "==> work-only AXI tools (slack/aws/gws/notion)"
      npm install -g {{axi-tools-work}}
      for t in {{axi-tools-work}}; do
        "$t" setup hooks >/dev/null 2>&1 && echo "    ✓ $t" || echo "    - $t (no setup hooks)"
      done
    fi

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
    npm update -g {{axi-tools}} gnhf
    for t in {{axi-tools}}; do "$t" setup hooks >/dev/null 2>&1 || true; done   # refresh hooks
    if [[ -f ~/.config/dotfiles-profile && "$(<~/.config/dotfiles-profile)" == work ]]; then
      npm update -g {{axi-tools-work}}
      for t in {{axi-tools-work}}; do "$t" setup hooks >/dev/null 2>&1 || true; done
    fi
    for spec in {{axi-tools-git}}; do npm install -g "$spec"; "$(basename "$spec")" setup hooks >/dev/null 2>&1 || true; done
    herdr integration install pi   # refresh Pi integration after a herdr update
    echo "FirstMate stack updated."
