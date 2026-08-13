#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for profile_user in personal:laszlohoranszky work:laszlo; do
  IFS=: read -r profile user <<<"$profile_user"
  prefix="darwinConfigurations.$profile.config.home-manager.users.$user.home"

  [[ $(nix eval --raw "$repo#$prefix.packages" \
    --apply 'pkgs: if builtins.any (pkg: (pkg.pname or "") == "terraform") pkgs then "present" else "absent"') == present ]] \
    || fail "$profile profile does not evaluate Terraform in Home Manager packages"

  home_path=$(nix build --no-link --print-out-paths "$repo#$prefix.path")
  [[ -x "$home_path/bin/terraform" ]] \
    || fail "$profile profile Home Manager path does not contain an executable Terraform"
  [[ $("$home_path/bin/terraform" version) == Terraform\ v* ]] \
    || fail "$profile profile Home Manager Terraform executable did not report its version"

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
