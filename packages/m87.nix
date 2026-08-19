{
  buildNpmPackage,
  lib,
  makeWrapper,
  nodejs_24,
  python3,
}:

buildNpmPackage {
  pname = "m87";
  version = "0.1.10";

  src = ./m87-npm;
  npmDepsHash = "sha256-4Is/xNNo/njsp8pIllMu75tOpbZQkcKqzpfpofaolv4=";
  nodejs = nodejs_24;
  dontNpmBuild = true;

  nativeBuildInputs = [
    makeWrapper
    python3
  ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node node_modules/@kunchenguid/m87/dist/cli.js --version | grep -Fx '0.1.10'
    node -e 'const p = require("./node_modules/@kunchenguid/m87/package.json"); if (p.name !== "@kunchenguid/m87" || p.repository.url !== "git+https://github.com/kunchenguid/m87.git" || p.bin.m87 !== "dist/cli.js") process.exit(1)'
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/m87"
    cp -R node_modules "$out/libexec/m87/"
    makeWrapper ${lib.getExe nodejs_24} "$out/bin/m87" \
      --add-flags "$out/libexec/m87/node_modules/@kunchenguid/m87/dist/cli.js"

    runHook postInstall
  '';

  meta = {
    description = "Local-first review queue";
    homepage = "https://github.com/kunchenguid/m87";
    # Upstream 0.1.10 publishes no license declaration.
    license = lib.licenses.unfree;
    mainProgram = "m87";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
