{ config, pkgs, lib, profile, ... }:

let
  dotfiles = "${config.home.homeDirectory}/Code/dotfiles";
  securePathOrder = builtins.readFile ./zsh/path-order.zsh;
  homebrewPath = lib.optionals pkgs.stdenv.isDarwin [ "/opt/homebrew/bin" ];
  chromeDevtoolsMcp = pkgs.writeTextFile {
    name = "chrome-devtools-mcp";
    destination = "/bin/chrome-devtools-mcp";
    executable = true;
    text = builtins.readFile ./scripts/chrome-devtools-mcp.js;
  };
  m87GithubRepos = [
    "dematom-labs/agent-sandbox-runtime"
    "dematom-labs/alteran"
    "dematom-labs/conference-directory"
    "dematom-labs/infrastructure"
    "dematom-labs/seo-scout"
    "dematom-labs/truediyer"
  ];
  # The kept agent tooling; the agentTooling activation below reconciles every
  # tool to it. See README.md "Declarative agent tooling".
  agentTooling = lib.importJSON ./agent-tooling.json;
  # Source of the Pi-root skills kept from the retired pstack-claude package.
  pstackClaude = pkgs.fetchFromGitHub {
    owner = "michael-denyer";
    repo = "pstack-claude";
    rev = "356c6e0f978df729eb16f227d795f34d221c5aad";
    hash = "sha256-PxD5vgXMTtwgxGP3wFyiSO8TcXh0xTJaym2+VpVf4LE=";
  };
  piSignedExecutable = "/Applications/Pi Launcher.app/Contents/MacOS/pi-launcher";
  avProjectPolicy = pkgs.writeShellScriptBin "av" ''
    unset AV_VENDOR_CLI
    exec ${pkgs.bash}/bin/bash ${./scripts/av-firstmate-policy.sh} "$@"
  '';
  piSignedEntrypoint = pkgs.writeShellScript "pi-signed" ''
    set -eu
    if [ "''${1-}" = update ] && [ "''${2-}" = --self ]; then
      echo "pi-signed: 'pi update --self' is disabled for the signed route" >&2
      exit 64
    fi
    export FM_PI_HARNESS=pi-signed
    exec /usr/local/bin/av inject +OPENCODE_API_KEY -- \
      ${lib.escapeShellArg piSignedExecutable} "$@"
  '';
  tailscaleAppCli = pkgs.writeShellScript "tailscale" ''
    exec /Applications/Tailscale.app/Contents/MacOS/Tailscale "$@"
  '';
