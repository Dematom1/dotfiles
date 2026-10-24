#!/usr/bin/env bash
# Replaces packages/signoff-src with signoff/ from dematom-labs/workflows at the
# given commit and pins packages/signoff.nix to it. Needs SSH access to that
# private repository. See README.md "Local signoff".
set -euo pipefail

rev="${1:?usage: scripts/vendor-signoff.sh <dematom-labs/workflows commit SHA>}"
if [[ ! $rev =~ ^[0-9a-f]{40}$ ]]; then
  echo "vendor-signoff: '$rev' is not a full lowercase commit SHA" >&2
  exit 1
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone --quiet --filter=blob:none --no-checkout \
  git@github.com:dematom-labs/workflows.git "$tmp/workflows"
mkdir "$tmp/src"
git -C "$tmp/workflows" archive "$rev" signoff | tar -x -C "$tmp/src" --strip-components=1

rm -rf "$root/packages/signoff-src"
mv "$tmp/src" "$root/packages/signoff-src"
sed -i.bak -E "s/^  rev = \"[0-9a-f]{40}\";/  rev = \"$rev\";/" "$root/packages/signoff.nix"
rm "$root/packages/signoff.nix.bak"
grep -q "^  rev = \"$rev\";" "$root/packages/signoff.nix"

echo "Vendored signoff at $rev. Run 'nix build .#signoff' to build it and run its tests."
echo "After the next rebuild, the new binary must be added to the App key's access list again."
