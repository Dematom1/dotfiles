#!/usr/bin/env bash
set -euo pipefail

# Pass an npm 12+ executable to exercise Renovate's remote-fetch defaults.
npm=${1:-npm}
version=$("$npm" --version)
if (( ${version%%.*} < 12 )); then
  echo "npm 12+ required (got $version); pass its executable as the first argument" >&2
  exit 1
fi
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d)
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT
cp -R "$repo/packages/npm/npm-cli/." "$work/"
rm "$work/package-lock.json"

(
  cd "$work"
  # npm_config_store is injected by Renovate for pnpm; npm only warns about it.
  npm_config_cache="$work/cache" npm_config_store="$work/store" \
    "$npm" install --package-lock-only --ignore-scripts --no-audit
)
# Maintenance must regenerate the pinned npm and its bundled dependency tree.
cmp "$repo/packages/npm/npm-cli/package-lock.json" "$work/package-lock.json"
echo "PASS: npm $version regenerated the npm CLI lockfile"
