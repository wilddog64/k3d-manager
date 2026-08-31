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

# --- Slice F: auth, generator, and metric wiring ------------------------------

LOADTEST_KEYCLOAK_ISSUER="${LOADTEST_KEYCLOAK_ISSUER:-https://keycloak.3ai-talk.org/realms/shopping-cart}"
LOADTEST_CLIENT_ID="${LOADTEST_CLIENT_ID:-order-service}"
LOADTEST_TARGET_URL="${LOADTEST_TARGET_URL:-http://localhost:18081}"
LOADTEST_PROM_URL="${LOADTEST_PROM_URL:-http://localhost:19090}"
LOADTEST_STAGE_DURATION="${LOADTEST_STAGE_DURATION:-60s}"
LOADTEST_POLL_INTERVAL="${LOADTEST_POLL_INTERVAL:-15}"
LOADTEST_K6_SCRIPT="${LOADTEST_K6_SCRIPT:-${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/etc/loadtest/checkout.js}"
LOADTEST_RESULT_DIR="${LOADTEST_RESULT_DIR:-${TMPDIR:-/tmp}/k3dm-loadtest}"

# Metric names remote-written by k6 carry the k6_ prefix; PromQL below matches that.
LOADTEST_PROMQL_ERROR_RATE="${LOADTEST_PROMQL_ERROR_RATE:-100 * (sum(rate(k6_checkout_load_requests_total{result=\"error\"}[1m])) / clamp_min(sum(rate(k6_checkout_load_requests_total[1m])), 1))}"
LOADTEST_PROMQL_P95="${LOADTEST_PROMQL_P95:-histogram_quantile(0.95, sum(rate(k6_checkout_load_latency_seconds_bucket[1m])) by (le))}"
LOADTEST_PROMQL_CPU="${LOADTEST_PROMQL_CPU:-100 * max(sum(rate(container_cpu_usage_seconds_total{namespace=\"shopping-cart-apps\"}[1m])) / sum(kube_pod_container_resource_limits{namespace=\"shopping-cart-apps\",resource=\"cpu\"}))}"
LOADTEST_PROMQL_STRIPE_RL="${LOADTEST_PROMQL_STRIPE_RL:-sum(increase(payment_stripe_rate_limited_total[1m]))}"
LOADTEST_PROMQL_DB_POOL="${LOADTEST_PROMQL_DB_POOL:-max(hikaricp_connections_pending{namespace=\"shopping-cart-apps\"})}"
LOADTEST_PROMQL_CONTROL_PLANE="${LOADTEST_PROMQL_CONTROL_PLANE:-sum(increase(apiserver_request_total{code=~\"5..\"}[1m]))}"
LOADTEST_PROMQL_EVICTION="${LOADTEST_PROMQL_EVICTION:-sum(kube_node_status_condition{condition=~\"DiskPressure|PIDPressure\",status=\"true\"})}"
LOADTEST_PROMQL_MEMORY="${LOADTEST_PROMQL_MEMORY:-sum(kube_node_status_condition{condition=\"MemoryPressure\",status=\"true\"})}"

# Pure: build the OIDC token endpoint from an issuer URL.
function _loadtest_token_endpoint() {
  local issuer="${1:?issuer required}"
  printf '%s/protocol/openid-connect/token\n' "${issuer%/}"
}

# Thin wrapper around the k6 binary so BATS can stub it.
function _loadtest_k6_bin() {
  command k6 "$@"
}

# Thin wrapper around curl so BATS can stub network calls.
function _loadtest_curl() {
  command curl "$@"
}

