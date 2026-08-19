#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

system=$(nix eval --impure --raw --expr 'builtins.currentSystem')
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

  [[ $(nix eval --json "$repo#$prefix.home.file" \
    --apply 'files: builtins.hasAttr ".claude/skills" files') == true ]] \
    || fail "$profile does not expose the generated Claude skill root"

  m87_config=$(nix eval --raw "$repo#$prefix.home.activation.m87GithubDiscovery.data")
  [[ "$m87_config" == *'init --yes --plugin github'* && "$m87_config" == *'--github-repo dematom-labs/agent-sandbox-runtime'* ]] \
    || fail "$profile M87 discovery does not use the native headless initializer"
  [[ "$m87_config" != *' plugin sync '* && "$m87_config" != *' status'* ]] \
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

skills_update=$(cd "$repo" && just --dry-run update-skills 2>&1)
[[ "$skills_update" == *"skills add kunchenguid/vision -g -y --agent '*' --copy"* ]] \
  || fail "Vision is not declared through the all-agent copy-mode owner"
[[ $(grep -c "skills add .* --agent '\*' --copy" <<<"$skills_update") -eq 4 ]] \
  || fail "not every all-agent skills source uses copy mode"
grep -Fq "npx -y skills add kunchenguid/vision -g -y --agent '*' --copy" "$repo/.agents/SKILLS.md" \
  || fail "Vision provenance does not match its copy-mode installer"

! git -C "$repo" ls-files --error-unmatch .agents/skills/vision/SKILL.md >/dev/null 2>&1 \
  || fail "generated Vision files were committed"
! git -C "$repo" ls-files '.claude/plugins/**' | grep -q . \
  || fail "generated Claude plugin registry files were committed"

grep -Fq 'FM_PI_HARNESS=pi-signed pi-signed' "$repo/README.md" \
  || fail "README omits the exact signed Firstmate launch command"

echo "Nix-managed agent tool and discovery checks passed"
