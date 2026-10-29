#!/usr/bin/env bash
# Run every dotfiles verification journey; never switches the live system.
# usage: verify.sh [personal|work]
# Evidence: $DOTFILES_VERIFY_OUT (default ~/.cache/dotfiles-verify)/<UTC stamp>/
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
out="${DOTFILES_VERIFY_OUT:-$HOME/.cache/dotfiles-verify}/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
exec > >(tee "$out/summary.txt") 2>&1
echo "evidence: $out"
status=0
"$here/build.sh" "$out/build" "${1:-}" || status=1
if [[ -f "$out/build/build.env" ]]; then
  generation=$(sed -n 's/^GENERATION=//p' "$out/build/build.env")
  python3 "$here/m87-handoff.py" "$generation" "$out" || status=1
  "$here/av-launcher.sh" "$generation" "$out/av" || status=1
fi
if [[ $status -eq 0 ]]; then echo "verify: PASS"; else echo "verify: FAIL (see $out)"; fi
exit "$status"
