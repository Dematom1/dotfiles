{ config, pkgs, lib, profile, ... }:

let
  dotfiles = "${config.home.homeDirectory}/Code/dotfiles";
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
  # Follow Pi's existing mutable-package policy; upstream documents this spec.
  piAutoresearchPackage = "npm:pi-autoresearch";
  nixManagedPiPackage = "npm:@ff-labs/pi-fff";
  piSignedExecutable = "/Applications/Pi Launcher.app/Contents/MacOS/pi-launcher";
  kindlePilot = "${dotfiles}/kindle/kindle_pilot.py";
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
in
{
  # home.username / home.homeDirectory are derived from the profile's
  # users.users entry in configuration.nix.
  home.stateVersion = "26.05";

  # Automic Vault installs its signed CLI stub here after the app is opened.
  # Declare the path explicitly so `av` is available in Home Manager shells.
  home.sessionPath = lib.optionals pkgs.stdenv.isDarwin [
    "${config.home.homeDirectory}/.local/bin"
    "/usr/local/bin"
  ];

  home.packages = with pkgs; [
    # core cli - portable across macOS and the Linux sandbox
    just doppler tmux jq yq bat fd fzf eza zoxide atuin direnv delta
    # git
    git git-crypt lazygit lazydocker
    # kubernetes / infra
    argocd kubectl kubernetes-helm kustomize k9s kubectx kubernetes-axi terraform tailscale
    # agent review queue (npm identity/integrity are pinned in packages/m87-npm)
    m87
    # dev / build
    neovim gh prek cmake lld luarocks protobuf
    nodejs_24 python311 uv memray
    # upstream pipx 1.8.0 test suite is broken in this nixpkgs pin; skip its checks
    (pipx.overridePythonAttrs (_: { doCheck = false; }))
    # net
    websocat curl
  ]
  # macOS-only: GUI/desktop tooling that either won't build on Linux (aerospace)
  # or is pointless on a headless server (wezterm, the browser MCP, desktop fonts).
  ++ lib.optionals pkgs.stdenv.isDarwin [
    # window manager (was a homebrew cask from nikitabobko/tap - native in nixpkgs)
    aerospace
    wezterm
    chromeDevtoolsMcp
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
    # ~/.claude/settings.json is intentionally NOT managed here: AXI setup hooks
    # and Claude's plugin manager mutate it, so it's tool-owned like the skills.
    # Claude gets a composition entrypoint (shared AGENTS.md + Claude-only RTK)
    ".claude/CLAUDE.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/CLAUDE.md";
    ".codex/AGENTS.md".source      = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/AGENTS.md";
    # Agent-agnostic generated skills. `just update-skills` uses the skills
    # CLI's copy mode because a relative leaf symlink under this linked root can
    # otherwise point back to itself. See .agents/SKILLS.md.
    ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/.agents/skills";
    # pi-fff is a real Pi extension entrypoint, not merely an installed package.
    # The activation reconciliation below removes its duplicate npm registry entry.
    ".pi/agent/extensions/pi-fff".source = "${pkgs.pi-fff}/${pkgs.pi-fff.extensionPath}";
    ".pi/agent/models.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/pi/models.json";
  }
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
    # The pilot script stays in the checkout and receives credentials only at runtime.
    ".local/bin/kindle-pilot".source = config.lib.file.mkOutOfStoreSymlink kindlePilot;
  };

  # Home Manager owns the scheduled job. It is intentionally dry-run only:
  # omitting --live-send is the safety boundary for unattended execution.
  launchd.agents.kindlePilot = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "/usr/local/bin/av"
        "inject"
        "+MINIFLUX_URL"
        "+MINIFLUX_API_TOKEN"
        "--"
        "${pkgs.python311}/bin/python3"
        "${config.home.homeDirectory}/.local/bin/kindle-pilot"
        "--dry-run"
      ];
      RunAtLoad = false;
      StartInterval = 3600;
      ThrottleInterval = 300;
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/kindle-pilot.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/kindle-pilot.error.log";
    };
  };

  # Reconcile only the declarative Pi package entries. Preserve the mutable
  # settings and every other package; pi-fff is loaded by its Nix-managed
  # extension path above, so removing its npm entry prevents double loading.
  home.activation.piPackageReconciliation = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.pi/agent/settings.json"
    if [[ -v DRY_RUN ]]; then
      echo "Would reconcile Pi packages in $settings"
    elif [[ -f "$settings" ]]; then
      tmp=$(${pkgs.coreutils}/bin/mktemp "$settings.tmp.XXXXXX")
      if ! ${lib.getExe pkgs.jq} \
        --arg autoresearch ${lib.escapeShellArg piAutoresearchPackage} \
        --arg nixManaged ${lib.escapeShellArg nixManagedPiPackage} \
        '.packages = (((.packages // []) | map(select(. != $nixManaged and . != $autoresearch))) + [$autoresearch])' \
        "$settings" > "$tmp" \
        || ! ${pkgs.coreutils}/bin/chmod --reference="$settings" "$tmp"; then
        rm -f "$tmp"
        echo "ERROR: unable to reconcile Pi packages in $settings" >&2
        exit 1
      fi
      mv "$tmp" "$settings"
    else
      mkdir -p "$(dirname "$settings")"
      printf '{"packages":["%s"]}\n' ${lib.escapeShellArg piAutoresearchPackage} > "$settings"
    fi
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

      # Put nix + user bins on PATH for NON-interactive shells too (agents, git
      # hooks, tool subprocesses). init.zsh only runs for interactive shells, so
      # anything launched outside a terminal couldn't find gh/just/prek/etc.
      typeset -U path PATH
      path=("/etc/profiles/per-user/$USER/bin" "$HOME/.local/bin" $path)
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
      claude   = "headroom wrap claude --";       # 200K default - caps per-turn context re-read
      claude1m = "headroom wrap claude --1m --";   # opt-in 1M window for tasks that truly need it
      codex  = "headroom wrap codex --no-proxy --port 8787 --no-context-tool --no-mcp --no-tokensave --no-serena --";
      # regenerate ~/.secrets from 1Password (needs `op signin`)
      refresh-secrets = "op inject -f -i ~/Code/dotfiles/zsh/secrets.tpl -o ~/.secrets && echo '✓ ~/.secrets refreshed'";
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
        ENABLE_CORRECTION="true"
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
      '')
    ];
  };
}
