#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d "$repo/.pi-signed-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

jq_bin=$(command -v jq) || fail "jq is required for Pi signed drift fixtures"
cat > "$tmp/releases.json" <<'EOF'
[
  {"tag_name":"v9.0.0-rc.1","draft":false,"prerelease":true},
  {"tag_name":"v8.0.0","draft":true,"prerelease":false},
  {"tag_name":"v0.84.2","draft":false,"prerelease":false}
]
EOF
printf '[]\n' > "$tmp/issues.json"
cat > "$tmp/fake-curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *releases*) cat "$RELEASES_JSON" ;;
  *issues*) cat "$ISSUES_JSON" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$tmp/fake-curl"
cat > "$tmp/fake-pi" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$FAKE_PI_VERSION"
EOF
chmod +x "$tmp/fake-pi"

run_drift() {
  RELEASES_JSON="$tmp/releases.json" \
  ISSUES_JSON="$tmp/issues.json" \
  FAKE_PI_VERSION="$FAKE_PI_VERSION" \
  PI_SIGNED_PI_BINARY="$tmp/fake-pi" \
  PI_SIGNED_CURL="$tmp/fake-curl" \
  PI_SIGNED_JQ="$jq_bin" \
  PI_SIGNED_UPSTREAM_RELEASES_URL=https://fixture/releases \
  PI_SIGNED_BLOCKED_ISSUES_URL=https://fixture/issues \
  "$repo/scripts/pi-signed-drift.sh"
}

FAKE_PI_VERSION=pi-0.84.2
output=$(run_drift)
[[ "$output" == "pi-signed: no drift (bundled Pi 0.84.2; upstream stable 0.84.2; no open upstream-pi-blocked issue)." ]] \
  || fail "clean drift output was not exact: $output"

FAKE_PI_VERSION=pi-0.84.1
output=$(run_drift)
[[ "$output" == *"bundled Pi 0.84.1 trails upstream stable 0.84.2"* ]] \
  || fail "version comparison did not report a stale signed bundle: $output"

cat > "$tmp/issues.json" <<'EOF'
[
  {"number":12,"title":"Upstream Pi is blocked","state":"open","labels":[{"name":"upstream-pi-blocked"}]}
]
EOF
FAKE_PI_VERSION=pi-0.84.2
output=$(run_drift)
[[ "$output" == *"open upstream-pi-blocked issue #12: Upstream Pi is blocked"* ]] \
  || fail "open upstream-pi-blocked issue was not reported: $output"
[[ "$output" != *"no drift"* ]] || fail "blocked issue produced clean output"

printf '[]\n' > "$tmp/issues.json"
cat > "$tmp/releases.json" <<'EOF'
[{"tag_name":"v0.84.1","draft":false,"prerelease":false}]
EOF
FAKE_PI_VERSION=pi-0.84.2
output=$(run_drift)
[[ "$output" == "pi-signed: no drift (bundled Pi 0.84.2; upstream stable 0.84.1; no open upstream-pi-blocked issue)." ]] \
  || fail "newer bundled version was treated as stale: $output"

if [[ "$(nix eval --impure --raw --expr 'builtins.currentSystem')" == aarch64-darwin ]]; then
  prefix=darwinConfigurations.personal.config.home-manager.users.laszlohoranszky
  entrypoint=$(nix build --no-link --print-out-paths "$repo#$prefix.home.file.\".local/bin/pi-signed\".source")
  [[ -x "$entrypoint" ]] || fail "Home Manager did not expose an executable pi-signed entrypoint"
  grep -Fq 'FM_PI_HARNESS=pi-signed' "$entrypoint" || fail "signed entrypoint omitted harness identity"

  fake_av="$tmp/fake-av"
  fake_target="$tmp/signed-target"
  fake_regular_pi="$tmp/pi"
  harness_file="$tmp/harness"
  args_file="$tmp/args"
  av_called="$tmp/av-called"
  regular_called="$tmp/regular-called"
  cat > "$fake_av" <<'EOF'
#!/usr/bin/env bash
: > "$AV_CALLED"
printf '%s\n' "${FM_PI_HARNESS-}" > "$HARNESS_FILE"
if [[ ${FAIL_AV:-0} == 1 ]]; then
  exit 42
fi
[[ "$#" -ge 4 ]] || exit 70
[[ "$1" == inject && "$2" == +OPENCODE_API_KEY && "$3" == -- && "$4" == "$EXPECTED_TARGET" ]] || exit 71
shift 4
exec "$EXPECTED_TARGET" "$@"
EOF
  cat > "$fake_target" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$#" > "$ARGS_FILE"
printf '<%s>\n' "$@" >> "$ARGS_FILE"
EOF
  cat > "$fake_regular_pi" <<'EOF'
#!/usr/bin/env bash
: > "$REGULAR_CALLED"
EOF
  chmod +x "$fake_av" "$fake_target" "$fake_regular_pi"

  rendered="$tmp/pi-signed"
  sed \
    -e "s#/usr/local/bin/av#$fake_av#g" \
    -e "s#/Applications/Pi Launcher.app/Contents/MacOS/pi-launcher#$fake_target#g" \
    "$entrypoint" > "$rendered"
  chmod +x "$rendered"

  EXPECTED_TARGET="$fake_target" AV_CALLED="$av_called" HARNESS_FILE="$harness_file" \
  ARGS_FILE="$args_file" REGULAR_CALLED="$regular_called" PATH="$tmp:$PATH" \
  env -u OPENCODE_API_KEY FM_PI_HARNESS=wrong "$rendered" alpha "two words" "" --flag=value
  mapfile -t argv < "$args_file"
  [[ ${argv[0]} == 4 && ${argv[1]} == '<alpha>' && ${argv[2]} == '<two words>' \
    && ${argv[3]} == '<>' && ${argv[4]} == '<--flag=value>' ]] \
    || fail "signed entrypoint did not preserve argv: ${argv[*]}"
  [[ $(<"$harness_file") == pi-signed ]] || fail "signed entrypoint did not set FM_PI_HARNESS"
  [[ ! -e "$regular_called" ]] || fail "signed entrypoint fell back to regular pi"

  rm -f "$args_file" "$av_called" "$regular_called"
  set +e
  EXPECTED_TARGET="$fake_target" AV_CALLED="$av_called" HARNESS_FILE="$harness_file" \
  ARGS_FILE="$args_file" REGULAR_CALLED="$regular_called" FAIL_AV=1 PATH="$tmp:$PATH" \
  "$rendered" probe
  status=$?
  set -e
  [[ $status -eq 42 ]] || fail "Vault failure was masked by a fallback (status $status)"
  [[ ! -e "$regular_called" && ! -e "$args_file" ]] || fail "signed route ran an insecure fallback after Vault failure"

  rm -f "$av_called"
  set +e
  EXPECTED_TARGET="$fake_target" AV_CALLED="$av_called" HARNESS_FILE="$harness_file" \
  ARGS_FILE="$args_file" REGULAR_CALLED="$regular_called" "$rendered" update --self
  status=$?
  set -e
  [[ $status -eq 64 ]] || fail "signed route allowed pi update --self (status $status)"
  [[ ! -e "$av_called" ]] || fail "signed route invoked Vault for disabled pi update --self"
fi

grep -Fq '/Applications/Pi\ Launcher.app/Contents/MacOS/pi-launcher --version' "$repo/README.md" \
  || fail "README omitted the raw no-secret signed-app diagnostic path"

printf '%s\n' "Pi signed entrypoint and drift checks passed"
