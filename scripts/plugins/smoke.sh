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
    fi
  done < <(_smoke_records)
  printf 'smoke: %d passed, %d failed, %d skipped\n' "$_passed" "$_failed" "$_skipped"
  [[ "$_failed" -eq 0 ]]
}
