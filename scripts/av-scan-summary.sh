#!/usr/bin/env bash
set -euo pipefail

require_clean=false
scanner=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-clean)
      require_clean=true
      shift
      ;;
    --scanner)
      [[ $# -ge 2 ]] || { echo "missing value for --scanner" >&2; exit 2; }
      scanner=$2
      shift 2
      ;;
    --help)
      echo "usage: av-scan-summary.sh [--require-clean] [--scanner PATH]"
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z $scanner ]]; then
  scanner=$(command -v av) || {
    echo "Automic Vault scanner is unavailable" >&2
    exit 1
  }
fi
[[ -x $scanner ]] || {
  echo "Automic Vault scanner is not executable" >&2
  exit 1
}

zsh_bin=$(command -v zsh) || {
  echo "zsh is unavailable" >&2
  exit 1
}
jq_bin=$(command -v jq) || {
  echo "jq is unavailable" >&2
  exit 1
}

# Only the reduced source/severity counts reach disk or stdout. The scanner's
# raw report flows directly into jq and is never printed by this wrapper.
summary_file=$(mktemp)
trap 'rm -f "$summary_file"' EXIT

set +e
# The child zsh expands $1 to the absolute scanner path passed after --.
# shellcheck disable=SC2016
"$zsh_bin" -lic 'exec "$1" scan --json' -- "$scanner" 2>/dev/null \
  | "$jq_bin" -ce '
      if type != "object" or (.findings | type) != "array" then
        error("invalid scanner report")
      else
        {
          total: (.findings | length),
          categories: (
            [.findings[] | {source, severity}]
            | group_by([.source, .severity])
            | map({
                source: .[0].source,
                severity: .[0].severity,
                count: length
              })
            | sort_by([.source, .severity])
          )
        }
      end
    ' >"$summary_file"
pipeline_status=("${PIPESTATUS[@]}")
set -e

if [[ ${pipeline_status[0]} -ne 0 ]]; then
  echo "Automic Vault scanner failed operationally with exit ${pipeline_status[0]}" >&2
  exit 1
fi
if [[ ${pipeline_status[1]} -ne 0 ]]; then
  echo "Automic Vault scanner returned an invalid report" >&2
  exit 1
fi

cat "$summary_file"

if $require_clean && ! "$jq_bin" -e '.total == 0' "$summary_file" >/dev/null; then
  echo "Automic Vault operator scan still has findings" >&2
  exit 1
fi
