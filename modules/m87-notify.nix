{ config, lib, pkgs, ... }:

let
  notifier = pkgs.writeShellScript "m87-notify" ''
    exec ${pkgs.python311}/bin/python3 ${../scripts/m87-notify.py} \
      --m87 ${pkgs.m87}/bin/m87 --yq ${pkgs.yq}/bin/yq
  '';
in
{
  launchd.agents.m87-notify = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ "${notifier}" ];
      StartInterval = 300;
      ProcessType = "Background";
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
        PATH = "${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.python311 ]}:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/m87-notify.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/m87-notify.error.log";
    };
  };
}
