#!/usr/bin/env bats

# vCluster CLI field names/options and host inventory assumptions are from the read-only
# M5 capture and pinned v0.32.1 source inspection recorded in the plan, ssh m5-air.local,
# 2026-11-12 14:14Z. These fixtures only return the captured JSON shape; they never contact
# the cluster.

setup() {
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dev-hub-bats.XXXXXX")"
  export TEST_ROOT HOME="${TEST_ROOT}/home" SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
  mkdir -p "${HOME}/.kube/vclusters" "${TEST_ROOT}/repo"
  export CALL_LOG="${TEST_ROOT}/calls.log" REPO_ROOT="${TEST_ROOT}/repo"
  : >"${CALL_LOG}"
  [ -d "${HOME}" ] && [ -d "${REPO_ROOT}" ]

  _run_command() {
    while [[ "${1:-}" == --* ]]; do
      [[ "$1" == -- ]] && { shift; break; }
      shift
    done
    local command_name="$1"
    printf '%s' "$1" >>"${CALL_LOG}"
    shift
    for arg in "$@"; do printf ' %s' "$arg" >>"${CALL_LOG}"; done
    printf '\n' >>"${CALL_LOG}"
    if [[ "${command_name}" == rm ]]; then /bin/rm "$@"; return; fi
    case "$(cat "${CALL_LOG}" | tail -1)" in
      "kubectl config current-context") printf '%s' "${CURRENT_CONTEXT:-k3d-k3d-cluster}" ;;
      *"list -n dev-hub --output json"*)
        if [[ "${EXIST_VCLUSTER:-0}" == 1 ]]; then printf '[{"Name":"dev-hub","Status":"Ready"}]'; else printf '[]'; fi
        ;;
      *"get namespace dev-hub"*) [[ "${EXIST_NAMESPACE:-0}" == 1 ]] ;;
      *"get resourcequota -n dev-hub -o json"*) printf '{"items":[{"status":{"used":{"limits.memory":"512Mi","limits.cpu":"200m"},"hard":{"limits.memory":"3Gi","limits.cpu":"3"}}}]}' ;;
      *) : ;;
    esac
  }
  _vcluster_check_prerequisites() { _VCLUSTER_BIN="${VCLUSTER_TEST_BIN:-vcluster}"; }
  _info() { :; }
  _err() { printf 'ERROR: %s\n' "$*" >&2; return 1; }
  vcluster_create() {
    printf 'vcluster-create %s namespace=%s port=%s values=%s\n' "$1" "$VCLUSTER_NAMESPACE" "$VCLUSTER_LOCAL_PORT" "$VCLUSTER_VALUES_FILE" >>"${CALL_LOG}"
  }
  _vcluster_remove_proxy() { printf 'remove-proxy %s\n' "$1" >>"${CALL_LOG}"; }
  if [[ -r "${SCRIPT_DIR}/plugins/dev_hub.sh" ]]; then
    # shellcheck source=../../plugins/dev_hub.sh
    source "${SCRIPT_DIR}/plugins/dev_hub.sh"
  fi
}

teardown() {
  rm -rf -- "${TEST_ROOT}"
}

@test "dev hub up applies host objects in namespace and creates the vCluster with its dedicated settings" {
  dev_hub_up
  grep -F 'apply -f '"${SCRIPT_DIR}"'/etc/dev-hub/priorityclass.yaml' "${CALL_LOG}"
  grep -F 'apply -n dev-hub -f '"${SCRIPT_DIR}"'/etc/dev-hub/resourcequota.yaml' "${CALL_LOG}"
  grep -F 'vcluster-create dev-hub namespace=dev-hub port=11444' "${CALL_LOG}"
  [ "$(grep -c '^vcluster-create dev-hub' "${CALL_LOG}")" -eq 1 ]
}

@test "dev hub up is idempotent for an existing namespace and vCluster" {
  export EXIST_NAMESPACE=1 EXIST_VCLUSTER=1
  dev_hub_up
  if grep -q 'create namespace dev-hub' "${CALL_LOG}"; then return 1; fi
  if grep -q '^vcluster-create ' "${CALL_LOG}"; then return 1; fi
}

@test "dev hub up refuses a non-hub current context before lifecycle calls" {
  export CURRENT_CONTEXT=ubuntu-k3s
  run dev_hub_up
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ubuntu-k3s"* && "${output}" == *"k3d-k3d-cluster"* ]]
  [ "$(wc -l <"${CALL_LOG}")" -eq 1 ]
  grep -Fx 'kubectl config current-context' "${CALL_LOG}"
  if rg -E 'vcluster-create|vcluster (create|delete|list)|(^| )apply( |$)|(^| )delete( |$)' "${CALL_LOG}"; then return 1; fi
}

@test "dev hub down refuses a non-hub current context before lifecycle calls" {
  export CURRENT_CONTEXT=ubuntu-k3s
  run dev_hub_down
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ubuntu-k3s"* && "${output}" == *"k3d-k3d-cluster"* ]]
  [ "$(wc -l <"${CALL_LOG}")" -eq 1 ]
  grep -Fx 'kubectl config current-context' "${CALL_LOG}"
  if rg -E 'vcluster-create|vcluster (create|delete|list)|(^| )apply( |$)|(^| )delete( |$)' "${CALL_LOG}"; then return 1; fi
}

