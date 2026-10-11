#!/usr/bin/env bash
set -euo pipefail
results_dir="${1:?usage: drill-freshness.sh results-dir}"
latest=""
latest_epoch=-1
while IFS= read -r candidate; do
  stamp="$(jq -r .run_timestamp "$candidate" 2>/dev/null || true)"
  epoch="$(python3 -c 'import datetime,sys
try:
 print(int(datetime.datetime.strptime(sys.argv[1], "%Y%m%dT%H%M%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()))
except (IndexError, ValueError):
 raise SystemExit(1)' "$stamp" 2>/dev/null || true)"
  if [[ "$epoch" =~ ^[0-9]+$ && "$epoch" -gt "$latest_epoch" ]]; then
    latest="$candidate"
    latest_epoch="$epoch"
  fi
done < <(find "$results_dir" -maxdepth 1 -type f -name '*.json' -print)
[[ -n "$latest" ]] || exit 1
jq -e '.success == true' "$latest" >/dev/null || exit 1
age="$(( $(date -u +%s) - latest_epoch ))"
(( age <= 8 * 86400 ))
