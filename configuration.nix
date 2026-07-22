{ pkgs, username, ... }:

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;
  system.primaryUser = username;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # Wire zsh into the nix environment: puts /etc/profiles/per-user/$USER/bin
  # (home.packages) and /run/current-system/sw/bin on PATH for every shell.
  programs.zsh.enable = true;

  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = true;  # auto-hide the menu bar
      AppleShowAllExtensions = true;
    };
    dock.autohide = true;
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click
  };
  homebrew = {
    # nix-homebrew is imported but intentionally not enabled, so this drives an
    # EXISTING Homebrew install (a prerequisite on a fresh Mac) via `brew bundle`.
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" ];
    brews = [
      # not in nixpkgs
      "herdr"
      "rtk"
    ];
    taps = [
      "kunchenguid/tap"
    ];
    casks = [
      "wezterm"
      "claude-code"
      "ghostty"
      "1password-cli"
      "gcloud-cli"
      "ngrok"
      "postico"
      "opensuperwhisper"
      "agentsview"
      "kunchenguid/tap/baby-menu"
      # fonts
      "font-hack-nerd-font"
      "font-meslo-lg-nerd-font"
      "font-sf-pro"
      "font-symbols-only-nerd-font"
      "sf-symbols"
    ];
  };
}
