{
  lib,
  buildEnv,
  buildGoModule,
  bash,
  git,
  just,
  ast-grep,
  bun,
  nodejs_24,
  uv,
  python3,
  go,
  ruby,
}:

let
  # dematom-labs/workflows is private, so a flake input could not be fetched by
  # GitHub-token CI or by root during `sudo darwin-rebuild`. signoff-src is that
  # repo's signoff/ directory at this commit; scripts/vendor-signoff.sh replaces
  # both together.
  rev = "43172c88e886f98e3b7c4d4c2cd5559031454a7b";

  # The only tools `git`, `just`, and the fleet `signoff` recipes can resolve.
  # This is the signer's own versioned-tool list plus bash for `#!/usr/bin/env
  # bash` recipes. Baking it in keeps the trusted PATH read-only in /nix/store
  # instead of following the mutable user profile. Add a tool here when a repo's
  # recipe needs one, e.g. terraform when infrastructure onboards.
  tools = buildEnv {
    name = "signoff-tools";
    paths = [ bash git just ast-grep bun nodejs_24 uv python3 go ruby ];
    pathsToLink = [ "/bin" ];
  };
in
buildGoModule {
  pname = "signoff";
  version = "0-unstable-${builtins.substring 0 7 rev}";

  src = ./signoff-src;
  # Standard library only, so there is nothing to vendor.
  vendorHash = null;

  ldflags = [
    "-s"
    "-w"
    "-X main.trustedPath=${tools}/bin:/usr/bin:/bin"
  ];

  # The suite drives real git and just against a fake GitHub API.
  nativeCheckInputs = [ git just ];

  passthru = { inherit rev tools; };

  meta = {
    description = "Posts the App-signed local-signoff check run after running the trusted just signoff recipe";
    homepage = "https://github.com/dematom-labs/workflows/tree/${rev}/signoff";
    mainProgram = "signoff";
    # Only darwin can sign: keychain_other.go is a stub that refuses.
    platforms = lib.platforms.darwin;
  };
}
