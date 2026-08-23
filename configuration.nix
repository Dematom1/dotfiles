{ pkgs, username, ... }:

let
  digestHome = "/Users/${username}/Code/dotfiles";
in
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
  launchd.user.agents.ai-tool-update-digest = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.python3}/bin/python3"
        "${digestHome}/scripts/ai-tool-update-digest.py"
        "--inventory"
        "${digestHome}/ai-tool-update-inventory.json"
      ];
      EnvironmentVariables = {
        HOMEBREW_NO_AUTO_UPDATE = "1";
        HOMEBREW_NO_ENV_HINTS = "1";
        PATH = "/opt/homebrew/bin:/usr/local/bin:/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin:/Users/${username}/.nix-profile/bin:/Users/${username}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      StartCalendarInterval = {
        Hour = 9;
        Minute = 0;
      };
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = "/Users/${username}/Library/Logs/ai-tool-update-digest.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/ai-tool-update-digest.log";
    };
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
      "felixkratz/formulae/sketchybar"
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
      "ngrok"
      "postico"
      "opensuperwhisper"
      "agentsview"
      "kunchenguid/tap/baby-menu"
      "kunchenguid/tap/pi-launcher"
      # One cask owns both the Automic Vault app and its signed `av` CLI stub,
      # preventing the separately installed app/CLI version skew.
      "automic-vault/isotopes/automic-vault"
      # fonts
      "font-hack-nerd-font"
      "font-meslo-lg-nerd-font"
      "font-sf-pro"
      "font-symbols-only-nerd-font"
      "sf-symbols"
    ];
  };
}
