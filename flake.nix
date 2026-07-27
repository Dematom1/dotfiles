{
  description = "dotfiles";

  inputs = {
    # Use `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` to use Nixpkgs 26.05.
    # This release branch also carries the full Linux/NixOS package set and
    # modules, so the same pin drives both the Darwin hosts and the Linux
    # sandbox below - no second nixpkgs input to keep in sync.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Use `github:nix-darwin/nix-darwin/nix-darwin-26.05` to use Nixpkgs 26.05.
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Agent-facing Kubernetes CLI. The source commit is pinned here and in
    # flake.lock; packages/kubernetes-axi.nix supplies the reproducible build.
    kubernetes-axi = {
      url = "github:thatdudealso/kubernetes-axi/c05c686e02cb0074ccf1ba5284d2941c05e9a54e";
      flake = false;
    };
  };

  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs, kubernetes-axi }:
  let
    supportedSystems = [
      "aarch64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

    # One overlay keeps the package identity identical in standalone package
    # builds, nix-darwin, NixOS, and standalone Home Manager configurations.
    kubernetesAxiOverlay = final: _: {
      kubernetes-axi = final.callPackage ./packages/kubernetes-axi.nix {
        src = kubernetes-axi;
      };
    };

    pkgsFor = system: import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [ kubernetesAxiOverlay ];
    };

    # Shared Home Manager wiring, identical for every platform. `profile` tells
    # home.nix which machine this is; home.nix gates macOS-only modules behind
    # pkgs.stdenv.isDarwin, so the same file is portable to Linux unchanged.
    # Dotted keys in one attrset literal merge, so extraSpecialArgs and users
    # co-exist (a top-level `//` would instead clobber the `home-manager` key).
    hmModule = { profile, username }: {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      # First switch renames any existing file/symlink in the way to *.bak
      # instead of erroring - lets nix take over the manual symlinks.
      home-manager.backupFileExtension = "bak";
      home-manager.extraSpecialArgs = { inherit profile; };
      home-manager.users.${username} = import ./home.nix;
    };

    # A Mac = the shared base (./configuration.nix) + a per-machine file
    # (./hosts/<name>.nix). Both are committed, so either Mac rebuilds straight
    # from git - fully reproducible. nix MERGES the two modules, so a host's
    # homebrew brews/casks are appended to the shared ones, not replacing them.
    mkDarwinHost = { profile, username, hostModule }: nix-darwin.lib.darwinSystem {
      specialArgs = { inherit username; };
      modules = [
        { nixpkgs.overlays = [ kubernetesAxiOverlay ]; }
        ./configuration.nix
        hostModule
        nix-homebrew.darwinModules.nix-homebrew
        home-manager.darwinModules.home-manager
        (hmModule { inherit profile username; })
      ];
    };

    # A Linux host = a per-machine NixOS module (./hosts/<name>.nix) with Home
    # Manager attached for captain's portable shell/CLI environment. Provider
    # agnostic: the host module carries no cloud-vendor assumptions.
    mkNixosHost = { profile, username, hostModule }: nixpkgs.lib.nixosSystem {
      specialArgs = { inherit username; };
      modules = [
        { nixpkgs.overlays = [ kubernetesAxiOverlay ]; }
        hostModule
        home-manager.nixosModules.home-manager
        (hmModule { inherit profile username; })
      ];
    };

    # Standalone Home Manager (no NixOS) so captain's environment also applies
    # on any non-NixOS Linux box (Ubuntu/Debian/etc.) that just has Nix + Home
    # Manager. `nix build .#homeConfigurations."captain@<system>".activationPackage`
    # is the Linux validation target when no NixOS builder is available.
    # `username`/`homeDirectory` default to captain but are overridable: some
    # provisioned boxes (e.g. a k3s node reachable only as root over Tailscale)
    # have no captain account, so the same portable environment is applied to
    # root's own home instead of creating a system user.
    mkLinuxHome = { system, username ? "captain", homeDirectory ? "/home/${username}" }:
      home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsFor system;
        extraSpecialArgs = { profile = "sandbox"; };
        modules = [
          ./home.nix
          {
            # home.nix already pins home.stateVersion; only the identity that a
            # NixOS/Darwin users.users entry would otherwise supply is set here.
            home.username = username;
            home.homeDirectory = homeDirectory;
          }
        ];
      };
  in {
    overlays.default = kubernetesAxiOverlay;

    # Direct package outputs make the pin easy to build and inspect separately
    # from a complete host or Home Manager activation.
    packages = forAllSystems (system:
      let
        package = (pkgsFor system).kubernetes-axi;
      in {
        kubernetes-axi = package;
        default = package;
      });

    # The package build runs upstream's unit suite. This additional bounded
    # smoke test runs doctor without kubectl on PATH, so no cluster is contacted.
    checks = forAllSystems (system:
      let
        pkgs = pkgsFor system;
        package = pkgs.kubernetes-axi;
      in {
        kubernetes-axi-doctor = pkgs.runCommand "kubernetes-axi-doctor-smoke" {
          nativeBuildInputs = [ package pkgs.gnugrep ];
        } ''
          mkdir -p "$out" "$TMPDIR/home"
          env -i HOME="$TMPDIR/home" PATH="${package}/bin" \
            kubernetes-axi doctor > "$out/doctor.toon"
          grep -q '^summary:' "$out/doctor.toon"
          grep -q 'kubectl' "$out/doctor.toon"
        '';
      });

    darwinConfigurations = {
      personal = mkDarwinHost {
        profile = "personal";
        username = "laszlohoranszky";
        hostModule = ./hosts/personal.nix;
      };
      work = mkDarwinHost {
        profile = "work";
        username = "laszlo";
        hostModule = ./hosts/work.nix;
      };
    };

    # Headless AI sandbox server (NixOS). Apply to any provisioned x86_64-linux
    # box with `nixos-rebuild switch --flake .#sandbox`.
    nixosConfigurations.sandbox = mkNixosHost {
      profile = "sandbox";
      username = "captain";
      hostModule = ./hosts/sandbox.nix;
    };

    # Portable Home Manager for non-NixOS Linux, on both common server arches.
    # `root@<arch>` targets boxes that are only SSH-reachable as root (no captain
    # account); they apply the identical environment to /root.
    homeConfigurations = {
      "captain@x86_64-linux" = mkLinuxHome { system = "x86_64-linux"; };
      "captain@aarch64-linux" = mkLinuxHome { system = "aarch64-linux"; };
      "root@x86_64-linux" = mkLinuxHome { system = "x86_64-linux"; username = "root"; homeDirectory = "/root"; };
      "root@aarch64-linux" = mkLinuxHome { system = "aarch64-linux"; username = "root"; homeDirectory = "/root"; };
    };
  };
}
