# The local-signoff signer (packages/signoff.nix) and its `signoff watch`
# launchd agent. See README.md "Local signoff" for the Keychain step that must
# come before enabling the watcher.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.signoff;
  home = config.users.users.${config.system.primaryUser}.home;
  stateDir = "${home}/.local/state/signoff";
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
    environment.systemPackages = [ pkgs.signoff ];

    # `watch` makes one pass and exits, so launchd schedules passes instead of
    # keeping one process alive, and never overlaps two passes. launchd opens
    # StandardOutPath before the job runs and does not create its directory,
    # so the script creates it and redirects its own output.
    launchd.user.agents.signoff-watch = lib.mkIf cfg.watch.enable {
      # gh supplies the read-only token (`gh auth token`). The checks themselves
      # see only the trusted PATH compiled into the signer.
      environment.PATH = "${pkgs.gh}/bin:/usr/bin:/bin";
      script = ''
        mkdir -p ${lib.escapeShellArg stateDir}
        exec >>${lib.escapeShellArg "${stateDir}/watch.log"} 2>&1
        exec ${lib.getExe pkgs.signoff} watch \
          --app-id ${toString cfg.watch.appId} \
          --installation-id ${toString cfg.watch.installationId} \
          --key-fingerprint ${lib.escapeShellArg cfg.watch.keyFingerprint}
      '';
      serviceConfig = {
        RunAtLoad = true;
        StartInterval = 120;
      };
    };
  };
}
