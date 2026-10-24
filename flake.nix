{
  description = "dotfiles";

  inputs = {
    # Use `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` to use Nixpkgs 26.05.
    # This release branch also carries the full Linux/NixOS package set and
    # modules, so the same pin drives both the Darwin hosts and the Linux
    # sandbox below.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Use `github:nix-darwin/nix-darwin/nix-darwin-26.05` to use Nixpkgs 26.05.
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Terraform releases aren't backported onto the stable release branch
    # above, so the pinned nixpkgs there lags HashiCorp's latest stable by
    # months. This second input exists solely so terraformOverlay (below) can
    # pin just the terraform package to a newer nixpkgs-unstable revision -
    # currently Terraform 1.15.8. Nothing else is taken from it, and it does
    # not `follow` nixpkgs, so it stays fully independent of the stable pin.
    # Like any flake input, it is a point-in-time pin, not a moving target:
    # picking up a later Terraform release means bumping this input's lock
    # entry (`nix flake lock --update-input nixpkgs-unstable`), and updating
    # the expected version in tests/terraform.sh to match.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Agent-facing Kubernetes and Docker CLIs. Upstream cuts no releases or npm
    # packages, so flake.lock pins the default-branch commit and
    # .github/workflows/flake-update.yml moves it daily;
    # packages/node-source-tool.nix supplies the reproducible build.
    kubernetes-axi = {
      url = "github:thatdudealso/kubernetes-axi";
      flake = false;
    };
    docker-axi = {
      url = "github:thatdudealso/docker-axi";
      flake = false;
    };

    # Pinned to an upstream release tag; upstream's flake owns vendorHash, so a
    # bump is a tag edit plus `nix flake lock`, which
    # .github/workflows/flake-update.yml does daily. It deliberately does not
    # follow nixpkgs: upstream builds and tests only against its own pin.
    treehouse.url = "github:kunchenguid/treehouse/v3.1.5";
  };

  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs, nixpkgs-unstable, kubernetes-axi, docker-axi, treehouse }:
  let
    supportedSystems = [
      "aarch64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

    # Every packages/npm/<name> directory becomes package <name>; Renovate keeps
    # its package.json and package-lock.json current.
    npmTools = builtins.attrNames (nixpkgs.lib.filterAttrs (_: type: type == "directory")
      (builtins.readDir ./packages/npm));

    # One overlay keeps package identities identical in standalone package
    # builds, nix-darwin, NixOS, and standalone Home Manager configurations.
    dotfilesOverlay = final: _:
      nixpkgs.lib.genAttrs npmTools (name: final.callPackage ./packages/npm-tool.nix {
        npmRoot = ./packages/npm + "/${name}";
      })
      // {
        kubernetes-axi = final.callPackage ./packages/node-source-tool.nix { src = kubernetes-axi; };
        docker-axi = final.callPackage ./packages/node-source-tool.nix { src = docker-axi; };
        treehouse = treehouse.packages.${final.stdenv.hostPlatform.system}.default;
        # A Pi extension, not a CLI: home.nix links its entrypoint directory.
        pi-fff = (final.callPackage ./packages/npm-tool.nix { npmRoot = ./packages/npm/pi-fff; }).overrideAttrs (old: {
          npmFlags = [ "--legacy-peer-deps" ];
          passthru = old.passthru or { } // {
            extensionPath = "libexec/pi-fff/node_modules/@ff-labs/pi-fff/src";
          };
        });
      };

    # Swaps in terraform from nixpkgs-unstable, currently pinning it to
    # 1.15.8; see the nixpkgs-unstable input comment above for how to move to
    # a newer release. Terraform stays Nix/Home Manager's sole responsibility
    # - this only changes which nixpkgs tree the one package comes from.
    terraformOverlay = final: _: {
      terraform = (import nixpkgs-unstable {
        system = final.stdenv.hostPlatform.system;
        config.allowUnfree = true;
      }).terraform;
    };

    sharedOverlays = [ dotfilesOverlay terraformOverlay ];

    pkgsFor = system: import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = sharedOverlays;
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
        { nixpkgs.overlays = sharedOverlays; }
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
        { nixpkgs.overlays = sharedOverlays; }
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
    overlays.default = dotfilesOverlay;

    # Direct package outputs make pins easy to build and inspect separately
    # from a complete host or Home Manager activation.
    packages = forAllSystems (system:
      let
        pkgs = pkgsFor system;
      in nixpkgs.lib.genAttrs npmTools (name: pkgs.${name}) // {
        inherit (pkgs) kubernetes-axi docker-axi treehouse;
        default = pkgs.kubernetes-axi;
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

        agent-tools-layout = pkgs.runCommand "agent-tools-layout" {
          nativeBuildInputs = [ pkgs.m87 pkgs.treehouse pkgs.nodejs_24 ];
        } ''
          test "$(m87 --version)" = ${pkgs.m87.version}
          treehouse --version | grep -Fq ${pkgs.treehouse.version}
          ${nixpkgs.lib.concatMapStrings (name: ''
            test -x ${pkgs.${name}}/bin/${name}
          '') (nixpkgs.lib.remove "pi-fff" npmTools ++ [ "kubernetes-axi" "docker-axi" ])}
          test -f ${pkgs.pi-fff}/${pkgs.pi-fff.extensionPath}/index.ts
          mkdir "$out"
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
