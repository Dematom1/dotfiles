{ config, pkgs, lib, profile, ... }:

let
  dotfiles = "${config.home.homeDirectory}/Code/dotfiles";
  chromeDevtoolsMcp = pkgs.writeTextFile {
    name = "chrome-devtools-mcp";
    destination = "/bin/chrome-devtools-mcp";
    executable = true;
    text = builtins.readFile ./scripts/chrome-devtools-mcp.js;
  };
in
{
  # home.username / home.homeDirectory are derived from the profile's
  # users.users entry in configuration.nix.
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    # core cli - portable across macOS and the Linux sandbox
    just doppler tmux jq yq bat fd fzf eza zoxide atuin direnv delta
    # git
    git git-crypt lazygit lazydocker
    # kubernetes / infra
    argocd kubernetes-helm k9s kubectx tailscale
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
    argo-workflows velero hcloud
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
  }
  # Linux sandbox: point the `docker` CLI / docker-compose at captain's rootless
  # podman socket (option B, key=podman-docker-socket). $XDG_RUNTIME_DIR expands
  # per session to /run/user/<uid>, matching the systemd user socket that
  # hosts/sandbox.nix installs. Harmless on non-NixOS Linux that lacks podman.
  // lib.optionalAttrs pkgs.stdenv.isLinux {
    DOCKER_HOST = "unix://\${XDG_RUNTIME_DIR}/podman/podman.sock";
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
    # ~/.claude/settings.json is intentionally NOT managed here: the AXI tools
    # (`gh-axi setup hooks` etc.) mutate it, so it's tool-owned like the skills.
    # Claude gets a composition entrypoint (shared AGENTS.md + Claude-only RTK)
    ".claude/CLAUDE.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/CLAUDE.md";
    ".codex/AGENTS.md".source      = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/AGENTS.md";
    # Agent-agnostic skill source; OpenCode wiring is owned by `just update-skills`.
    # See .agents/SKILLS.md for the managed-link contract.
    ".claude/skills".source        = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/.agents/skills";
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
  };

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
      claude = "headroom wrap claude --1m --";
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
