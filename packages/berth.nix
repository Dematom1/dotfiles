{ buildGoModule, fetchFromGitHub }:

# Switch to the berth flake package / v0.2.0 tag once upstream PR 15 lands.
buildGoModule {
  pname = "berth";
  version = "0-unstable-2026-11-10";
  src = fetchFromGitHub {
    owner = "Dematom1";
    repo = "berth";
    rev = "56bf0b3a3297cbee14f46679c0269b7afa2afa45";
    hash = "sha256-Z4yOXT+nMhxvhN4sWFSpWKPIZQf6l7fqcslWtALK84M=";
  };
  vendorHash = "sha256-9NZPsKyrQzROASqJEvUt8l7n8HXe8DUCACkxYCIOEC0=";
  subPackages = [ "." ];
  # Upstream tests inspect live processes and hw.memsize, denied by Darwin's sandbox.
  doCheck = false;
  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/berth" --version
    "$out/bin/berth" sweep --help
  '';
}
