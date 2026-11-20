#!/usr/bin/env bash
# Run the dibs-sweep launchd job script against fake dibs binaries:
#   tests/dibs-sweep-job.sh JOB_SCRIPT DIBS_BIN
# JOB_SCRIPT is the job's `/bin/sh -c` argument; DIBS_BIN is the dibs path it names.
# Run by the dibs-sweep-launchd flake check.
set -euo pipefail
job=$1
dibs_bin=$2
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ $job == *"$dibs_bin sweep --confirm --json"* ]] || fail "job does not run the pinned sweep: $job"
script=${job//"$dibs_bin"/"$work/dibs"}

# Both steps run in order every time; a sweep failure wins over the audit's status.
for case in "0 0 0" "1 0 1" "0 3 3" "1 3 1"; do
  read -r sweep audit expected <<<"$case"
  cat > "$work/dibs" <<EOF
#!/bin/sh
case "\$1" in
  sweep) echo "sweep \$*"; exit $sweep ;;
  orphans) echo "audit \$*"; exit $audit ;;
esac
exit 99
EOF
  chmod +x "$work/dibs"
  set +e
  /bin/sh -c "$script" > "$work/out" 2>&1
  status=$?
  set -e
  [[ $status == "$expected" ]] || fail "sweep=$sweep audit=$audit exited $status, expected $expected"
  mapfile -t lines < "$work/out"
  [[ ${#lines[@]} == 3 && ${lines[0]} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]] \
    || fail "sweep=$sweep audit=$audit: expected timestamp, sweep, audit lines: ${lines[*]}"
  [[ ${lines[1]} == "sweep sweep --confirm --json" && ${lines[2]} == "audit orphans --adopt --ttl 30m --json" ]] \
    || fail "sweep=$sweep audit=$audit: wrong commands or order: ${lines[*]}"
done
echo "dibs sweep job checks passed"
