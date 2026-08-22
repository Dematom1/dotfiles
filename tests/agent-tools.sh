#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

system=$(nix eval --impure --raw --expr 'builtins.currentSystem')
bash_bin=$(command -v bash)
case "$system" in
  aarch64-darwin)
    targets=(
      'personal:darwinConfigurations.personal.config.home-manager.users.laszlohoranszky'
      'work:darwinConfigurations.work.config.home-manager.users.laszlo'
    )
    ;;
  x86_64-linux|aarch64-linux)
    targets=("sandbox:homeConfigurations.\"captain@$system\".config")
    ;;
  *) fail "unsupported test host system '$system'" ;;
esac

nix build --no-link "$repo#checks.$system.agent-tools-layout"
m87_package=$(nix build --no-link --print-out-paths "$repo#m87")
node -e 'const p = require(process.argv[1]); if (p.name !== "@kunchenguid/m87" || p.version !== "0.1.10" || p.repository.url !== "git+https://github.com/kunchenguid/m87.git") process.exit(1)' \
  "$m87_package/libexec/m87/node_modules/@kunchenguid/m87/package.json" \
  || fail "M87 package identity does not match the authoritative upstream"

for target in "${targets[@]}"; do
  IFS=: read -r profile prefix <<<"$target"

  packages=$(nix eval --raw "$repo#$prefix.home.packages" \
    --apply 'pkgs: builtins.concatStringsSep "," (map (pkg: pkg.pname or "") pkgs)')
  [[ ",$packages," == *,m87,* ]] || fail "$profile profile does not install M87"

  home_path=$(nix build --no-link --print-out-paths "$repo#$prefix.home.path")
  [[ -x "$home_path/bin/m87" ]] || fail "$profile Home Manager path has no M87 executable"
  [[ $("$home_path/bin/m87" --version) == 0.1.10 ]] \
    || fail "$profile M87 executable has the wrong version"

  pi_fff=$(nix eval --raw "$repo#$prefix.home.file.\".pi/agent/extensions/pi-fff\".source")
  [[ -f "$pi_fff/index.ts" ]] || fail "$profile Pi extension path has no pi-fff entrypoint"
  node -e 'const p = require(process.argv[1]); if (p.name !== "@ff-labs/pi-fff" || p.version !== "0.10.5" || p.pi.extensions[0] !== "./src/index.ts") process.exit(1)' \
    "$(dirname "$pi_fff")/package.json" \
    || fail "$profile Pi extension path has the wrong package identity"

  pi_packages=$(nix eval --raw "$repo#$prefix.home.activation.piPackageReconciliation.data")

  models_source=$(nix eval --raw "$repo#$prefix.home.file.\".pi/agent/models.json\".source")
  [[ -L "$models_source" && "$(readlink "$models_source")" == */pi/models.json ]] \
    || fail "$profile Pi models catalog is not sourced from the repository"
  jq -e '.providers["opencode-go"].apiKey == "$OPENCODE_API_KEY"' "$repo/pi/models.json" >/dev/null \
    || fail "$profile Pi models catalog lost its non-secret credential reference"

  [[ $(nix eval --json "$repo#$prefix.home.file" \
    --apply 'files: builtins.hasAttr ".claude/skills" files') == true ]] \
    || fail "$profile does not expose the generated Claude skill root"

  m87_config=$(nix eval --raw "$repo#$prefix.home.activation.m87GithubDiscovery.data")
  [[ "$m87_config" == *'init --yes --plugin github'* && "$m87_config" == *'--github-repo dematom-labs/agent-sandbox-runtime'* ]] \
    || fail "$profile M87 discovery does not use the native headless initializer"
  [[ "$m87_config" != *' plugin sync '* && "$m87_config" != *'m87 status'* ]] \
    || fail "$profile M87 activation performs post-activation verification"
  [[ "$m87_config" == *'owned_repos=true'* ]] \
    || fail "$profile M87 discovery dropped personal repositories"
  [[ "$m87_config" == *'authored_external=true'* ]] \
    || fail "$profile M87 discovery omits Dematom1-authored external PRs"
  [[ "$m87_config" == *'explicit_repos=dematom-labs/agent-sandbox-runtime,dematom-labs/alteran,dematom-labs/conference-directory,dematom-labs/infrastructure,dematom-labs/seo-scout,dematom-labs/truediyer'* ]] \
    || fail "$profile M87 discovery has the wrong Dematom Labs allowlist"
  [[ "$m87_config" != *TOKEN* && "$m87_config" != *username=dematom-labs* ]] \
    || fail "$profile M87 discovery embeds credentials or changes viewer identity"
