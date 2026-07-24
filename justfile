# Dotfiles maintenance tasks - run `just` (or `just --list`).

skills-dir := ".agents/skills"

# AXI agent tools (npm globals, https://axi.md) relevant to this stack:
# github, chrome, k8s (kubectl), npm + FirstMate's lavish/tasks/quota.
# (postgres/docker AXI tools aren't published to npm, so they're omitted.)
axi-tools := "gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi kubectl-axi npm-axi"

# work-machine-only AXI tools - installed by setup/update-firstmate only when
# ~/.config/dotfiles-profile says "work" (the same marker rebuild.sh reads).
axi-tools-work := "slack-axi aws-axi gws-axi notion-axi"

# AXI tools installed from GitHub (npm install owner/repo). The binary name is
# the repo (basename of the spec), which is what `setup hooks` runs.
axi-tools-git := ""

# Show available tasks.
default:
    @just --list

# List every shared skill with its one-line description.
skills:
    #!/usr/bin/env bash
    set -euo pipefail
    for d in {{ skills-dir }}/*/; do
      [[ -f "$d/SKILL.md" ]] || continue
      name=$(basename "$d")
      desc=$(sed -n 's/^description:[[:space:]]*//p' "$d/SKILL.md" | head -1)
      printf '%-30s %s\n' "$name" "${desc:0:70}"
    done

# Health check: every skill dir must have a SKILL.md with name + description.
check-skills:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    fail=0
    for d in {{ skills-dir }}/*/; do
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
    rsync -a --delete --exclude '.git' "$(dirname "$skillmd")/" {{ skills-dir }}/learning-opportunities/

    echo "==> npx skills CLI (whathappened + vercel-labs)"
    npx -y skills add kunchenguid/whathappened -g -y --agent '*'
    npx -y skills add vercel-labs/agent-skills -g -y --agent '*'
    npx -y skills add vercel-labs/skills -g -y --agent '*'

    echo "==> wire shared skills into opencode (regenerated, not committed)"
    mkdir -p opencode/skills
    for link in opencode/skills/*; do
      [[ -L "$link" && "$(readlink "$link")" == ../../{{ skills-dir }}/* ]] || continue
      rm -- "$link"
    done
    for d in {{ skills-dir }}/*/; do
      [[ -d "$d" ]] || continue
      n=$(basename "$d")
      destination="opencode/skills/$n"
      [[ ! -e "$destination" && ! -L "$destination" ]] || continue
      ln -s "../../{{ skills-dir }}/$n" "$destination"
    done

    echo
    echo "All updated (skill content is gitignored). Validate:  just check-skills"

# ---------------------------------------------------------------------------
# Machine setup - install Nix, then activate the nix-darwin configuration.
# ---------------------------------------------------------------------------

# Fresh-machine one-shot: install Determinate Nix (if missing), then rebuild.
# Optional PROFILE (personal|work), e.g. `just setup work`, sets the marker first.
setup profile="": (_select-profile profile)
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v nix >/dev/null 2>&1; then
      echo "==> Installing Determinate Nix (macOS package)"
      # Use the macOS .pkg, not the shell installer: the shell path edits
      # /etc/fstab, which MDM-managed work Macs block, and it needs a TTY to
      # confirm (fails inside a `just` recipe). The pkg handles both.
      pkg="$(mktemp -d)/determinate-nix.pkg"
      curl -fsSL -o "$pkg" https://install.determinate.systems/determinate-pkg/stable/Universal
      sudo installer -pkg "$pkg" -target /
      # Put nix on PATH for THIS shell so rebuild runs without a relogin.
      for p in /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
               /nix/var/nix/profiles/default/etc/profile.d/nix.sh; do
        [[ -r "$p" ]] && . "$p" && break
      done
    fi
    echo "==> Activating nix-darwin configuration"
    ./rebuild.sh

# Activate the nix-darwin config (wraps ./rebuild.sh, sudo). Optional PROFILE
# (personal|work), e.g. `just rebuild work`, sets the marker before rebuilding.
rebuild profile="": (_select-profile profile)
    ./rebuild.sh

# Install Determinate Nix only (open a new shell afterwards before rebuild).
nix-install:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v nix >/dev/null 2>&1; then
      echo "nix already installed: $(nix --version)"; exit 0
    fi
    pkg="$(mktemp -d)/determinate-nix.pkg"
    curl -fsSL -o "$pkg" https://install.determinate.systems/determinate-pkg/stable/Universal
    sudo installer -pkg "$pkg" -target /
    echo "Nix installed. Open a new shell, then run:  just rebuild"

# (internal) If PROFILE is given, validate it and write ~/.config/dotfiles-profile.
_select-profile profile="":
    #!/usr/bin/env bash
    set -euo pipefail
    profile="{{ profile }}"
    [[ -z "$profile" ]] && exit 0
    case "$profile" in
      personal|work) ;;
      *) echo "Profile must be 'personal' or 'work' (got '$profile')" >&2; exit 1 ;;
    esac
    mkdir -p "$HOME/.config"
    printf '%s\n' "$profile" > "$HOME/.config/dotfiles-profile"
    echo "==> Selected profile: $profile"

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

# Bring a fresh machine fully online. Run the interactive prereqs first:
#   just setup            # install Nix (if needed) + activate config (needs sudo)
#   op signin             # 1Password
# then `just bootstrap` does the rest: secrets + FirstMate stack + every skill.
bootstrap: refresh-secrets setup-firstmate update-skills
    @echo "Bootstrap done. If GitHub isn't authed yet: gh auth login"

