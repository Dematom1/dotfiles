{
  lib,
  stdenvNoCC,
  makeWrapper,
  nodejs_24,
  src,
}:

let
  packageJson = builtins.fromJSON (builtins.readFile "${src}/package.json");
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

    install -Dm755 bin/kubernetes-axi.js \
      "$out/libexec/kubernetes-axi/kubernetes-axi.js"
    makeWrapper ${lib.getExe nodejs_24} "$out/bin/kubernetes-axi" \
      --add-flags "$out/libexec/kubernetes-axi/kubernetes-axi.js"

    runHook postInstall
  '';

  meta = {
    inherit (packageJson) description;
    homepage = "https://github.com/thatdudealso/kubernetes-axi";
    license = lib.licenses.mit;
    mainProgram = "kubernetes-axi";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