done

m87_sandbox=$(mktemp -d "$repo/.agent-tools-m87.XXXXXX")
awkless_sandbox=$(mktemp -d "$repo/.agent-tools-m87-awkless.XXXXXX")
pi_sandbox=$(mktemp -d "$repo/.agent-tools-pi.XXXXXX")
skills_sandbox=$(mktemp -d "$repo/.agent-tools-skills.XXXXXX")
trap 'rm -rf "$m87_sandbox" "$awkless_sandbox" "$pi_sandbox" "$skills_sandbox"' EXIT
M87_STATE_DIR="$m87_sandbox/state" "$m87_package/bin/m87" \
  init --yes --plugin skip --no-install-service >/dev/null
DRY_RUN_CMD='' M87_STATE_DIR="$m87_sandbox/state" HOME="$m87_sandbox/home" \
  bash -euo pipefail -c "$m87_config"
M87_STATE_DIR="$m87_sandbox/state" "$m87_package/bin/m87" plugin list \
  | awk '
      /^installed:/ { in_installed = 1; next }
      /^[^[:space:]]/ { in_installed = 0 }
      in_installed && /^[[:space:]]*-[[:space:]]+id:[[:space:]]+github[[:space:]]*$/ { found = 1 }
      END { exit !found }
    ' \
  || fail "M87 activation did not add the missing bundled GitHub plugin"

M87_STATE_DIR="$awkless_sandbox/state" "$m87_package/bin/m87" \
  init --yes --plugin skip --no-install-service >/dev/null
set +e
awkless_output=$(env -i HOME="$awkless_sandbox/home" USER=agent \
  PATH="$m87_package/bin" M87_STATE_DIR="$awkless_sandbox/state" DRY_RUN_CMD='' \
  "$bash_bin" -euo pipefail -c "$m87_config" 2>&1)
awkless_status=$?
set -e
[[ $awkless_status -eq 0 ]] || fail "M87 activation failed without PATH awk: $awkless_output"
[[ "$awkless_output" != *EPIPE* ]] || fail "M87 activation still emitted a downstream EPIPE"

failure_m87="$m87_sandbox/failing-m87"
cat > "$failure_m87" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "plugin list" ]]; then
  echo "simulated plugin list failure" >&2
  exit 23