# Mint an OAuth2 access token via the Keycloak password grant. Secrets are read
# from env (LOADTEST_CLIENT_SECRET / LOADTEST_USERNAME / LOADTEST_PASSWORD) and
# passed to curl via a 0600 config file so they never appear in argv or `ps`.
function _loadtest_mint_token() {
  local issuer="${LOADTEST_KEYCLOAK_ISSUER}" client_id="${LOADTEST_CLIENT_ID}"
  local secret="${LOADTEST_CLIENT_SECRET:-}" user="${LOADTEST_USERNAME:-}" pass="${LOADTEST_PASSWORD:-}"
  if [[ -z "${user}" || -z "${pass}" ]]; then
    _err "[loadtest] mint token needs LOADTEST_USERNAME and LOADTEST_PASSWORD (LOADTEST_CLIENT_SECRET only for a confidential client)"
    return 1
  fi
  local endpoint cfg raw token
  endpoint=$(_loadtest_token_endpoint "${issuer}")
  cfg=$(mktemp "${TMPDIR:-/tmp}/k3dm-loadtest-tok.XXXXXX") || return 1
  chmod 600 "${cfg}"
  {
    printf 'data-urlencode = "grant_type=password"\n'
    printf 'data-urlencode = "client_id=%s"\n' "${client_id}"
    [[ -n "${secret}" ]] && printf 'data-urlencode = "client_secret=%s"\n' "${secret}"
    printf 'data-urlencode = "username=%s"\n' "${user}"
    printf 'data-urlencode = "password=%s"\n' "${pass}"
  } > "${cfg}"
  raw=$(_loadtest_curl -sf --config "${cfg}" "${endpoint}" 2>/dev/null)
  local rc=$?
  rm -f "${cfg}" 2>/dev/null || true
  if ((rc != 0)); then
    _err "[loadtest] token mint failed against ${endpoint} (client_id=${client_id})"
    return 1
  fi
  token=$(printf '%s' "${raw}" | jq -r '.access_token // empty')
  if [[ -z "${token}" ]]; then
    _err "[loadtest] token endpoint returned no access_token"
    return 1
  fi
  printf '%s\n' "${token}"
}

# Query Prometheus for a single instant scalar; empty result -> 0.
function _loadtest_prom_query() {
  local query="${1:?query required}" raw value
  raw=$(_loadtest_curl -sf -G "${LOADTEST_PROM_URL}/api/v1/query" \
    --data-urlencode "query=${query}" 2>/dev/null) || { printf '0\n'; return 0; }
  value=$(printf '%s' "${raw}" | jq -r '.data.result[0].value[1] // empty' 2>/dev/null)
  if [[ -z "${value}" || "${value}" == "null" || "${value}" == "NaN" ]]; then
    printf '0\n'
  else
    printf '%s\n' "${value}"
  fi
}

