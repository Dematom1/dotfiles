#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d "$repo/.tailscale-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

wrapper=${1:?usage: tailscale-app-cli.sh wrapper-path}
[[ -x "$wrapper" ]] || fail "Home Manager tailscale wrapper is not executable"

cat > "$tmp/app-cli" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$ARGS_FILE"
exit "$APP_STATUS"
EOF
chmod +x "$tmp/app-cli"
sed "s#/Applications/Tailscale.app/Contents/MacOS/Tailscale#$tmp/app-cli#g" \
  "$wrapper" > "$tmp/tailscale"
chmod +x "$tmp/tailscale"

for expected_status in 0 42; do
  rm -f "$tmp/args"
  status=0
  ARGS_FILE="$tmp/args" APP_STATUS="$expected_status" \
    "$tmp/tailscale" status 'two words' '' '--flag=value' '*' $'line\nbreak' || status=$?
  [[ $status -eq $expected_status ]] \
    || fail "tailscale returned $status instead of app status $expected_status"
  [[ -f "$tmp/args" ]] || fail "tailscale did not invoke the app CLI"
  printf '%s\0' status 'two words' '' '--flag=value' '*' $'line\nbreak' > "$tmp/expected"
  cmp -s "$tmp/expected" "$tmp/args" || fail "tailscale did not preserve arguments"
done

echo "Tailscale app CLI checks passed"
