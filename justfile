# Dotfiles maintenance tasks - run `just` (or `just --list`).

skills-dir := ".agents/skills"

# AXI agent tools (https://axi.md). Nix installs every one of them (home.nix,
# packages/npm/<name>), so these lists only decide whose session hooks are set
# up.
axi-tools := "gh-axi chrome-devtools-axi tasks-axi npm-axi pypi-axi homebrew-axi jev-axi bun-axi hetzner-axi argocd-axi argo-workflows-axi datadog-axi k8s-axi"

# HEY stays on-demand so session-start hooks cannot inject private email.
# lavish-axi is routed by its skill instead of a per-session status dump.
# quota-axi, pg-axi, docker-axi and linear-axi have no `setup hooks` command.
axi-tools-no-hooks := "hey-axi lavish-axi quota-axi pg-axi docker-axi linear-axi"

# Argo CD connectivity for this Mac is pending a separate maintainer setup.

# work-machine-only AXI tools - Nix installs them on the work profile only, and
# their hooks are set up only when ~/.config/dotfiles-profile says "work" (the
# same marker rebuild.sh reads).
axi-tools-work := "slack-axi aws-axi gws-axi notion-axi"

# Reviewed upstream agent package/plugin identities. Keep these user-scoped and
# tool-owned: Pi and Claude Code both reconcile repeated installs idempotently.
ponytail-pi-source := "git:github.com/DietrichGebert/ponytail"
ponytail-claude-marketplace := "DietrichGebert/ponytail"
ponytail-claude-plugin := "ponytail@ponytail"

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

# Reinstall every skill source declared in agent-tooling.json (`just rebuild`
# installs only missing ones and removes undeclared skills). Then run
# `just check-skills`.
update-skills:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "==> npx skills CLI (sources declared in agent-tooling.json)"
    python3 scripts/agent-tooling-reconcile.py --manifest agent-tooling.json --refresh-skills

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
    echo "All updated (generated skill content is gitignored). Validate:  just check-skills"

# ---------------------------------------------------------------------------
# Machine setup - install Nix, then activate the nix-darwin configuration.
# ---------------------------------------------------------------------------

# Fresh-machine one-shot: install Determinate Nix (if missing), then rebuild.
# Optional PROFILE (personal|work), e.g. `just setup work`, sets the marker first.
setup profile="": (_select-profile profile)
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v nix >/dev/null 2>&1; then
      echo "==> Installing Determinate Nix"
      curl -fsSL https://install.determinate.systems/nix | sh -s -- install
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
    curl -fsSL https://install.determinate.systems/nix | sh -s -- install
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
# FirstMate + Herdr + Pi agent stack. Pi, Herdr, No Mistakes and Claude Code
# are npm globals + native installers that self-update into ~/.local/bin
# (managed on PATH by the Home Manager zsh setup). Nix installs the base deps
# (git/gh/jq/node/curl), Treehouse and every AXI tool: daily auto-merged PRs
# keep their pins current and `just rebuild` activates them.
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

# Focused regression checks for Neovim, account selection, agent setup, and shell safety.
check-regressions:
    python3 ./tests/m87-migration.py
    ./tests/av-project-policy.sh
    ./tests/nvim-fff.sh
    ./tests/usernames.sh
    ./tests/claude-launch.sh
    ./tests/terraform.sh
    ./tests/agent-tools.sh
    ./tests/agent-tooling.py
    ./tests/pi-signed.sh
    python3 ./tests/m87-notify.py
    ./tests/ponytail.sh
    ./tests/just-update.sh
    ./tests/regressions.sh

# Redacted Automic Vault scan through the real login-shell operator path.
av-scan:
    ./scripts/av-scan-summary.sh

# Final app-visible acceptance gate. This fails while any finding remains.
av-check:
    ./scripts/av-scan-summary.sh --require-clean

# Install Ponytail through each agent's native user-scoped package manager.
# Claude Code is shared by both Mac profiles; the Linux sandbox remains Pi-only
# unless Claude is installed there separately.
_setup-ponytail:
    #!/usr/bin/env bash
    set -euo pipefail
    pi install {{ ponytail-pi-source }}
    if ! command -v claude >/dev/null 2>&1; then
      if [[ $(uname -s) == Darwin ]]; then
        echo "missing Claude Code: run 'just setup-firstmate' to install it" >&2
        exit 1
      fi
      echo "    - Claude Code unavailable; installed Ponytail for Pi only"
      exit 0
    fi
    claude plugin marketplace add --scope user {{ ponytail-claude-marketplace }}
    claude plugin install --scope user {{ ponytail-claude-plugin }}

# Reconcile missing installs first, then refresh Claude's mutable marketplace
# checkout and installed plugin through its native update contract.
_update-ponytail: _setup-ponytail
    #!/usr/bin/env bash
    set -euo pipefail
    pi update {{ ponytail-pi-source }}
    command -v claude >/dev/null 2>&1 || exit 0
    claude plugin marketplace update ponytail
    claude plugin update {{ ponytail-claude-plugin }}

