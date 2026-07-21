{ config, pkgs, lib, profile, ... }:

let
  dotfiles = "${config.home.homeDirectory}/Code/dotfiles";
in
{
  # home.username / home.homeDirectory are derived from
  # users.users.laszlohoranszky in configuration.nix.
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    # core cli
    just doppler tmux jq bat fd fzf eza zoxide atuin direnv delta
    # git
    git git-crypt lazygit lazydocker
    # kubernetes / infra
    argocd kubernetes-helm k9s kubectx tailscale
    # dev / build
    neovim gh prek cmake lld luarocks protobuf
    nodejs_24 python311 memray zoxide wezterm
    # upstream pipx 1.8.0 test suite is broken in this nixpkgs pin; skip its checks
    (pipx.overridePythonAttrs (_: { doCheck = false; }))
    # net
    websocat curl
    # window manager (was a homebrew cask from nikitabobko/tap - native in nixpkgs)
    aerospace

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
  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";

  # Edit-in-place: the real files stay in the repo, ~ just points at them
  # (mkOutOfStoreSymlink, so edits don't need a rebuild - unlike a store copy).
  home.file = {
    # ~/.config/* app configs
    ".config/nvim".source       = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/nvim";
    ".config/ghostty".source    = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/ghostty";
    ".config/aerospace".source  = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/aerospace";
    ".config/bat".source        = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/bat";
    ".config/sketchybar".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/sketchybar";
    ".config/yazi".source       = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/yazi";
    ".config/opencode".source   = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/opencode";
    ".config/atuin".source      = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/atuin";
    ".config/direnv".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/direnv";
    ".config/git".source        = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/git";
    # only the JSON — let Karabiner keep its assets/ + automatic_backups/ out of the repo
    ".config/karabiner/karabiner.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/karabiner/karabiner.json";

    # ~ home-dir dotfiles
    ".wezterm.lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/.wezterm.lua";
    ".tmux.conf".source   = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/.tmux.conf";
    ".p10k.zsh".source    = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/zsh/p10k.zsh";

    # AI tooling - one AGENTS.md shared across Claude + Codex
    ".config/herdr".source         = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/herdr";
    # ~/.claude/settings.json is intentionally NOT managed here: the AXI tools
    # (`gh-axi setup hooks` etc.) mutate it, so it's tool-owned like the skills.
    # Claude gets a composition entrypoint (shared AGENTS.md + Claude-only RTK)
    ".claude/CLAUDE.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/CLAUDE.md";
    ".codex/AGENTS.md".source      = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/AGENTS.md";
    # agent-agnostic skill set (SKILL.md dirs) - the one source of truth;
    # opencode gets the same skills via per-skill symlinks in opencode/skills
    ".claude/skills".source        = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/.agents/skills";
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