fi
exit 0
EOF
chmod +x "$failure_m87"
failure_state="$m87_sandbox/failure-state"
mkdir -p "$failure_state"
touch "$failure_state/m87.sqlite"
failure_config=${m87_config//"$m87_package/bin/m87"/"$failure_m87"}
set +e
failure_output=$(M87_STATE_DIR="$failure_state" DRY_RUN_CMD='' \
  bash -euo pipefail -c "$failure_config" 2>&1)
failure_status=$?
set -e
[[ $failure_status -eq 23 ]] || fail "M87 plugin-list failure returned $failure_status instead of 23"
[[ "$failure_output" == *"simulated plugin list failure"* && "$failure_output" == *"plugin list failed"* ]] \
  || fail "M87 plugin-list failure diagnostics were hidden"

mkdir -p "$pi_sandbox/.pi/agent"
cat > "$pi_sandbox/.pi/agent/settings.json" <<'EOF'
{
  "theme": "captain-local",
  "packages": [
    "npm:pi-web-access@0.14.0",
    "npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6",
    "git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055",
    "git:github.com/DietrichGebert/ponytail",
    "npm:@ff-labs/pi-fff",
    "npm:pi-autoresearch",
    "npm:pi-autoresearch",
    "/Users/laszlohoranszky/.local/lib/node_modules/memtrace/pi-package"
  ]
}
EOF
DRY_RUN_CMD='' HOME="$pi_sandbox" bash -euo pipefail -c "$pi_packages"
settings="$pi_sandbox/.pi/agent/settings.json"
[[ $(jq '[.packages[] | select(. == "npm:pi-autoresearch")] | length' "$settings") -eq 1 ]] \
  || fail "generated Pi settings do not contain pi-autoresearch exactly once"
[[ $(jq '[.packages[] | select(. == "npm:@ff-labs/pi-fff")] | length' "$settings") -eq 0 ]] \
  || fail "generated Pi settings retain the duplicate Nix-managed pi-fff package"
[[ $(jq -r '.theme' "$settings") == captain-local ]] \
  || fail "Pi package reconciliation discarded unrelated local settings"
for package in \
  'npm:pi-web-access@0.14.0' \
  'npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6' \
  'git:github.com/DietrichGebert/ponytail' \
  '/Users/laszlohoranszky/.local/lib/node_modules/memtrace/pi-package'; do
  jq -e --arg package "$package" '.packages | index($package) != null' "$settings" >/dev/null \
    || fail "Pi package reconciliation dropped $package"
done

if [[ "$system" == aarch64-darwin ]]; then
  for profile in personal work; do
    casks=$(nix eval --raw "$repo#darwinConfigurations.$profile.config.homebrew.casks" \
      --apply 'casks: builtins.concatStringsSep "," (map (cask: cask.name) casks)')
    [[ ",$casks," == *,kunchenguid/tap/pi-launcher,* ]] \
      || fail "$profile does not declare Pi Launcher"
    [[ ",$casks," == *,automic-vault/isotopes/automic-vault,* ]] \
      || fail "$profile does not declare the unified Automic Vault app/CLI cask"
  done
fi

HOME="$skills_sandbox" npx -y skills add kunchenguid/vision -g -y --agent '*' --copy >/dev/null
HOME="$skills_sandbox" npx -y skills add mattpocock/skills --skill teach -g -y --agent '*' --copy >/dev/null
HOME="$skills_sandbox" npx -y skills add humanlayer/skills --skill show-me -g -y --agent '*' --copy >/dev/null
for skill in vision teach show-me; do
  [[ -f "$skills_sandbox/.claude/skills/$skill/SKILL.md" ]] \
    || fail "sandboxed Claude runtime cannot discover $skill"
  [[ -f "$skills_sandbox/.pi/agent/skills/$skill/SKILL.md" ]] \
    || fail "sandboxed Pi runtime cannot discover $skill"
done

skills_update=$(cd "$repo" && just --dry-run update-skills 2>&1)
[[ "$skills_update" == *"skills add kunchenguid/vision -g -y --agent '*' --copy"* ]] \
  || fail "Vision is not declared through the all-agent copy-mode owner"
[[ "$skills_update" == *"skills add mattpocock/skills --skill teach -g -y --agent '*' --copy"* ]] \
  || fail "Matt Teach is not declared through the all-agent copy-mode owner"
[[ "$skills_update" == *"skills add humanlayer/skills --skill show-me -g -y --agent '*' --copy"* ]] \
  || fail "HumanLayer Show Me is not declared through the all-agent copy-mode owner"
[[ $(grep -c "skills add .* --agent '\*' --copy" <<<"$skills_update") -eq 6 ]] \
  || fail "not every all-agent skills source uses copy mode"
[[ $(grep -Fc 'mattpocock/skills --skill' <<<"$skills_update") -eq 1 ]] \
  || fail "an unapproved Matt Pocock skill source is declared"
! git -C "$repo" ls-files --error-unmatch .agents/skills/vision/SKILL.md >/dev/null 2>&1 \
  || fail "generated Vision files were committed"
! git -C "$repo" ls-files '.claude/plugins/**' | grep -q . \
  || fail "generated Claude plugin registry files were committed"

grep -Fq 'FM_PI_HARNESS=pi-signed pi-signed' "$repo/README.md" \
  || fail "README omits the exact signed Firstmate launch command"

echo "Nix-managed agent tool and discovery checks passed"
