{
  lib,
  buildGoModule,
  git,
  just,
}:

let
  # dematom-labs/workflows is private, so a flake input could not be fetched by
  # GitHub-token CI or by root during `sudo darwin-rebuild`. signoff-src is that
  # repo's signoff/ directory at this commit; scripts/vendor-signoff.sh replaces
  # both together.
  rev = "43172c88e886f98e3b7c4d4c2cd5559031454a7b";
in
buildGoModule {
  pname = "signoff";
  version = "0-unstable-${builtins.substring 0 7 rev}";

  src = ./signoff-src;
  # Standard library only, so there is nothing to vendor.
  vendorHash = null;

  # No -X main.trustedPath: the signer's default trusted PATH is the system and
  # per-user profile directories, so tool updates never change this binary.
  ldflags = [
    "-s"
    "-w"
  ];

  # The suite drives real git and just against a fake GitHub API.
  nativeCheckInputs = [ git just ];

  passthru = { inherit rev; };

  meta = {
    description = "Posts the App-signed local-signoff check run after running the trusted just signoff recipe";
    homepage = "https://github.com/dematom-labs/workflows/tree/${rev}/signoff";
    mainProgram = "signoff";
    # Only darwin can sign: keychain_other.go is a stub that refuses.
    platforms = lib.platforms.darwin;
  };
}
