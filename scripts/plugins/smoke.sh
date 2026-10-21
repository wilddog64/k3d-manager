#!/usr/bin/env bash

set -euo pipefail

SMOKE_INFRA_CONTEXT="${SMOKE_INFRA_CONTEXT:-${INFRA_CONTEXT:-k3d-k3d-cluster}}"
SMOKE_BIN_DIR="${SMOKE_BIN_DIR:-${SCRIPT_DIR}/../bin}"

function _smoke_records() {
  cat <<'EOF'
offline|webhook|bin/smoke-test-webhook
cluster|cluster-health|bin/smoke-test-cluster-health
EOF
}

function _smoke_context_reachable() {
  local _ctx="$1"
  _kubectl --context "$_ctx" --request-timeout=10s get --raw='/readyz' >/dev/null 2>&1
}

function _smoke_run_dir() {
  local _root="${SMOKE_LOG_ROOT:-${TMPDIR:-/tmp}/k3dm-smoke}"
  local _stamp
  local _dir
  _stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  _dir="${_root}/${_stamp}"
  _run_command -- mkdir -p "$_dir"
  printf '%s\n' "$_dir"
}

function _smoke_execute() {
  local _script="$1" _log="$2"
  _run_command -- "${SMOKE_BIN_DIR}/${_script#bin/}" >"$_log" 2>&1
}

function _smoke_failure_excerpt() {
  local _log="$1" _line _count=0 _shown=0
  if [[ ! -f "$_log" || ! -r "$_log" ]]; then
    printf '  diagnostics_unavailable: cluster-health log is missing or unreadable. Check the smoke job transcript with /k3dm logs <job-id>.\n'
    return
  fi
  _count="$(grep -cE '^[[:space:]]*\[FAIL\]' "$_log" 2>/dev/null || true)"
  if [[ "$_count" -eq 0 ]]; then
    printf '  diagnostics_unavailable: no [FAIL] details found in cluster-health log. Check /k3dm logs <job-id> for the full smoke transcript.\n'
    return
  fi
  printf '  smoke_check_failed: %s cluster-health failure(s)\n' "$_count"
  while IFS= read -r _line; do
    [[ "$_line" == *'[FAIL]'* ]] || continue
    _line="$(printf '%s' "$_line" | LC_ALL=C tr -cd '\11\12\15\40-\176' | sed -E 's/(token|password|secret|api[_-]?key|authorization)([[:space:]]*[:=][[:space:]]*|[[:space:]]+)[^[:space:]]+/\1=[REDACTED]/Ig; s/(Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/Ig')"
    printf '  %s\n' "${_line:0:240}"
    _shown=$((_shown + 1))
    [[ "$_shown" -ge 5 ]] && break
  done < "$_log"
  if [[ "$_count" -gt "$_shown" ]]; then
    printf '  ... %s additional failure(s) omitted. Retrieve details with /k3dm logs <job-id>.\n' "$((_count - _shown))"
  else
    printf '  Next: retrieve the full bounded job transcript with /k3dm logs <job-id>.\n'
  fi
}

function smoke_run() {
  local _filter="${1:-}"
  local _run_dir _tier _name _script _log _status _reason _check_rc
  local _passed=0 _failed=0 _skipped=0

  if [[ "$#" -gt 1 || ( -n "$_filter" && "$_filter" != "offline" && "$_filter" != "cluster" ) ]]; then
    printf 'Usage: smoke_run [offline|cluster]\n' >&2
    return 2
  fi

  _run_dir="$(_smoke_run_dir)"
  printf '%-15s %-9s %s\n' "check" "tier" "status"
  while IFS='|' read -r _tier _name _script; do
    [[ -z "$_tier" ]] && continue
    [[ -n "$_filter" && "$_filter" != "$_tier" ]] && continue
    _log="${_run_dir}/${_name}.log"
    _reason=""
    if [[ "$_tier" == "cluster" ]] && ! _smoke_context_reachable "$SMOKE_INFRA_CONTEXT"; then
      _status="SKIP"
      _reason="(context ${SMOKE_INFRA_CONTEXT} unreachable)"
      _skipped=$((_skipped + 1))
    else
      if (set +e; _smoke_execute "$_script" "$_log"); then
        _status="PASS"
        _passed=$((_passed + 1))
      else
        _status="FAIL"
        _failed=$((_failed + 1))
      fi
    fi
    printf '%-15s %-9s %s %s\n' "$_name" "$_tier" "$_status" "$_reason"
    if [[ "$_status" != "PASS" ]]; then
      printf '  log: %s\n' "$_log"
      if [[ "$_name" == "cluster-health" && "$_status" == "FAIL" ]]; then
        _smoke_failure_excerpt "$_log"
      elif [[ "$_name" == "cluster-health" && "$_status" == "SKIP" ]]; then
        printf '  environment_unavailable: infra context is unreachable; retry after restoring cluster access.\n'
      fi
    fi
  done < <(_smoke_records)
  printf 'smoke: %d passed, %d failed, %d skipped\n' "$_passed" "$_failed" "$_skipped"
  [[ "$_failed" -eq 0 ]]
}
