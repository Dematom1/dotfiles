# A dependency-free Node CLI built from its GitHub source (a flake input), for
# AXI tools that are not published to npm. The build runs upstream's unit suite.
{
  lib,
  stdenvNoCC,
  makeWrapper,
  nodejs_24,
  src,
}:

let
  packageJson = builtins.fromJSON (builtins.readFile "${src}/package.json");
  bin = packageJson.bin.${packageJson.name};
in
stdenvNoCC.mkDerivation {
  pname = packageJson.name;
  version = packageJson.version;

  inherit src;

  nativeBuildInputs = [
    makeWrapper
    nodejs_24
  ];

  dontBuild = true;
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    node --test
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 ${bin} \
      "$out/libexec/${packageJson.name}/${baseNameOf bin}"
    makeWrapper ${lib.getExe nodejs_24} "$out/bin/${packageJson.name}" \
      --add-flags "$out/libexec/${packageJson.name}/${baseNameOf bin}"

    runHook postInstall
  '';

  meta = {
    inherit (packageJson) description;
    homepage = "https://github.com/thatdudealso/${packageJson.name}";
    license = lib.licenses.mit;
    mainProgram = packageJson.name;
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
