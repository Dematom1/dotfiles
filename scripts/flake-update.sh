#!/usr/bin/env bash
set -euo pipefail

# Moves the self-updated flake inputs forward in the checkout given as $1
# (default: the current directory) and prints one Markdown line per change.
# - Inputs pinned to a release tag (`url = "github:owner/repo/vX.Y.Z"`) move to
#   upstream's latest stable release once it is a day old.
# - Inputs without releases track their default branch through flake.lock.
# Run by .github/workflows/flake-update.yml; needs nix, jq and an authenticated gh.

repo=${1:-.}
# Only these inputs and the release-tag pins move. Never add nixpkgs-signoff:
# its rebuilt signer drops off the App key's Keychain access list.
branch_inputs=(kubernetes-axi docker-axi)
min_age_seconds=${FLAKE_UPDATE_MIN_AGE_SECONDS:-86400}

flake="$repo/flake.nix"
now=$(date +%s)

pinned=$(grep -Eo 'github:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/v[0-9][A-Za-z0-9_.-]*"' "$flake" | tr -d '"' || true)
for ref in $pinned; do
  IFS=/ read -r owner name current <<<"${ref#github:}"
  release=$(gh api "repos/$owner/$name/releases/latest")
  latest=$(jq -r .tag_name <<<"$release")
  published=$(jq -r .published_at <<<"$release")
  age=$((now - $(jq -rn --arg t "$published" '$t | fromdateiso8601')))
  if [[ "$latest" == "$current" ]]; then
    continue
  elif ((age < min_age_seconds)); then
    echo "skip $owner/$name $latest: released ${age}s ago" >&2
    continue
  fi
  sed -i.bak "s|github:$owner/$name/$current\"|github:$owner/$name/$latest\"|" "$flake"
  rm -f "$flake.bak"
  echo "- \`$owner/$name\` $current -> $latest (https://github.com/$owner/$name/releases/tag/$latest)"
done

before=$(jq -c '.nodes' "$repo/flake.lock")
# Refreshes the branch inputs; any input whose tag changed above is re-locked too.
(cd "$repo" && nix flake update "${branch_inputs[@]}" >&2)
for input in "${branch_inputs[@]}"; do
  old=$(jq -r --arg i "$input" '.[$i].locked.rev' <<<"$before")
  new=$(jq -r --arg i "$input" '.nodes[$i].locked | "\(.owner)/\(.repo) \(.rev)"' "$repo/flake.lock")
  if [[ "${new#* }" != "$old" ]]; then
    echo "- \`${new% *}\` ${old:0:12} -> ${new: -40:12} (https://github.com/${new% *}/compare/$old...${new#* })"
  fi
done
