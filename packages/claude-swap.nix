{ lib, python3Packages, fetchPypi }:

let
  # The nixpkgs pin has 8.2.6; claude-swap requires >=8.2.8,<9.
  textual = python3Packages.textual.overridePythonAttrs (old: rec {
    version = "8.2.8";
    src = fetchPypi {
      pname = "textual";
      inherit version;
      hash = "sha256-PxBqn7xz453SZslxJDIIfeeKbWRAhMfCQdaiXDFpEVs=";
    };
    dependencies = old.dependencies ++ [ python3Packages.pygments ];
  });
in
python3Packages.buildPythonApplication rec {
  pname = "claude-swap";
  version = "0.29.0";
  pyproject = true;

  src = fetchPypi {
    pname = "claude_swap";
    inherit version;
    hash = "sha256-F1kyKZt/YnuEDdzmPa/AWuzC010Wh5K06fK5ThkqOXg=";
  };

  build-system = [ python3Packages.hatchling ];
  dependencies = [ textual python3Packages.truststore ];
  pythonImportsCheck = [ "claude_swap" ];

  meta = {
    description = "Multi-account switcher for Claude Code";
    homepage = "https://github.com/realiti4/claude-swap";
    license = lib.licenses.mit;
    mainProgram = "cswap";
  };
}
