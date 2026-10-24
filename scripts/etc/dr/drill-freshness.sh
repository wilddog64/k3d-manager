#!/usr/bin/env bash
set -euo pipefail

results_dir="${1:?usage: drill-freshness.sh results-dir}"
freshness_seconds=$((8 * 86400))
now_epoch="${DR_FRESHNESS_NOW_EPOCH:-$(date -u +%s)}"
latest=""
latest_stamp=""
latest_epoch=-1

report_error() {
  local title="$1" message="$2"
  printf '::error title=%s::%s\n' "$title" "$message" >&2
  printf '%s\n' "$message" >&2
}

while IFS= read -r -d '' candidate; do
  stamp="$(jq -er '.run_timestamp | strings' "$candidate" 2>/dev/null || true)"
  [[ -n "$stamp" ]] || continue
  epoch="$(python3 -c 'import datetime,sys
try:
 print(int(datetime.datetime.strptime(sys.argv[1], "%Y%m%dT%H%M%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()))
except (IndexError, ValueError):
 raise SystemExit(1)' "$stamp" 2>/dev/null || true)"
  if [[ "$epoch" =~ ^[0-9]+$ && "$epoch" -gt "$latest_epoch" ]] && jq -e '.success | type == "boolean"' "$candidate" >/dev/null 2>&1; then
    latest="$candidate"
    latest_stamp="$stamp"
    latest_epoch="$epoch"
  fi
done < <(find "$results_dir" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)

if [[ -z "$latest" ]]; then
  report_error "DR drill freshness: no valid results" "No readable valid DR drill result was found. Run make dr-drill on M2, then make dr-drill-publish on M4."
  exit 1
fi

if ! jq -e '.success == true' "$latest" >/dev/null; then
  report_error "DR drill freshness: latest drill failed" "Latest DR drill result ($latest_stamp) reports success=false. Run make dr-drill on M2, then make dr-drill-publish on M4 after a successful drill."
  exit 1
fi

age=$((now_epoch - latest_epoch))
if (( age <= freshness_seconds )); then
  exit 0
fi
if (( age > freshness_seconds )); then
  age_days=$((age / 86400))
  age_hours=$(((age % 86400) / 3600))
  cutoff_epoch=$((now_epoch - freshness_seconds))
  cutoff="$(date -u -d "@$cutoff_epoch" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -r "$cutoff_epoch" '+%Y-%m-%dT%H:%M:%SZ')"
  message="Latest successful DR drill result ($latest_stamp) is stale: age ${age_days}d ${age_hours}h exceeds the 8-day threshold; cutoff was $cutoff. This is stale evidence, not a failed recovery drill. Run make dr-drill on M2, then make dr-drill-publish on M4."
  report_error "DR drill freshness: successful result is stale" "$message"
  exit 1
fi