in
{
  # home.username / home.homeDirectory are derived from the profile's
  # users.users entry in configuration.nix.
  home.stateVersion = "26.05";

  # nix-darwin activation copies the app-bundled signed av binary here after
  # Homebrew updates Automic Vault. Managed `av` availability is documented in
  # README.md under "Firstmate project availability".
  home.sessionPath = homebrewPath ++ lib.optionals pkgs.stdenv.isDarwin [
    "${config.home.homeDirectory}/.local/bin"
    "/usr/local/bin"
  ];

  home.packages = with pkgs; [
    # core cli - portable across macOS and the Linux sandbox
    just doppler tmux jq yq bat fd fzf eza zoxide atuin direnv delta glab
    # git
    git git-crypt lazygit lazydocker
    # kubernetes / infra
    argocd kubectl kubernetes-helm kustomize k9s kubectx kubernetes-axi terraform
    # agent review queue (npm identity/integrity are pinned in packages/m87-npm)
    m87
    backpass acpx
    # dev / build
    neovim gh prek cmake lld luarocks protobuf
    nodejs_24 bun python311 go uv memray
    # upstream pipx 1.8.0 test suite is broken in this nixpkgs pin; skip its checks
    (pipx.overridePythonAttrs (_: { doCheck = false; }))
    # net
    websocat curl
  ]
  ++ lib.optionals (!pkgs.stdenv.isDarwin) [
    tailscale
  ]
  # macOS-only: GUI/desktop tooling that either won't build on Linux (aerospace)
  # or is pointless on a headless server (wezterm, the browser MCP, desktop fonts).
  ++ lib.optionals pkgs.stdenv.isDarwin [
    # Nix owns the gcloud binary; gcloud owns ~/.config/gcloud.
    google-cloud-sdk
    # window manager (was a homebrew cask from nikitabobko/tap - native in nixpkgs)
    aerospace
    wezterm
    chromeDevtoolsMcp
    avProjectPolicy
    nerd-fonts.hack
  ]
  # personal Mac only (the Homebrew equivalent lives in hosts/personal.nix)
  ++ lib.optionals (profile == "personal") [
    # personal-only nix packages
    gnupg argo-workflows velero hcloud
  ]
  # work Mac only (the Homebrew equivalent lives in hosts/work.nix)
  ++ lib.optionals (profile == "work") [
    # work-only nix packages
    awscli2
  ];
  # Desktop fonts only matter where there's a GUI.
  fonts.fontconfig.enable = pkgs.stdenv.isDarwin;
  home.sessionVariables = {
    EDITOR = "nvim";
  }
  # chrome-devtools-axi is a macOS desktop browser launcher; its MCP wiring has
  # no place on the headless sandbox.
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    # chrome-devtools-axi's MCP SDK filters arbitrary inherited variables, so
    # route it through the tracked launcher that passes the explicit opt-out.
    CHROME_DEVTOOLS_AXI_MCP_PATH = "${chromeDevtoolsMcp}/bin/chrome-devtools-mcp";
    CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS = "1";
  };

  # Edit-in-place: the real files stay in the repo, ~ just points at them
  # (mkOutOfStoreSymlink, so edits don't need a rebuild - unlike a store copy).
  # Portable links, applied on every platform. mkOutOfStoreSymlink points at the
  # live checkout at ~/Code/dotfiles (the sandbox clones the repo there too), so
  # edits apply without a rebuild.
  home.file = {
    # ~/.config/* app configs
    ".config/nvim".source       = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/nvim";
    ".config/bat".source        = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/bat";
    ".config/yazi".source       = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/yazi";
    ".config/opencode".source   = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/opencode";
    ".config/atuin".source      = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/atuin";
    ".config/direnv".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/direnv";
    ".config/git".source        = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/git";

    # ~ home-dir dotfiles
    ".tmux.conf".source   = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/.tmux.conf";
    ".p10k.zsh".source    = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/zsh/p10k.zsh";

    # AI tooling - one AGENTS.md shared across Claude + Codex
    ".config/herdr".source         = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/herdr";
    # ~/.claude/settings.json is intentionally NOT linked: AXI setup hooks and
    # Claude's plugin manager mutate it. The agentTooling activation edits only
    # its hooks.
    # Claude gets a composition entrypoint (shared AGENTS.md + Claude-only RTK)
    ".claude/CLAUDE.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/CLAUDE.md";
    ".codex/AGENTS.md".source      = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/AGENTS.md";
    # Generated skills for the maintained agent surfaces. `just update-skills`
    # uses the skills CLI's copy mode because a relative leaf symlink under this
    # linked root can otherwise point back to itself. See .agents/SKILLS.md.
    ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/.agents/skills";
    # pi-fff is a real Pi extension entrypoint, not merely an installed package.
    # It is not a declared Pi package, so the agentTooling activation removes its
    # duplicate npm registry entry.
    ".pi/agent/extensions/pi-fff".source = "${pkgs.pi-fff}/${pkgs.pi-fff.extensionPath}";
    ".pi/agent/models.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/pi/models.json";
  }
  // lib.listToAttrs (map (name: lib.nameValuePair ".pi/agent/skills/${name}" {
    source = "${pstackClaude}/plugins/pstack/skills/${name}";
  }) agentTooling.pi.skills)
  # macOS-only: configs for GUI apps (window manager, terminals, status bar,
  # keyboard remapper) that don't exist on the headless Linux sandbox.
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    ".config/ghostty".source    = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/ghostty";
    ".config/aerospace".source  = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/aerospace";
    ".config/sketchybar".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/sketchybar";
    # only the JSON - let Karabiner keep its assets/ + automatic_backups/ out of the repo
    ".config/karabiner/karabiner.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/karabiner/karabiner.json";
    ".wezterm.lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/.wezterm.lua";
    # One credentialed signed-Pi entrypoint; regular `pi` remains unchanged.
    ".local/bin/pi-signed".source = piSignedEntrypoint;
    ".local/bin/tailscale".source = tailscaleAppCli;
  };

  # Reconcile Claude plugins, marketplaces, MCP servers and hooks, Codex MCP
  # servers and hooks, Pi packages, and every skill root to agent-tooling.json.
  # Network or parse problems only warn, so a rebuild never fails on them.
  home.activation.agentTooling = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    dry_run=()
    if [[ -v DRY_RUN ]]; then dry_run=(--dry-run); fi
    PATH="${lib.makeBinPath [ pkgs.nodejs_24 pkgs.git ]}:$HOME/.local/bin:${lib.concatMapStrings (path: "${path}:") homebrewPath}$PATH" \
      ${lib.getExe pkgs.python311} ${./scripts/agent-tooling-reconcile.py} \
      --manifest ${./agent-tooling.json} "''${dry_run[@]}"
  '';

  # M87 stores plugin configuration with its existing queue in ~/.m87. Use its
  # native non-interactive initializer only for a fresh state, without starting
  # a daemon mid-activation. Then apply the full replacement config so existing
  # owned sources survive alongside authored work and the explicit org allowlist.
  home.activation.m87GithubDiscovery = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    state_dir="''${M87_STATE_DIR:-$HOME/.m87}"
    if [[ ! -f "$state_dir/m87.sqlite" ]]; then
      $DRY_RUN_CMD ${lib.getExe pkgs.m87} init --yes --plugin github \
        --github-repo ${lib.escapeShellArgs m87GithubRepos} \
        --no-install-service
    fi
    if [[ -f "$state_dir/m87.sqlite" ]]; then
      if plugin_list=$($DRY_RUN_CMD ${lib.getExe pkgs.m87} plugin list); then
        :
      else
        status=$?
        [[ -z "$plugin_list" ]] || printf '%s\n' "$plugin_list" >&2
        echo "ERROR: m87 plugin list failed (exit $status)" >&2
        exit "$status"
      fi
      if ${pkgs.gawk}/bin/awk '
        /^installed:/ { in_installed = 1; next }
        /^[^[:space:]]/ { in_installed = 0 }
        in_installed && /^[[:space:]]*-[[:space:]]+id:[[:space:]]+github[[:space:]]*$/ { found = 1 }
        END { exit !found }
      ' <<<"$plugin_list"; then
        :
      else
        status=$?
        if [[ $status -ne 1 ]]; then
          echo "ERROR: m87 plugin list output could not be parsed (exit $status)" >&2
          exit "$status"
        fi
        $DRY_RUN_CMD ${lib.getExe pkgs.m87} plugin add github
      fi
      $DRY_RUN_CMD ${lib.getExe pkgs.m87} plugin configure github --config \
        owned_repos=true \
        authored_external=true \
        'explicit_repos=${lib.concatStringsSep "," m87GithubRepos}'
    fi
  '';

  # ---------------------------------------------------------------------------
  # Zsh - declarative structure; imperative extras live-sourced from the repo.
  # home-manager now owns ~/.zshrc and ~/.zshenv.
  # ---------------------------------------------------------------------------
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost-text suggestions from history
    syntaxHighlighting.enable = true;  # valid commands highlighted green

    # was ~/.zshenv (volta/cargo) - ported so it survives home-manager taking over
    envExtra = ''
      [ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

      # Keep the same managed tools available to interactive and non-interactive
      # shells, then place protected directories ahead of user-writable ones.
      typeset -U path PATH
      path=(
        "$HOME/.opencode/bin"
        "$HOME/.lmstudio/bin"
        "/usr/local/zig"
        ${lib.concatStringsSep "\n        " (map (path: ''"${path}"'') homebrewPath)}
        "$HOME/.bun/bin"
        "$HOME/go/bin"
        "$HOME/.local/bin"
        "/etc/profiles/per-user/$USER/bin"
        $path
      )
      ${securePathOrder}
    '';

    # macOS /etc/zprofile runs after .zshenv and invokes path_helper, which can
    # restore unsafe inherited ordering. Re-apply the ordering in .zprofile so
    # login shells pass the final PATH to child processes.
    profileExtra = ''
      ${securePathOrder}
    '';

    history = {
      size = 10000;
      save = 10000;
      path = "${config.home.homeDirectory}/.zhistory";
      share = true;
      expireDuplicatesFirst = true;
      ignoreDups = true;
    };

    shellAliases = {
      ".."   = "cd ..";
      "..."  = "cd ../..";
      ls     = "eza --icons=always";
      ll     = "eza -la --icons=always";
      tree   = "eza --tree --icons=always";
      cat    = "bat";
      n      = "nvim .";
      k      = "kubectl";
      da     = "direnv allow";
      gs     = "git status";
      gd     = "git diff";
      gl     = "git log --oneline -20";
      jv     = "av inject -- just";
    };

    oh-my-zsh = {
      enable = true;
      theme = "";                       # prompt comes from the powerlevel10k plugin
      plugins = [ "git" "web-search" ];
    };

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh/themes/powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    initContent = lib.mkMerge [
      # runs first - p10k instant prompt must precede any output
      (lib.mkBefore ''
        # p10k instant-prompt verbosity is owned by ~/.p10k.zsh (set to quiet there)
        ENABLE_CORRECTION="false"
        COMPLETION_WAITING_DOTS="true"
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')
      # runs last - live-editable extras + machine-local escape hatches
      (lib.mkAfter ''
        source "$HOME/Code/dotfiles/zsh/init.zsh"
        [[ -f ~/.p10k.zsh ]]     && source ~/.p10k.zsh
        [[ -f ~/.secrets ]]      && source ~/.secrets
        [[ -f ~/.zshrc.local ]]  && source ~/.zshrc.local
        ${securePathOrder}
      '')
    ];
  };
}
