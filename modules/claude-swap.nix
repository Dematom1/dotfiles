{ config, lib, pkgs, ... }:

{
  options.services.claude-swap.autoEnable = lib.mkEnableOption
    "Claude account auto-balancing (enable only after adding accounts with cswap add)";

  config = {
    home.packages = [ pkgs.claude-swap ];
    home.sessionVariables.QUOTA_AXI_CLAUDE_SWAP = "1";

    home.activation.claudeSwapLogs = lib.mkIf
      (pkgs.stdenv.isDarwin && config.services.claude-swap.autoEnable)
      (lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ] ''
        run mkdir -p ${lib.escapeShellArg "${config.home.homeDirectory}/Library/Logs"}
      '');

    launchd.agents.claude-swap = lib.mkIf pkgs.stdenv.isDarwin {
      enable = config.services.claude-swap.autoEnable;
      config = {
        ProgramArguments = [ "${pkgs.claude-swap}/bin/cswap" "auto" "--interval" "60" "--threshold" "90" ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/claude-swap/launchd.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/claude-swap/launchd.log";
        ProcessType = "Background";
        Nice = 19;
        EnvironmentVariables = {
          PATH = "${config.home.homeDirectory}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          PYTHONUNBUFFERED = "1";
        };
      };
    };
  };
}