# Focused regression checks for account selection, setup hooks, and shell safety.
check-regressions:
    ./tests/usernames.sh
    ./tests/regressions.sh

# Run setup hooks only when the AXI tool advertises them, and preserve failures.
_setup-axi-hooks tool:
    #!/usr/bin/env bash
    set -euo pipefail
    tool='{{ tool }}'
    if help=$("$tool" setup --help 2>&1); then
      probe_status=0
    else
      probe_status=$?
    fi
    normalized_help=${help//$'\r'/}
    if [[ "$normalized_help" != *$'\n'* ]] \
      && { grep -Eiq "^[[:space:]]*((error|fatal):[[:space:]]*)?(unknown|unrecognized|invalid|unsupported|no such)[[:space:]]+(sub)?command[[:space:]]*(:[[:space:]]*|[[:space:]]+)['\"]?setup([[:space:]]+hooks)?['\"]?\.?[[:space:]]*$" <<<"$normalized_help" \
        || grep -Eiq "^[[:space:]]*((error|fatal):[[:space:]]*)?['\"]?setup([[:space:]]+hooks)?['\"]?[[:space:]]+(is[[:space:]]+)?(an?[[:space:]]+)?(unknown|unrecognized|invalid|unsupported|no such)[[:space:]]+(sub)?command\.?[[:space:]]*$" <<<"$normalized_help"; }; then
      echo "    - $tool (no setup hooks)"
      exit 0
    fi
    if [[ $probe_status -ne 0 ]]; then
      [[ -z "$help" ]] || printf '%s\n' "$help" >&2
      echo "ERROR: $tool setup hook capability probe failed (exit $probe_status)" >&2
      exit "$probe_status"
    fi
    if grep -Eq '^usage: quota-axi \[auth\] \[flags\]$' <<<"$help" \
      && grep -Eq '^commands\[[0-9]+\]:$' <<<"$help" \
      && grep -Eq '^[[:space:]]+\(none\)=quota, auth$' <<<"$help" \
      && ! grep -Eq '(^|[[:space:]])setup[[:space:]]+hooks([[:space:]]|$)' <<<"$help"; then
      echo "    - $tool (no setup hooks)"
      exit 0
    fi
    if ! grep -Eq '(^|[[:space:]])setup[[:space:]]+hooks([[:space:]]|$)' <<<"$help"; then
      [[ -z "$help" ]] || printf '%s\n' "$help" >&2
      echo "ERROR: $tool setup hook capability probe returned unrecognized output" >&2
      exit 1
    fi
    if output=$("$tool" setup hooks 2>&1); then
      echo "    ✓ $tool"
    else
      status=$?
      [[ -z "$output" ]] || printf '%s\n' "$output" >&2
      echo "ERROR: $tool setup hooks failed (exit $status)" >&2
      exit "$status"
    fi

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

    echo "==> Headroom (agent wrapper; the `claude`/`codex` shell aliases run through it)"
    # pipx venvs (from nix) - install both packages: headroom-ai provides the
    # `headroom` binary, headroom provides `max`. --force keeps re-runs idempotent.
    pipx install --force 'headroom-ai[all]'
    pipx install --force 'headroom[all]'

    echo "==> Pi + Herdr"
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
    curl -fsSL https://herdr.dev/install.sh | sh
    herdr integration install pi

    echo "==> Treehouse + No Mistakes + AXI tools"
    curl -fsSL https://kunchenguid.github.io/treehouse/install.sh | sh
    curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh
    npm install -g {{ axi-tools }}
    # each AXI tool installs its agent hooks via `setup hooks`; report per tool
    # (a few legitimately have no such subcommand)
    echo "==> AXI setup hooks"
    for t in {{ axi-tools }}; do
      just _setup-axi-hooks "$t"
    done

    # AXI tools installed from GitHub (npm spec != binary name)
    echo "==> GitHub AXI tools"
    for spec in {{ axi-tools-git }}; do
      npm install -g "$spec"
      bin="$(basename "$spec")"
      just _setup-axi-hooks "$bin"
    done

    # work-only AXI tools (same ~/.config/dotfiles-profile marker rebuild.sh reads)
    profile=personal
    if [[ -f ~/.config/dotfiles-profile ]]; then profile="$(<~/.config/dotfiles-profile)"; fi
    if [[ "$profile" == work ]]; then
      echo "==> work-only AXI tools (slack/aws/gws/notion)"
      npm install -g {{ axi-tools-work }}
      for t in {{ axi-tools-work }}; do
        just _setup-axi-hooks "$t"
      done
    fi

    echo "==> extra global npm tools"
    npm install -g gnhf

    ws="$HOME/Code/agent-workspace"
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
    ws="$HOME/Code/agent-workspace"
    if [[ -d "$ws/.git" ]]; then git -C "$ws" pull --ff-only; fi
    pi update --self
    herdr update
    treehouse update
    no-mistakes update
    npm update -g {{ axi-tools }} gnhf
    for t in {{ axi-tools }}; do just _setup-axi-hooks "$t"; done   # refresh hooks
    if [[ -f ~/.config/dotfiles-profile && "$(<~/.config/dotfiles-profile)" == work ]]; then
      npm update -g {{ axi-tools-work }}
      for t in {{ axi-tools-work }}; do just _setup-axi-hooks "$t"; done
    fi
    for spec in {{ axi-tools-git }}; do npm install -g "$spec"; just _setup-axi-hooks "$(basename "$spec")"; done
    herdr integration install pi   # refresh Pi integration after a herdr update
    echo "FirstMate stack updated."
