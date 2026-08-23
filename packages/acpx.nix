{
  buildNpmPackage,
  lib,
  makeWrapper,
  nodejs_24,
}:

buildNpmPackage {
  pname = "acpx";
  version = "0.13.1";

  src = ./acpx-npm;
  npmDepsHash = "sha256-JRG2W376A1iqTSdNsNx6v2f+bHxZSHdGQy9eK3FiqLs=";
  nodejs = nodejs_24;
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node -e 'const p = require("./node_modules/acpx/package.json"); if (p.name !== "acpx" || p.version !== "0.13.1" || p.bin.acpx !== "dist/cli.js") process.exit(1)'
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/acpx"
    cp -R node_modules "$out/libexec/acpx/"
    makeWrapper ${lib.getExe nodejs_24} "$out/bin/acpx" \
      --add-flags "$out/libexec/acpx/node_modules/acpx/dist/cli.js"

    runHook postInstall
  '';

  meta = {
    description = "Headless CLI client for the Agent Client Protocol";
    homepage = "https://github.com/openclaw/acpx";
    license = lib.licenses.mit;
    mainProgram = "acpx";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
