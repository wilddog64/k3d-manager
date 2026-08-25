#!/usr/bin/env bash
# scripts/plugins/loadtest.sh

set -euo pipefail

LOADTEST_STAGES="${LOADTEST_STAGES:-100 250 500 1000 2500 5000}"
LOADTEST_MAX_ERROR_RATE="${LOADTEST_MAX_ERROR_RATE:-2}"
LOADTEST_MAX_P95_SECONDS="${LOADTEST_MAX_P95_SECONDS:-2}"
LOADTEST_MAX_CPU_PCT="${LOADTEST_MAX_CPU_PCT:-80}"
LOADTEST_BREACH_INTERVALS="${LOADTEST_BREACH_INTERVALS:-2}"

function _loadtest_is_greater() {
  local value="${1:?value required}"
  local threshold="${2:?threshold required}"
  awk -v value="${value}" -v threshold="${threshold}" 'BEGIN { exit !(value > threshold) }'
}

function _loadtest_evaluate_gates() {
  # Positional snapshot: error_rate p95_seconds cpu_pct, then five 0/1 flags.
  local error_rate="${1:?error rate required}"
  local p95_seconds="${2:?p95 seconds required}"
  local cpu_pct="${3:?cpu percentage required}"
  local stripe_rate_limited="${4:?stripe rate-limit flag required}"
  local db_pool_exhausted="${5:?db pool flag required}"
  local control_plane_error="${6:?control-plane flag required}"
  local node_eviction_risk="${7:?node eviction flag required}"
  local memory_pressure="${8:?memory pressure flag required}"
  local breaches=()

  if _loadtest_is_greater "${error_rate}" "${LOADTEST_MAX_ERROR_RATE}"; then
    breaches+=(error_rate)
  fi
  if _loadtest_is_greater "${p95_seconds}" "${LOADTEST_MAX_P95_SECONDS}"; then
    breaches+=(p95_seconds)
  fi
  if _loadtest_is_greater "${cpu_pct}" "${LOADTEST_MAX_CPU_PCT}"; then
    breaches+=(cpu_pct)
  fi
  [[ "${stripe_rate_limited}" == "1" ]] && breaches+=(stripe_rate_limited)
  [[ "${db_pool_exhausted}" == "1" ]] && breaches+=(db_pool_exhausted)
  [[ "${control_plane_error}" == "1" ]] && breaches+=(control_plane_error)
  [[ "${node_eviction_risk}" == "1" ]] && breaches+=(node_eviction_risk)
  [[ "${memory_pressure}" == "1" ]] && breaches+=(memory_pressure)

  ((${#breaches[@]} == 0)) || printf '%s\n' "${breaches[*]}"
  return 0
}

function _loadtest_decide() {
  local stage_index="${1:?stage index required}"
  local breach_list="${2:-}"
  local consecutive_breach_count="${3:?consecutive breach count required}"
  local next_count=0
  local decision

  if [[ -z "${breach_list}" ]]; then
    decision=increase
  else
    next_count=$((consecutive_breach_count + 1))
    if ((next_count >= LOADTEST_BREACH_INTERVALS)); then
      decision=stop
    else
      decision=hold
    fi
  fi

  local stage_count
  local stage_values=()
  read -r -a stage_values <<< "${LOADTEST_STAGES}"
  stage_count="${#stage_values[@]}"
  if [[ "${decision}" == "increase" && "${stage_index}" -ge $((stage_count - 1)) ]]; then
    decision=hold
  fi
  printf '%s\n%s\n' "${decision}" "${next_count}"
}

function _loadtest_next_stage() {
  local current_index="${1:?stage index required}"
  local stages=()
  read -r -a stages <<< "${LOADTEST_STAGES}"
  local last_index
  last_index=$((${#stages[@]} - 1))
  local next_index=$((current_index + 1))

  if ((next_index > last_index)); then
    next_index="${last_index}"
  fi
  printf '%s\n' "${stages[${next_index}]}"
}

function _loadtest_write_stage_summary() {
  local run_id="${1:?run id required}"
  local stage="${2:?stage required}"
  local target_concurrency="${3:?target concurrency required}"
  local actual_throughput="${4:?actual throughput required}"
  local decision="${5:?decision required}"
  local breach_list="${6:-}"
  local output_path="${7:?output path required}"
  local breach_json

  if [[ -e "${output_path}" ]]; then
    _err "[loadtest] refusing to overwrite immutable stage summary: ${output_path}"
    return 1
  fi
  breach_json=$(printf '%s\n' "${breach_list}" | tr ' ' '\n' | jq -R -s 'split("\n") | map(select(length > 0))')
  jq -n \
    --arg run_id "${run_id}" \
    --arg stage "${stage}" \
    --argjson target_concurrency "${target_concurrency}" \
    --argjson actual_throughput "${actual_throughput}" \
    --arg decision "${decision}" \
    --argjson breaches "${breach_json}" \
    '{run_id: $run_id, stage: $stage, target_concurrency: $target_concurrency,
      actual_throughput: $actual_throughput, decision: $decision, breaches: $breaches}' \
    > "${output_path}"
}

function _loadtest_fetch_metrics() {
  _err "[loadtest] metric fetcher is not wired in this slice"
  return 1
}

function loadtest_run() {
  local confirmed=0
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --confirm) confirmed=1 ;;
      *)
        _err "[loadtest] unknown option: ${arg}"
        return 2
        ;;
    esac
  done
  if [[ "${LOADTEST_CONFIRM:-}" == "1" ]]; then
    confirmed=1
  fi
  if ((confirmed == 0)); then
    _err "[loadtest] refusing to run without --confirm or LOADTEST_CONFIRM=1"
    return 1
  fi

  LOADTEST_RUN_ID="${LOADTEST_RUN_ID:-loadtest-$(date -u +%Y%m%dT%H%M%SZ)}"
  _info "[loadtest] initialized ${LOADTEST_RUN_ID}; live generator and metric poller are not wired (Slice F)"
}

function loadtest_status() {
  printf 'stages=%s\nmax_error_rate=%s\nmax_p95_seconds=%s\nmax_cpu_pct=%s\nbreach_intervals=%s\n' \
    "${LOADTEST_STAGES}" "${LOADTEST_MAX_ERROR_RATE}" "${LOADTEST_MAX_P95_SECONDS}" \
    "${LOADTEST_MAX_CPU_PCT}" "${LOADTEST_BREACH_INTERVALS}"
}
