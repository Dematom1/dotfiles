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
      # The cask owns the app; postActivation copies its signed binary to
      # /usr/local/bin/av after Homebrew updates the cask.
      "automic-vault/isotopes/automic-vault"
      # fonts
      "font-hack-nerd-font"
      "font-meslo-lg-nerd-font"
      "font-sf-pro"
      "font-symbols-only-nerd-font"
      "sf-symbols"
    ];
  };

  # Homebrew owns the app bundle and runs before postActivation. Keep the
  # PATH-visible CLI byte-for-byte aligned with the signed bundle binary.
  system.activationScripts.postActivation.text = ''
      app="/Applications/Automic Vault.app"
      bundled="$app/Contents/MacOS/av"
      target="/usr/local/bin/av"

      if [ ! -x "$bundled" ]; then
        echo "error: Automic Vault bundled av is missing: $bundled" >&2
        exit 1
      fi

      bundled_version=$("$bundled" --version 2>/dev/null) || {
        echo "error: unable to read the Automic Vault bundled av version" >&2
        exit 1
      }
      if [ -z "$bundled_version" ]; then
        echo "error: Automic Vault bundled av returned an empty version" >&2
        exit 1
      fi

      if [ -x "$target" ]; then
        target_version=$("$target" --version 2>/dev/null) || target_version="unavailable"
        if [ "$target_version" != "$bundled_version" ] || ! /usr/bin/cmp -s "$bundled" "$target"; then
          echo "warning: Automic Vault av mismatch ($target_version vs $bundled_version); replacing $target" >&2
        fi
      else
        echo "Installing Automic Vault av $bundled_version at $target" >&2
      fi

      if [ ! -x "$target" ] || ! /usr/bin/cmp -s "$bundled" "$target"; then
        /bin/mkdir -p "$(/usr/bin/dirname "$target")" || exit 1
        /usr/bin/install -o root -g wheel -m 755 "$bundled" "$target" || exit 1
      fi

      if ! /usr/bin/cmp -s "$bundled" "$target"; then
        echo "error: $target is not identical to the bundled Automic Vault av" >&2
        exit 1
      fi
      target_version=$("$target" --version 2>/dev/null) || {
        echo "error: unable to read the PATH-visible Automic Vault av version" >&2
        exit 1
      }
      if [ "$target_version" != "$bundled_version" ]; then
        echo "error: Automic Vault av version mismatch after synchronization ($target_version vs $bundled_version)" >&2
        exit 1
      fi
    '';
}