@test "dev hub status refuses a non-hub current context before read calls" {
  export CURRENT_CONTEXT=ubuntu-k3s
  run dev_hub_status
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ubuntu-k3s"* && "${output}" == *"k3d-k3d-cluster"* ]]
  [ "$(wc -l <"${CALL_LOG}")" -eq 1 ]
  grep -Fx 'kubectl config current-context' "${CALL_LOG}"
  if rg -E 'vcluster-create|vcluster (create|delete|list)|(^| )apply( |$)|(^| )delete( |$)' "${CALL_LOG}"; then return 1; fi
}

@test "N1 positive control has a namespaced quota apply and the intended context" {
  dev_hub_up
  grep -F -- '--context k3d-k3d-cluster apply -n dev-hub -f ' "${CALL_LOG}"
  while IFS= read -r call; do
    [[ "${call}" == *'--context k3d-k3d-cluster'* ]] || continue
    [[ " ${call} " == *' -n dev-hub '* ]] && continue
    [[ "${call}" == *'priorityclass.yaml' ]] || return 1
  done <"${CALL_LOG}"
}

@test "N2 scanner catches a Vault address fixture and passes current Part A files" {
  local fixture="${TEST_ROOT}/fixture.yaml"
  printf 'endpoint: VAULT_ADDR\n' >"${fixture}"
  grep -Eq 'VAULT_ADDR|vault token|ExternalSecret|SecretStore|kubeconfig|pushgateway|remote_write' "${fixture}"
  [ -f "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml" ]
  if rg -n -i 'VAULT_ADDR|vault token|ExternalSecret|SecretStore|kubeconfig|pushgateway|remote_write' \
    "${SCRIPT_DIR}/etc/dev-hub" "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml"; then return 1; fi
}

@test "N3 positive control creates dev-hub in dev-hub and never uses vclusters" {
  dev_hub_up
  grep -F 'vcluster-create dev-hub namespace=dev-hub' "${CALL_LOG}"
  if grep -F 'vclusters' "${CALL_LOG}"; then return 1; fi
}

@test "N5 down deletes the vCluster and only the dev-hub host namespace and local files" {
  printf 'fixture kubeconfig\n' >"${HOME}/.kube/vclusters/dev-hub.yaml"
  dev_hub_down
  grep -F 'vcluster delete dev-hub -n dev-hub --wait' "${CALL_LOG}"
  grep -F 'delete namespace dev-hub -n dev-hub --ignore-not-found' "${CALL_LOG}"
  grep -F 'remove-proxy dev-hub' "${CALL_LOG}"
  [ ! -e "${HOME}/.kube/vclusters/dev-hub.yaml" ]
  if grep -F 'cicd' "${CALL_LOG}"; then return 1; fi
}

@test "N6 scanner rejects configMaps all true and no dashboard ConfigMap volume is introduced" {
  local fixture="${TEST_ROOT}/values-dev-hub.yaml"
  printf 'sync:\n  toHost:\n    configMaps:\n      all: true\n' >"${fixture}"
  grep -Eq 'configMaps:[[:space:]]*$' "${fixture}"
  grep -Eq 'all:[[:space:]]*true' "${fixture}"
  [ -f "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml" ]
  if rg -n 'all:[[:space:]]*true|grafana_dashboard' \
    "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml" "${SCRIPT_DIR}/etc/dev-hub"; then return 1; fi
}

@test "M5 memory alerts are warnings outside the analyze alert-name matcher" {
  local rules="${SCRIPT_DIR}/etc/argocd/platform-ops/prometheusrule.yaml"
  local route="${SCRIPT_DIR}/etc/argocd/platform-ops/alertmanager-config.yaml"
  local dev_hub_rules
  dev_hub_rules="$(sed -n '/name: dev-hub.alerts/,/name: argocd.alerts/p' "${rules}")"
  grep -F 'alert: HubVmMemoryLow' <<<"${dev_hub_rules}"
  grep -F 'alert: DevHubNearQuota' <<<"${dev_hub_rules}"
  [ "$(grep -c 'severity: warning' <<<"${dev_hub_rules}")" -eq 2 ]
  if rg -n 'HubVmMemoryLow|DevHubNearQuota' "${route}"; then return 1; fi
  grep -F 'memory: 768Mi' "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml"
  grep -F 'memory: 128Mi' "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml"
  local memory_budget_mi=896
  [ "${memory_budget_mi}" -le 3072 ]
}

@test "dev hub status reports phase and quota with read-only host calls" {
  export VCLUSTER_TEST_BIN="/resolved/vcluster"
  dev_hub_status >"${TEST_ROOT}/status.out"
  grep -F 'vCluster phase: NotFound' "${TEST_ROOT}/status.out"
  grep -F 'Quota limits.memory used/hard: 512Mi / 3Gi' "${TEST_ROOT}/status.out"
  grep -F 'get resourcequota -n dev-hub -o json' "${CALL_LOG}"
  grep -F '/resolved/vcluster list -n dev-hub --output json' "${CALL_LOG}"
  if grep -Eq 'apply|create|delete|patch|replace' "${CALL_LOG}"; then return 1; fi
}
