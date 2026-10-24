# One npm CLI from packages/npm/<name>, whose package.json pins exactly one
# dependency. importNpmLock fetches every tarball by the lockfile's own
# integrity hash, so a Renovate bump of package.json + package-lock.json builds
# as-is: there is no npmDepsHash to keep in sync.
{
  lib,
  buildNpmPackage,
  importNpmLock,
  nodejs_24,
  bun,
  npmRoot,
}:

let
  pname = baseNameOf npmRoot;
  dependency = lib.head (lib.attrNames (lib.importJSON (npmRoot + "/package.json")).dependencies);
  locked = (lib.importJSON (npmRoot + "/package-lock.json")).packages."node_modules/${dependency}";
in
buildNpmPackage {
  inherit pname;
  inherit (locked) version;

  src = npmRoot;
  npmDeps = importNpmLock { inherit npmRoot; };
  npmConfigHook = importNpmLock.npmConfigHook;
  nodejs = nodejs_24;
  dontNpmBuild = true;
  buildInputs = lib.optionals (pname == "bun-axi") [ bun ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/${pname}"
    cp -R node_modules "$out/libexec/${pname}/"
    root="$out/libexec/${pname}/node_modules/${dependency}"
    node -e '
      const p = require(process.argv[1] + "/package.json");
      const bin = typeof p.bin === "string" ? { [p.name.split("/").pop()]: p.bin } : p.bin ?? {};
      for (const [name, path] of Object.entries(bin)) console.log(name + "\t" + path);
    ' "$root" | while IFS=$'\t' read -r name path; do
      patchShebangs "$root/$path"
      ln -s "$root/$path" "$out/bin/$name"
    done

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    if find -L "$out/bin" -type l | grep .; then
      echo "dangling bin links above" >&2
      exit 1
    fi
    runHook postInstallCheck
  '';

  meta = {
    description = "${dependency} from npm";
    homepage = "https://www.npmjs.com/package/${dependency}";
    # Packages that publish no license declaration (m87 0.1.10) count as unfree.
    license = if locked ? license then lib.getLicenseFromSpdxId locked.license else lib.licenses.unfree;
    mainProgram = pname;
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