# Emit "> 0 -> 1, else 0" for the boolean saturation flags.
function _loadtest_prom_flag() {
  local query="${1:?query required}" value
  value=$(_loadtest_prom_query "${query}")
  if _loadtest_is_greater "${value}" "0"; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

# Produce the 8-positional snapshot that _loadtest_evaluate_gates consumes:
#   error_rate p95_seconds cpu_pct stripe db_pool control_plane eviction memory
function _loadtest_fetch_metrics() {
  local error_rate p95 cpu stripe db_pool control_plane eviction memory
  error_rate=$(_loadtest_prom_query "${LOADTEST_PROMQL_ERROR_RATE}")
  p95=$(_loadtest_prom_query "${LOADTEST_PROMQL_P95}")
  cpu=$(_loadtest_prom_query "${LOADTEST_PROMQL_CPU}")
  stripe=$(_loadtest_prom_flag "${LOADTEST_PROMQL_STRIPE_RL}")
  db_pool=$(_loadtest_prom_flag "${LOADTEST_PROMQL_DB_POOL}")
  control_plane=$(_loadtest_prom_flag "${LOADTEST_PROMQL_CONTROL_PLANE}")
  eviction=$(_loadtest_prom_flag "${LOADTEST_PROMQL_EVICTION}")
  memory=$(_loadtest_prom_flag "${LOADTEST_PROMQL_MEMORY}")
  printf '%s %s %s %s %s %s %s %s\n' \
    "${error_rate}" "${p95}" "${cpu}" "${stripe}" "${db_pool}" \
    "${control_plane}" "${eviction}" "${memory}"
}

# Launch k6 for a single stage at the given concurrency. Returns k6's exit code.
function _loadtest_k6_stage() {
  local stage="${1:?stage required}" vus="${2:?vus required}" duration="${3:?duration required}"
  local token="${4:-${LOADTEST_TOKEN:-}}"
  LOADTEST_RUN_ID="${LOADTEST_RUN_ID}" \
  LOADTEST_STAGE="${stage}" \
  LOADTEST_VUS="${vus}" \
  LOADTEST_DURATION="${duration}" \
  LOADTEST_TARGET_URL="${LOADTEST_TARGET_URL}" \
  LOADTEST_TOKEN="${token}" \
  LOADTEST_POLL_ORDER="${LOADTEST_POLL_ORDER:-0}" \
    _loadtest_k6_bin run \
      ${LOADTEST_K6_OUT:+--out "${LOADTEST_K6_OUT}"} \
      "${LOADTEST_K6_SCRIPT}"
}

function loadtest_run() {
  local confirmed=0
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --confirm) confirmed=1 ;;
      --dry-run) LOADTEST_DRY_RUN=1 ;;
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
  local dry="${LOADTEST_DRY_RUN:-0}"
  local run_dir="${LOADTEST_RESULT_DIR}/${LOADTEST_RUN_ID}"
  mkdir -p "${run_dir}"

  local stages=()
  read -r -a stages <<< "${LOADTEST_STAGES}"
  local stage_count="${#stages[@]}"
  _info "[loadtest] ${LOADTEST_RUN_ID}: ${stage_count} stage(s), results in ${run_dir} (dry_run=${dry})"

  local idx breach_count=0 target token="${LOADTEST_TOKEN:-}"
  for ((idx = 0; idx < stage_count; idx++)); do
    target="${stages[idx]}"

    if [[ "${dry}" != "1" ]]; then
      token=$(_loadtest_mint_token) || { _err "[loadtest] aborting: token mint failed at stage ${target}"; return 1; }
      _loadtest_k6_stage "${target}" "${target}" "${LOADTEST_STAGE_DURATION}" "${token}" \
        || _info "[loadtest] k6 stage ${target} exited non-zero (client-side); trusting Prometheus gates"
    fi

    local snapshot breaches
    if [[ "${dry}" == "1" ]]; then
      snapshot="${LOADTEST_DRY_METRICS:-0 0 0 0 0 0 0 0}"
    else
      snapshot=$(_loadtest_fetch_metrics)
    fi
    # shellcheck disable=SC2086
    breaches=$(_loadtest_evaluate_gates ${snapshot})

    local decision_out decision next_count
    decision_out=$(_loadtest_decide "${idx}" "${breaches}" "${breach_count}")
    decision=$(printf '%s\n' "${decision_out}" | sed -n '1p')
    next_count=$(printf '%s\n' "${decision_out}" | sed -n '2p')
    breach_count="${next_count}"

    _loadtest_write_stage_summary "${LOADTEST_RUN_ID}" "${target}" "${target}" 0 \
      "${decision}" "${breaches}" "${run_dir}/stage-${idx}-${target}.json"
    _info "[loadtest] stage ${target}: decision=${decision} breaches=[${breaches}]"

    if [[ "${decision}" == "stop" ]]; then
      _info "[loadtest] stop condition reached at stage ${target}; ending run"
      break
    fi
  done

  _info "[loadtest] ${LOADTEST_RUN_ID} complete; per-stage summaries under ${run_dir}"
}

function loadtest_status() {
  printf 'stages=%s\nmax_error_rate=%s\nmax_p95_seconds=%s\nmax_cpu_pct=%s\nbreach_intervals=%s\nissuer=%s\nclient_id=%s\ntarget_url=%s\nprom_url=%s\nk6_script=%s\n' \
    "${LOADTEST_STAGES}" "${LOADTEST_MAX_ERROR_RATE}" "${LOADTEST_MAX_P95_SECONDS}" \
    "${LOADTEST_MAX_CPU_PCT}" "${LOADTEST_BREACH_INTERVALS}" \
    "${LOADTEST_KEYCLOAK_ISSUER}" "${LOADTEST_CLIENT_ID}" "${LOADTEST_TARGET_URL}" \
    "${LOADTEST_PROM_URL}" "${LOADTEST_K6_SCRIPT}"
}
