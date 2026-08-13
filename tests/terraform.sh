#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Pinned via the nixpkgs-unstable overlay in flake.nix. Bump this alongside
# that input's lock entry so a stale pin (e.g. a silent fall-back to the
# older stable-branch build) fails this test instead of going unnoticed.
expected_version="1.15.8"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if grep -Eq '^[[:space:]]*brew "[^"]*terraform' "$repo/Brewfile"; then
  fail "Brewfile still declares Terraform outside the Nix-managed operator package path"
fi

system=$(nix eval --impure --raw --expr 'builtins.currentSystem')
case "$system" in
  aarch64-darwin)
    targets=(
      "personal:laszlohoranszky:darwinConfigurations.personal.config.home-manager.users.laszlohoranszky.home"
      "work:laszlo:darwinConfigurations.work.config.home-manager.users.laszlo.home"
    )
    ;;
  x86_64-linux|aarch64-linux)
    targets=("sandbox:captain:homeConfigurations.\"captain@$system\".config.home")
    ;;
  *)
    fail "unsupported test host system '$system'"
    ;;
esac

for target in "${targets[@]}"; do
  IFS=: read -r profile user prefix <<<"$target"

  [[ $(nix eval --raw "$repo#$prefix.packages" \
    --apply 'pkgs: if builtins.any (pkg: (pkg.pname or "") == "terraform") pkgs then "present" else "absent"') == present ]] \
    || fail "$profile profile does not evaluate Terraform in Home Manager packages"

  home_path=$(nix build --no-link --print-out-paths "$repo#$prefix.path")
  [[ -x "$home_path/bin/terraform" ]] \
    || fail "$profile profile Home Manager path does not contain an executable Terraform"
  [[ $("$home_path/bin/terraform" version) == "Terraform v${expected_version}"* ]] \
    || fail "$profile profile Home Manager Terraform executable did not report expected version v${expected_version}"

  activation_bin="/etc/profiles/per-user/$user/bin"
  if [[ "$user" == "$(id -un)" && -x "$activation_bin/terraform" ]]; then
    zsh=$(command -v zsh) || fail "zsh is required to verify the activated operator path"
    resolved=$(env -i HOME="${HOME:-/tmp}" USER="$user" \
      PATH="$activation_bin:/run/current-system/sw/bin" "$zsh" -fc 'command -v terraform')
    [[ "$resolved" == "$activation_bin/terraform" ]] \
      || fail "$profile profile activated operator path resolved Terraform as '$resolved'"
  else
    echo "Skipping $profile live activation check: no safe current Terraform activation evidence"
  fi
done

echo "Terraform package and operator path checks passed"
