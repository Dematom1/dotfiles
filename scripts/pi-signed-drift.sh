#!/usr/bin/env bash
set -euo pipefail

# Read-only report for the Pi binary inside the signed launcher bundle.
app_dir=${PI_SIGNED_APP_DIR:-/Applications/Pi Launcher.app}
pi_binary=${PI_SIGNED_PI_BINARY:-$app_dir/Contents/Resources/pi/pi}
curl_bin=${PI_SIGNED_CURL:-curl}
jq_bin=${PI_SIGNED_JQ:-jq}
releases_url="${PI_SIGNED_UPSTREAM_RELEASES_URL:-https://api.github.com/repos/earendil-works/pi/releases?per_page=100}"
blocked_url="${PI_SIGNED_BLOCKED_ISSUES_URL:-https://api.github.com/repos/kunchenguid/pi-launcher/issues?state=open&labels=upstream-pi-blocked&per_page=100}"

fail() {
  echo "pi-signed: drift check failed: $*" >&2
  exit 1
}

version_from() {
  local text=$1
  if [[ $text =~ (^|[^0-9])([0-9]+\.[0-9]+\.[0-9]+)([^0-9]|$) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
  else
    return 1
  fi
}

version_lt() {
  local left=$1 right=$2
  local left_major left_minor left_patch right_major right_minor right_patch
  IFS=. read -r left_major left_minor left_patch <<<"$left"
  IFS=. read -r right_major right_minor right_patch <<<"$right"
  ((left_major < right_major)) || {
    ((left_major == right_major && left_minor < right_minor)) || {
      ((left_major == right_major && left_minor == right_minor && left_patch < right_patch))
    }
  }
}

if [[ ! -x "$pi_binary" ]]; then
  echo "pi-signed: drift check skipped (signed bundle is not installed)."
  exit 0
fi
bundle_output=$(
  unset OPENCODE_API_KEY
  "$pi_binary" --version 2>&1
) || fail "could not read $pi_binary --version"
bundle_version=$(version_from "$bundle_output") || fail "unparseable bundled Pi version: $bundle_output"

releases_json=$("$curl_bin" -fsSL "$releases_url") || fail "could not read upstream stable releases"
upstream_version=$("$jq_bin" -r '
  [.[]
   | select((.draft | not) and (.prerelease | not))
   | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
   | .tag_name[1:]]
  | first // empty
' <<<"$releases_json")
[[ -n "$upstream_version" ]] || fail "upstream stable version was not found"

blocked_json=$("$curl_bin" -fsSL "$blocked_url") || fail "could not read open upstream-pi-blocked issues"
blocked_issue=$("$jq_bin" -r '
  [.[]
   | select((.state // "") == "open")
   | select(has("pull_request") | not)
   | select(any(.labels[]?; .name == "upstream-pi-blocked"))]
  | first
  | if . == null then "" else "#\(.number): \(.title)" end
' <<<"$blocked_json")

if version_lt "$bundle_version" "$upstream_version"; then
  echo "pi-signed: drift notice: bundled Pi $bundle_version trails upstream stable $upstream_version."
fi
if [[ -n "$blocked_issue" ]]; then
  echo "pi-signed: drift notice: open upstream-pi-blocked issue $blocked_issue."
fi
if ! version_lt "$bundle_version" "$upstream_version" && [[ -z "$blocked_issue" ]]; then
  echo "pi-signed: no drift (bundled Pi $bundle_version; upstream stable $upstream_version; no open upstream-pi-blocked issue)."
fi