# Remove hooks only through documented tool-owned uninstall commands. The marker
# makes the migration a one-time rebuild action.
_cleanup-axi-hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    marker="$HOME/.local/state/dotfiles/axi-hooks-cleaned-v1"
    [[ -e "$marker" ]] && exit 0
    mkdir -p "$(dirname "$marker")"
    for tool in bun-axi; do
      if command -v "$tool" >/dev/null 2>&1; then "$tool" setup hooks --uninstall
      else echo "    - $tool unavailable; skipped"; fi
    done
    for tool in hetzner-axi argocd-axi argo-workflows-axi datadog-axi; do
      if command -v "$tool" >/dev/null 2>&1; then "$tool" setup uninstall
      else echo "    - $tool unavailable; skipped"; fi
    done
    # Other tools have no documented hook uninstall form in their help; leave
    # their hooks untouched rather than risk deleting hooks they do not own.
    echo "    - skipped tools without documented uninstall: gh-axi chrome-devtools-axi tasks-axi npm-axi pypi-axi homebrew-axi jev-axi slack-axi aws-axi gws-axi notion-axi"
    touch "$marker"

# One-time setup of the FirstMate stack. Re-runnable. Run `gh auth login` after.
setup-firstmate:
    #!/usr/bin/env bash
    set -euo pipefail
    set +h   # don't cache command locations - we install tools then use them
    for c in git gh jq node npm curl treehouse; do
      command -v "$c" >/dev/null || { echo "missing base dep: $c (add in nix + ./rebuild.sh)"; exit 1; }
    done

    # keep global npm installs user-owned (nix's node can't write to its store)
    mkdir -p "$HOME/.local/bin"
    npm config set prefix "$HOME/.local"

    echo "==> Pi + Herdr"
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
    curl -fsSL https://herdr.dev/install.sh | sh
    herdr integration install pi
    if [[ $(uname -s) == Darwin ]]; then
      bash scripts/install-claude-native.sh
    fi
    just _setup-ponytail

    echo "==> No Mistakes"
    curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh
    just _retire-superseded-installs
    echo "==> extra global npm tools"
    npm install -g gnhf

    ws="$HOME/agent-workspace"
    echo "==> workspace: $ws"
    if [[ ! -d "$ws/.git" ]]; then
      git clone https://github.com/kunchenguid/firstmate.git "$ws"
    fi
    mkdir -p "$ws/config"
    printf 'herdr\n' > "$ws/config/backend"
    printf 'pi\n'    > "$ws/config/crew-harness"

    echo
    echo "Done. Next:  gh auth login   then   cd $ws && herdr   (run 'pi' in pane 1)"

# Remove the npm-global and curl-installed copies of tools Nix now installs, so
# a stale copy in ~/.local/bin cannot shadow them for callers that skip the
# shell's PATH ordering (e.g. hooks that resolve a bare command).
_retire-superseded-installs:
    #!/usr/bin/env bash
    set -euo pipefail
    root=$(npm root -g)
    for package in {{ axi-tools }} {{ axi-tools-no-hooks }} {{ axi-tools-work }} @nikolauska/linear-axi; do
      if [[ -n "$root" && -d "$root/$package" ]]; then
        echo "    - removing npm-global $package (Nix installs it now)"
        npm uninstall -g "$package"
      fi
    done
    if [[ -f "$HOME/.local/bin/treehouse" && ! -L "$HOME/.local/bin/treehouse" ]]; then
      echo "    - removing ~/.local/bin/treehouse (Nix installs it now)"
      rm -- "$HOME/.local/bin/treehouse"
    fi

# Read-only signed-Pi drift report; the signed app exists only on macOS.
report-pi-signed-drift:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "$(uname -s)" == Darwin ]]; then
      ./scripts/pi-signed-drift.sh
    else
      echo "pi-signed: drift check skipped (signed bundle is macOS-only)."
    fi

# Update the FirstMate stack via each tool's native updater (guide's order).
_update-herdr:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v brew >/dev/null 2>&1 && brew list --formula herdr >/dev/null 2>&1; then
      brew update && brew upgrade herdr
    else
      herdr update
    fi

update-firstmate:
    #!/usr/bin/env bash
    set -euo pipefail
    set +h   # don't cache command locations (updaters may replace binaries)
    ws="$HOME/agent-workspace"
    if [[ -d "$ws/.git" ]]; then git -C "$ws" pull --ff-only; fi
    pi update --self
    just _update-ponytail
    just _update-herdr
    # No Mistakes refuses to restart its shared daemon under active pipeline
    # runs; skip only that refusal (never --force). Other failures stay fatal.
    nm_status=0
    nm_output=$(no-mistakes update </dev/null 2>&1 | tee /dev/stderr) || nm_status=$?
    if (( nm_status != 0 )); then
      if [[ "$nm_output" =~ refusing\ update\ because\ ([0-9]+)\ active\ pipeline\ run ]]; then
        echo "skipped no-mistakes update: ${BASH_REMATCH[1]} active pipeline runs; rerun 'no-mistakes update' once they finish (never --force)" >&2
      else
        exit "$nm_status"
      fi
    fi
    # Treehouse and the AXI tools are Nix-pinned: daily auto-merged PRs move the
    # pins and `just rebuild` activates them, so only their hooks refresh here.
    just _retire-superseded-installs
    npm update -g gnhf
    herdr integration install pi   # refresh Pi integration after a herdr update
    just report-pi-signed-drift
    echo "FirstMate stack updated."
