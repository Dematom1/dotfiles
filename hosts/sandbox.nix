# Headless AI sandbox server (NixOS). Provider-agnostic: no cloud-vendor
# assumptions, so this applies to any provisioned x86_64-linux box (bare metal,
# a droplet, an EC2/GCE instance, a local VM):
#
#   nixos-rebuild switch --flake .#sandbox
#
# The operator supplies the machine-specific disk/boot layout by generating
# hardware-configuration.nix on the box (`nixos-generate-config`) and importing
# it, or by overriding the lib.mkDefault placeholders below. Those placeholders
# exist only so `nix build .#nixosConfigurations.sandbox.config.system.build.toplevel`
# evaluates and builds without a real machine attached.
{ config, pkgs, lib, modulesPath, username, ... }:

{
  imports = [
    # Broad virtualized-provider compatibility (virtio disk/net, cloud drivers).
    # Harmless on bare metal.
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # --- Placeholder boot + filesystem -------------------------------------
  # Overridden by the host's real hardware-configuration.nix. Kept as
  # lib.mkDefault so importing that file wins without a merge conflict.
  boot.loader.grub.enable = lib.mkDefault true;
  boot.loader.grub.device = lib.mkDefault "/dev/sda";
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "26.05";
  networking.hostName = "sandbox";

  # Flakes on a fresh box, so `nixos-rebuild --flake` works out of the box.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  time.timeZone = lib.mkDefault "UTC";

  # --- SSH: key-based auth only ------------------------------------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # --- captain account ----------------------------------------------------
  # Home Manager (wired in flake.nix) owns captain's shell/CLI environment.
  users.users.${username} = {
    isNormalUser = true;
    home = "/home/${username}";
    extraGroups = [ "wheel" ];   # sudo
    shell = pkgs.zsh;
    autoSubUidGidRange = true;
    # Keep captain's systemd user manager (and the rootless podman socket below)
    # running without an interactive login, so `docker` works on the first SSH.
    linger = true;
    openssh.authorizedKeys.keys = [
      # Add captain's SSH public key(s) here before applying, e.g.
      # "ssh-ed25519 AAAA... captain@laptop"
      # Alternatively manage them out-of-band (cloud metadata, secrets tooling).
    ];
  };
  # Login is key-only, so a password prompt on sudo would just block automation.
  security.sudo.wheelNeedsPassword = false;

  # Wire zsh into the system so Home Manager's zsh config has a login shell.
  programs.zsh.enable = true;

  # --- Container runtime: podman -----------------------------------------
  # Podman over Docker for a sandbox that runs AI-generated code: rootless and
  # daemonless (no privileged system-wide socket to escalate through), while
  # dockerCompat still exposes the `docker` CLI for tooling that expects it.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # Rootless Docker-compatible API socket (human decision key=podman-docker-socket,
  # option B). dockerCompat gives the `docker` CLI a binary; this gives it a daemon
  # to talk to. It is captain's *rootless* per-user socket under $XDG_RUNTIME_DIR -
  # the rootful virtualisation.podman.dockerSocket is deliberately left OFF so no
  # privileged, system-wide Docker daemon runs on a box that executes AI-authored
  # code. captain's DOCKER_HOST (home.nix) points here, so `docker` and
  # `docker-compose` reach rootless podman over SSH; linger (above) keeps the
  # socket alive between logins.
  systemd.user.sockets.podman = {
    description = "Podman API Socket";
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "%t/podman/podman.sock" ];
    socketConfig.SocketMode = "0660";
  };
  systemd.user.services.podman = {
    description = "Podman API Service";
    requires = [ "podman.socket" ];
    after = [ "podman.socket" ];
    serviceConfig = {
      Type = "exec";
      KillMode = "process";
      ExecStart = "${pkgs.podman}/bin/podman system service";
    };
  };

  # --- Baseline AI/dev tooling (system-wide) -----------------------------
  # Language-specific toolchains and the portable CLI stack come from Home
  # Manager (see home.nix); this is the minimal system-level build toolchain.
  environment.systemPackages = with pkgs; [
    git gh curl wget
    gcc gnumake pkg-config
    docker-compose
  ];

  # Only SSH is reachable from outside.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };
}
