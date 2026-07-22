{
  description = "dotfiles";

  inputs = {
    # Use `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` to use Nixpkgs 26.05.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Use `github:nix-darwin/nix-darwin/nix-darwin-26.05` to use Nixpkgs 26.05.
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs }:
  let
    user = "laszlohoranszky";

    # A machine = the shared base (./configuration.nix) + a per-machine file
    # (./hosts/<name>.nix). Both are committed, so either Mac rebuilds straight
    # from git - fully reproducible. nix MERGES the two modules, so a host's
    # homebrew brews/casks are appended to the shared ones, not replacing them.
    mkHost = { profile, hostModule }: nix-darwin.lib.darwinSystem {
      modules = [
        ./configuration.nix
        hostModule
        nix-homebrew.darwinModules.nix-homebrew
        home-manager.darwinModules.home-manager
        {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # First switch renames any existing file/symlink in the way to *.bak
            # instead of erroring - lets nix take over the manual symlinks.
            home-manager.backupFileExtension = "bak";
            # tell home.nix which machine this is, so home.packages can differ
            home-manager.extraSpecialArgs = { inherit profile; };
            home-manager.users.${user} = import ./home.nix;
        }
      ];
    };
  in {
    darwinConfigurations = {
      personal = mkHost { profile = "personal"; hostModule = ./hosts/personal.nix; };
      work     = mkHost { profile = "work";     hostModule = ./hosts/work.nix; };
    };
  };
}
