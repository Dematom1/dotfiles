# The local-signoff signer (packages/signoff.nix) and its `signoff watch`
# launchd agent. See README.md "Local signoff" for the Keychain step that must
# come before enabling the watcher.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.signoff;
  home = config.users.users.${config.system.primaryUser}.home;
  signoff = lib.getExe pkgs.signoff;
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
    # A Keychain denial (a build not on the key's access list) would prompt on
    # every pass, so it pauses passes until the marker is removed or the binary
    # changes.
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
        mkdir -p "$state"
        exec >>"$state/watch.log" 2>&1
        if [ -e "$marker" ]; then
          [ "$(cat "$marker")" = ${signoff} ] && exit 0
          rm -f "$marker"
        fi
        ${signoff} watch \
          --app-id ${toString cfg.watch.appId} \
          --installation-id ${toString cfg.watch.installationId} \
          --key-fingerprint ${lib.escapeShellArg cfg.watch.keyFingerprint} \
          >"$state/pass.log" 2>&1
        status=$?
        cat "$state/pass.log"
        if grep -q 'keychain .*/login\.keychain-db:' "$state/pass.log"; then
          echo ${signoff} >"$marker"
          echo "signoff: Keychain denied ${signoff}; passes are paused until it is on the App key's access list and $marker is removed"
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
