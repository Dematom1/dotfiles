# The local-signoff signer (packages/signoff.nix) and its `signoff watch`
# launchd agent. See README.md "Local signoff" for the Keychain step that must
# come before enabling the watcher.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.signoff;
  home = config.users.users.${config.system.primaryUser}.home;
  signoff = lib.getExe pkgs.signoff;
  watchArgs = [
    "watch"
    "--app-id" (toString cfg.watch.appId)
    "--installation-id" (toString cfg.watch.installationId)
    "--key-fingerprint" cfg.watch.keyFingerprint
  ];
in
{
  options.services.signoff = {
    enable = lib.mkEnableOption "the signoff binary";

    watch = {
      enable = lib.mkEnableOption ''
        the `signoff watch` launchd agent. Turn it on only after the installed
        binary is on the App key's Keychain access list, or every pass raises a
        Keychain prompt
      '';
      appId = lib.mkOption {
        type = lib.types.ints.positive;
        default = 5460531;
        description = "GitHub App id of dematom-local-signoff.";
      };
      installationId = lib.mkOption {
        type = lib.types.ints.positive;
        default = 174959222;
        description = "The App's dematom-labs installation id.";
      };
      keyFingerprint = lib.mkOption {
        type = lib.types.str;
        default = "SHA256:tlF5N8zgxWi5AR2FZdYPcRdbm8C1Dk4LkwsMp77A4Uk=";
        description = "GitHub fingerprint of the App private key in the login Keychain.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # The signer's trusted PATH is /run/current-system/sw/bin, the per-user
    # profile, then /usr/bin:/bin. home.packages already supplies git, just,
    # bun, node, uv, python3, and go; these are the versioned tools (plus bash
    # for `#!/usr/bin/env bash` recipes) it does not.
    environment.systemPackages = [ pkgs.signoff pkgs.ast-grep pkgs.ruby pkgs.bash ];

    # `watch` makes one pass and exits, so launchd schedules passes instead of
    # keeping one process alive, and never overlaps two passes. launchd opens
    # StandardOutPath before the job runs and does not create its directory,
    # so the script creates it and redirects its own output.
    #
    # A Keychain error (a build not on the key's access list, or no matching
    # key) would repeat on every pass, so it pauses passes until the marker is
    # removed or the binary or watcher settings change.
    launchd.user.agents.signoff-watch = lib.mkIf cfg.watch.enable {
      # gh supplies the read-only token (`gh auth token`). The checks themselves
      # see only the signer's trusted PATH.
      environment = {
        PATH = "${pkgs.gh}/bin:/usr/bin:/bin";
        HOME = home;
      };
      script = ''
        state="$HOME/.local/state/signoff"
        marker="$state/keychain-denied"
        pass=${lib.escapeShellArg "${signoff} ${toString watchArgs}"}
        mkdir -p "$state"
        exec >>"$state/watch.log" 2>&1
        if [ -e "$marker" ]; then
          [ "$(cat "$marker")" = "$pass" ] && exit 0
          rm -f "$marker"
        fi
        ${signoff} ${lib.escapeShellArgs watchArgs} >"$state/pass.log" 2>&1
        status=$?
        cat "$state/pass.log"
        error=$(grep -m 1 'keychain .*/login\.keychain-db:' "$state/pass.log")
        if [ -n "$error" ]; then
          printf '%s\n' "$pass" >"$marker"
          printf 'signoff: passes are paused after a Keychain error until the signer or its watcher settings change or %s is removed: %s\n' "$marker" "$error"
        fi
        exit $status
      '';
      serviceConfig = {
        RunAtLoad = true;
        StartInterval = 120;
      };
    };
  };
}
