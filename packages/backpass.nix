{
  buildNpmPackage,
  lib,
  makeWrapper,
  nodejs_24,
}:

buildNpmPackage {
  pname = "backpass";
  version = "0.1.1";

  src = ./backpass-npm;
  npmDepsHash = "sha256-kNQrMagLbxHm2+RH13tn/Gi1ZnQmHflcoxFPNMmUgTg=";
  nodejs = nodejs_24;
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node -e 'const p = require("./node_modules/backpass/package.json"); if (p.name !== "backpass" || p.version !== "0.1.1" || p.bin.backpass !== "./bin/backpass.js") process.exit(1)'
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/backpass"
    cp -R node_modules "$out/libexec/backpass/"
    makeWrapper ${lib.getExe nodejs_24} "$out/bin/backpass" \
      --add-flags "$out/libexec/backpass/node_modules/backpass/bin/backpass.js"

    runHook postInstall
  '';

  meta = {
    description = "Agent memory analysis and editing CLI";
    homepage = "https://github.com/kunchenguid/backpass";
    license = lib.licenses.mit;
    mainProgram = "backpass";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
