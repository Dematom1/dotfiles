{
  buildNpmPackage,
  lib,
  nodejs_24,
}:

buildNpmPackage {
  pname = "pi-fff";
  version = "0.10.5";

  src = ./pi-fff-npm;
  npmDepsHash = "sha256-xEpDYFMEle8HDEQgZHA9Ru0AIm7FQ5soGsMUSDCXfgE=";
  nodejs = nodejs_24;
  npmFlags = [ "--legacy-peer-deps" ];
  dontNpmBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    test -f node_modules/@ff-labs/pi-fff/src/index.ts
    node -e 'const p = require("./node_modules/@ff-labs/pi-fff/package.json"); if (p.name !== "@ff-labs/pi-fff" || p.version !== "0.10.5" || p.pi.extensions[0] !== "./src/index.ts") process.exit(1)'
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/libexec/pi-fff"
    cp -R node_modules "$out/libexec/pi-fff/"

    runHook postInstall
  '';

  passthru.extensionPath = "libexec/pi-fff/node_modules/@ff-labs/pi-fff/src";

  meta = {
    description = "FFF-powered file and content search extension for Pi";
    homepage = "https://github.com/dmtrKovalenko/fff/tree/main/packages/pi-fff";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
