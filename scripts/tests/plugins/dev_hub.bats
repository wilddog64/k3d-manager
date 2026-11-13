#!/usr/bin/env bats

# vCluster CLI field names/options and host inventory assumptions are from the read-only
# M5 capture and pinned v0.32.1 source inspection recorded in the plan, ssh m5-air.local,
# 2026-11-12 14:14Z. These fixtures only return the captured JSON shape; they never contact
# the cluster.
# ArgoCD/Grafana chart pins, hub Service name, and PriorityClass translation are from that
# same capture. Sync tests use a scratch clone and local bare origin; passwords are fixture values.
# No live credential, GitHub request, Keychain, or cluster state is read by this suite.

setup() {
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dev-hub-bats.XXXXXX")"
  export TEST_ROOT HOME="${TEST_ROOT}/home" SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
  SOURCE_SCRIPTS_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export SOURCE_SCRIPTS_DIR
  mkdir -p "${HOME}/.kube/vclusters" "${TEST_ROOT}/repo"
  export CALL_LOG="${TEST_ROOT}/calls.log" REPO_ROOT="${TEST_ROOT}/repo"
  export APPLY_LOG="${TEST_ROOT}/applied-files.log" TEMP_PATH_LOG="${TEST_ROOT}/temp-paths.log"
  export WRAPPER_LOG="${TEST_ROOT}/wrapper-flags.log"
  : >"${CALL_LOG}" "${APPLY_LOG}" "${TEMP_PATH_LOG}" "${WRAPPER_LOG}"
  [ -d "${HOME}" ] && [ -d "${REPO_ROOT}" ]

  _run_command() {
    local soft=0 quiet=0
    while [[ "${1:-}" == --* ]]; do
      case "$1" in
        --) shift; break ;;
        --soft|--no-exit) soft=1; shift ;;
        --quiet) quiet=1; shift ;;
        *) shift ;;
      esac
    done
    local command_name="$1"
    local wrapper_line="soft=${soft} $1"
    shift
    for arg in "$@"; do wrapper_line+=" ${arg}"; done
    printf '%s\n' "${wrapper_line}" >>"${WRAPPER_LOG}"
    set -- "${command_name}" "$@"
    local call_line="$1"
    shift
    for arg in "$@"; do call_line+=" ${arg}"; done
    printf '%s\n' "${call_line}" >>"${CALL_LOG}"
    if [[ "${command_name}" == rm ]]; then /bin/rm "$@"; return; fi
    local rc=0 output="" previous="" arg
    if [[ "${command_name}" == mktemp ]]; then
      if [[ "${FAIL_MKTEMP:-0}" == 1 ]]; then
        mkdir -p "${TEST_ROOT}/failed-temp"
        printf '%s' "${TEST_ROOT}/failed-temp"
        rc=51
      elif [[ "${EMPTY_MKTEMP:-0}" == 1 ]]; then :
      else output="$(command mktemp "$@")" || rc=$?
      fi
      if (( rc == 0 )); then printf '%s\n' "${output}" >>"${TEMP_PATH_LOG}"; printf '%s' "${output}"; fi
    elif [[ "${command_name}" == envsubst || "${command_name}" == jq || "${command_name}" == head || "${command_name}" == cat ]]; then
      command "${command_name}" "$@" || rc=$?
    elif [[ "${command_name}" == openssl ]]; then
      if [[ "${OPENSSL_FAIL:-0}" == 1 ]]; then printf 'partial-password'; rc=52
      elif [[ "${OPENSSL_EMPTY:-0}" != 1 ]]; then printf '%s' "${PASSWORD_FIXTURE:-fixture-generated-password}"
      fi
    elif [[ "${command_name}" == security && "${1:-}" == find-generic-password ]]; then
      if [[ "${SECURITY_MISSING:-0}" == 1 && ! -f "${TEST_ROOT}/security.stdin" ]]; then
        rc=44
      elif [[ "${SECURITY_MISMATCH:-0}" == 1 ]]; then
        printf 'different-read-back-password'
      elif [[ -f "${TEST_ROOT}/security.stdin" ]]; then
        printf 'fixture-generated-password'
      else
        printf '%s' "${PASSWORD_FIXTURE:-fixture-greppable-password}"
      fi
    elif [[ "${command_name}" == security && "${1:-}" == -i ]]; then
      cat >"${TEST_ROOT}/security.stdin" || rc=$?
    elif [[ "${command_name}" == git ]]; then
      if [[ "${GIT_HEAD_FAIL:-0}" == 1 && "$*" == "rev-parse --abbrev-ref HEAD" ]]; then
        rc=53
      elif [[ "${EMPTY_GIT_HEAD:-0}" == 1 && "$*" == "rev-parse --abbrev-ref HEAD" ]]; then
        :
      else
        command git "$@" || rc=$?
      fi
    elif [[ "${command_name}" == kubectl ]]; then
      previous=""
      for arg in "$@"; do
        if [[ "${previous}" == -f ]]; then
          if [[ "${arg}" == - ]]; then cat >>"${APPLY_LOG}" || rc=$?
          elif [[ -f "${arg}" ]]; then cat "${arg}" >>"${APPLY_LOG}" || rc=$?
          fi
        fi
        previous="${arg}"
      done
      if [[ "${FAIL_KUBECTL_APPLY:-0}" == 1 && " $* " == *" apply "* ]]; then rc=41; fi
      case "$(cat "${CALL_LOG}" | tail -1)" in
        "kubectl config current-context") printf '%s' "${CURRENT_CONTEXT:-k3d-k3d-cluster}" ;;
        *"list -n dev-hub --output json"*)
          if [[ "${EXIST_VCLUSTER:-0}" == 1 ]]; then printf '[{"Name":"dev-hub","Status":"Ready"}]'; else printf '[]'; fi
          ;;
        *"get namespace dev-hub"*) [[ "${EXIST_NAMESPACE:-0}" == 1 ]] || rc=$? ;;
        *"get --raw=/readyz"*)
          local ready_attempts
          ready_attempts="$(grep -c 'get --raw=/readyz' "${CALL_LOG}" || true)"
          if [[ "${READY_ALWAYS_FAIL:-0}" == 1 || "${ready_attempts}" -le "${READY_FAIL_COUNT:-0}" ]]; then
            printf 'The connection to the server localhost:11444 was refused'
            rc=1
          else
            printf 'ok'
          fi
          ;;
        *"get resourcequota -n dev-hub -o json"*) printf '{"items":[{"status":{"used":{"limits.memory":"512Mi","limits.cpu":"200m"},"hard":{"limits.memory":"3Gi","limits.cpu":"3"}}}]}' ;;
        *"get applicationset grafana-dashboards-hub"*)
          if [[ "${APPSET_MISSING:-0}" == 1 ]]; then rc=1; else printf '%s' "${APPSET_BRANCH:-release-branch}"; fi
          ;;
        *"get applicationset "*) rc=1 ;;
        *"--kubeconfig ${HOME}/.kube/vclusters/dev-hub.yaml"*"get service hub-prometheus"*)
          local service_attempts
          service_attempts="$(grep -c 'get service hub-prometheus' "${CALL_LOG}" || true)"
          if [[ "${SERVICE_WARNING:-0}" == 1 ]]; then
            printf 'warning: fixture warning on stderr\n' >&2
            printf 'service/hub-prometheus'
          elif [[ "${SERVICE_FAIL_TWICE:-0}" == 1 && "${service_attempts}" -le 2 ]]; then
            printf 'The connection to the server localhost:11444 was refused'
            rc=1
          elif [[ "${SERVICE_ERROR:-}" == unreachable ]]; then
            printf 'The connection to the server localhost:11444 was refused'
            rc=1
          elif [[ "${SERVICE_ERROR:-}" == notfound || "${EXIST_PROMETHEUS_SERVICE:-0}" != 1 ]]; then
            rc=0
          else
            printf 'service/hub-prometheus'
          fi
          ;;
        *"create namespace monitoring"*) printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: monitoring\n' ;;
        *) : ;;
      esac
    elif [[ "${command_name}" == helm && "${FAIL_HELM:-}" == grafana \
      && "$(cat "${CALL_LOG}" | tail -1)" == *"upgrade --install dev-hub-grafana"* ]]; then
      rc=42
    elif [[ "${command_name}" == sleep ]]; then
      :
    elif [[ "${command_name}" == vcluster ]]; then
      case "$(cat "${CALL_LOG}" | tail -1)" in
        *" connect dev-hub "*) [[ "${EMPTY_EXPORTED_KUBECONFIG:-0}" == 1 ]] || printf 'apiVersion: v1\nkind: Config\n' ;;
        *"list -n dev-hub --output json"*)
          if [[ "${EXIST_VCLUSTER:-0}" == 1 ]]; then printf '[{"Name":"dev-hub","Status":"Ready"}]'; else printf '[]'; fi
          ;;
        *) : ;;
      esac
    else
      :
    fi
    if (( rc != 0 )); then
      if (( soft )); then return "${rc}"; fi
      _err "failed to execute ${command_name}: ${rc}"
    fi
    (( quiet )) || :
    return 0
  }
  _vcluster_check_prerequisites() { _VCLUSTER_BIN="${VCLUSTER_TEST_BIN:-vcluster}"; }
  _info() { :; }
  _err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
  vcluster_create() {
    printf 'vcluster-create %s namespace=%s port=%s values=%s\n' "$1" "$VCLUSTER_NAMESPACE" "$VCLUSTER_LOCAL_PORT" "$VCLUSTER_VALUES_FILE" >>"${CALL_LOG}"
    mkdir -p "$(dirname "${DEV_HUB_KUBECONFIG}")"
    if [[ "${DRY_RUN:-0}" == 1 ]]; then
      return 0
    elif [[ "${EMPTY_CREATED_KUBECONFIG:-0}" != 1 ]]; then
      printf 'fixture kubeconfig\n' >"${DEV_HUB_KUBECONFIG}"
    else
      : >"${DEV_HUB_KUBECONFIG}"
    fi
    mkdir -p "$(dirname "${DEV_HUB_KUBECONFIG}")"
    if [[ "${EMPTY_CREATED_KUBECONFIG:-0}" != 1 ]]; then
      printf 'fixture kubeconfig\n' >"${DEV_HUB_KUBECONFIG}"
    else
      : >"${DEV_HUB_KUBECONFIG}"
    fi
  }
  _vcluster_remove_proxy() { printf 'remove-proxy %s\n' "$1" >>"${CALL_LOG}"; }
  _vcluster_refresh_connection() { printf 'refresh-connection %s\n' "$1" >>"${CALL_LOG}"; }
  if [[ -r "${SCRIPT_DIR}/plugins/dev_hub.sh" ]]; then
    # shellcheck source=../../plugins/dev_hub.sh
    source "${SCRIPT_DIR}/plugins/dev_hub.sh"
  fi
  # Use the production kubeconfig exporter, with a file writer isolated in the fixture.
  source "${SCRIPT_DIR}/plugins/vcluster.sh"
  _write_sensitive_file() {
    mkdir -p "${HOME}/.kube/vclusters"
    printf '%s' "$2" >"$1"
  }
  _vcluster_check_prerequisites() { _VCLUSTER_BIN="${VCLUSTER_TEST_BIN:-vcluster}"; }
  vcluster_create() {
    printf 'vcluster-create %s namespace=%s port=%s values=%s\n' "$1" "$VCLUSTER_NAMESPACE" "$VCLUSTER_LOCAL_PORT" "$VCLUSTER_VALUES_FILE" >>"${CALL_LOG}"
    mkdir -p "$(dirname "${DEV_HUB_KUBECONFIG}")"
    if [[ "${DRY_RUN:-0}" == 1 ]]; then
      return 0
    elif [[ "${EMPTY_CREATED_KUBECONFIG:-0}" != 1 ]]; then
      printf 'fixture kubeconfig\n' >"${DEV_HUB_KUBECONFIG}"
    else
      : >"${DEV_HUB_KUBECONFIG}"
    fi
  }
  _vcluster_remove_proxy() { printf 'remove-proxy %s\n' "$1" >>"${CALL_LOG}"; }
  _vcluster_refresh_connection() { printf 'refresh-connection %s\n' "$1" >>"${CALL_LOG}"; }
}

setup_sync_repo() {
  local sync_root="${TEST_ROOT}/sync"
  export SYNC_CLONE="${sync_root}/clone" REAL_GIT=1
  mkdir -p "${sync_root}"
  git init --bare "${sync_root}/origin.git" >/dev/null 2>&1
  git clone "${sync_root}/origin.git" "${SYNC_CLONE}" >/dev/null 2>&1
  git -C "${SYNC_CLONE}" config user.name 'Dev Hub Test'
  git -C "${SYNC_CLONE}" config user.email 'dev-hub-test@example.invalid'
  mkdir -p "${SYNC_CLONE}/scripts/etc/argocd"
  cp -R "${SOURCE_SCRIPTS_DIR}/etc/argocd/applicationsets" \
    "${SYNC_CLONE}/scripts/etc/argocd/"
  git -C "${SYNC_CLONE}" checkout -qb release-branch
  git -C "${SYNC_CLONE}" add scripts/etc/argocd/applicationsets
  git -C "${SYNC_CLONE}" commit -qm 'fixture ApplicationSet'
  git -C "${SYNC_CLONE}" push -qu origin release-branch
  git -C "${SYNC_CLONE}" branch other-branch release-branch
  git -C "${SYNC_CLONE}" push -qu origin other-branch
  git -C "${SYNC_CLONE}" branch main release-branch
  git -C "${SYNC_CLONE}" push -qu origin main
  git -C "${SYNC_CLONE}" branch deploy/hub release-branch
  git -C "${SYNC_CLONE}" push -qu origin deploy/hub
  cd "${SYNC_CLONE}"
}

teardown() {
  rm -rf -- "${TEST_ROOT}"
}

@test "dev hub up applies host objects in namespace and creates the vCluster with its dedicated settings" {
  local argocd_version
  argocd_version="$(sed -n 's/^export ARGOCD_HELM_CHART_VERSION="\([^"]*\)".*/\1/p' \
    "${SOURCE_SCRIPTS_DIR}/etc/argocd/vars.sh")"
  dev_hub_up
  grep -F 'apply -f '"${SCRIPT_DIR}"'/etc/dev-hub/priorityclass.yaml' "${CALL_LOG}"
  grep -F 'apply -n dev-hub -f '"${SCRIPT_DIR}"'/etc/dev-hub/resourcequota.yaml' "${CALL_LOG}"
  grep -F 'vcluster-create dev-hub namespace=dev-hub port=11444' "${CALL_LOG}"
  [ "$(grep -c '^vcluster-create dev-hub' "${CALL_LOG}")" -eq 1 ]
  grep -F 'upgrade --install argocd argo/argo-cd' "${CALL_LOG}" | grep -F -- "--version ${argocd_version} " | grep -F -- '--wait'
  grep -E '^kubectl --kubeconfig .* apply -f .*/argocd-project.yaml$' "${CALL_LOG}"
  grep -E '^helm .*upgrade --install dev-hub-grafana grafana/grafana .*--version 8\.8\.2 .*--wait$' "${CALL_LOG}"
}

@test "dev-hub dry run skips kubeconfig checks, password setup, and chart installs" {
  export DRY_RUN=1
  run dev_hub_up
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"DRY_RUN: would install argo-cd ${DEV_HUB_ARGOCD_VERSION} and grafana ${DEV_HUB_GRAFANA_VERSION} into the dev-hub vCluster"* ]]
  if grep -E '^(security|helm) ' "${CALL_LOG}"; then return 1; fi
}

@test "service check failure branch does not contain an impossible success condition" {
  awk '/if \(\( service_rc != 0 \)\); then/ { in_failure=1; found=1; next } \
    in_failure && /fi/ { in_failure=0 } \
    in_failure && /service_rc == 0/ { exit 1 } \
    END { if (!found) exit 1 }' "${SOURCE_SCRIPTS_DIR}/plugins/dev_hub.sh"
}

@test "dev hub up is idempotent for an existing namespace and vCluster" {
  export EXIST_NAMESPACE=1 EXIST_VCLUSTER=1 EXIST_PROMETHEUS_SERVICE=1
  printf 'fixture kubeconfig\n' >"${HOME}/.kube/vclusters/dev-hub.yaml"
  dev_hub_up
  if grep -q 'create namespace dev-hub' "${CALL_LOG}"; then return 1; fi
  if grep -q '^vcluster-create ' "${CALL_LOG}"; then return 1; fi
  grep -Fx 'refresh-connection dev-hub' "${CALL_LOG}"
  grep -F -- "--kubeconfig ${HOME}/.kube/vclusters/dev-hub.yaml --request-timeout=5s -n monitoring get service hub-prometheus" "${CALL_LOG}"
}

@test "existing dev hub fails with repair guidance when replicated Prometheus Service is missing" {
  export EXIST_NAMESPACE=1 EXIST_VCLUSTER=1
  run dev_hub_up
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"make dev-hub-down then make dev-hub-up"* ]]
  grep -Fx 'refresh-connection dev-hub' "${CALL_LOG}"
  grep -F -- "--kubeconfig ${HOME}/.kube/vclusters/dev-hub.yaml --request-timeout=5s -n monitoring get service hub-prometheus" "${CALL_LOG}"
  [ "$(grep -c 'get service hub-prometheus' "${CALL_LOG}")" -eq 1 ]
  [ "$(grep -c '^sleep ' "${CALL_LOG}" || true)" -eq 0 ]
}

@test "dev hub up rejects and removes an empty kubeconfig from vCluster creation" {
  export EMPTY_CREATED_KUBECONFIG=1
  run dev_hub_up
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"did not produce a non-empty kubeconfig"* ]]
  [ ! -e "${HOME}/.kube/vclusters/dev-hub.yaml" ]
  if grep -E 'helm .*upgrade --install' "${CALL_LOG}"; then return 1; fi
}

@test "dev hub up rejects and removes an empty kubeconfig from export" {
  export EXIST_NAMESPACE=1 EXIST_VCLUSTER=1 EMPTY_EXPORTED_KUBECONFIG=1
  : >"${HOME}/.kube/vclusters/dev-hub.yaml"
  run dev_hub_up
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"export produced an empty file"* ]]
  [ ! -e "${HOME}/.kube/vclusters/dev-hub.yaml" ]
  grep -F 'vcluster connect dev-hub -n dev-hub --local-port 11444 --print' "${CALL_LOG}"
  if grep -E 'helm .*upgrade --install' "${CALL_LOG}"; then return 1; fi
}

@test "first-up vCluster absence is a soft query result, not a command error" {
  _dev_hub_load_vcluster
  _vcluster_check_prerequisites
  run _dev_hub_cluster_exists
  [ "${status}" -eq 1 ]
  [[ "${output}" != *"ERROR:"* ]]
  grep -E '^soft=1 jq -e --arg name dev-hub ' "${WRAPPER_LOG}"
}

@test "M4 missing ApplicationSet reports unknown and still prints Grafana access" {
  export APPSET_MISSING=1
  run dev_hub_status
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ApplicationSet targetRevision: unknown"* ]]
  [[ "${output}" == *"Grafana URL: http://127.0.0.1:13000"* ]]
  grep -E '^soft=1 kubectl --kubeconfig .* get applicationset grafana-dashboards-hub ' "${WRAPPER_LOG}"
}

@test "chart installation removes its password secret directory after helm failure" {
  export FAIL_HELM=grafana
  run _dev_hub_install_charts
  [ "${status}" -ne 0 ]
  [ -s "${TEMP_PATH_LOG}" ]
  while IFS= read -r temp_path; do
    [ ! -e "${temp_path}" ]
    [ ! -e "${temp_path}/grafana-secret.yaml" ]
  done <"${TEMP_PATH_LOG}"
}

@test "dev hub up stops when the written Grafana password does not verify" {
  export SECURITY_MISSING=1 SECURITY_MISMATCH=1
  run dev_hub_up
  [ "${status}" -ne 0 ]
  if grep -F 'admin-password:' "${APPLY_LOG}"; then return 1; fi
  if grep -F 'upgrade --install dev-hub-grafana' "${CALL_LOG}"; then return 1; fi
}

@test "dev hub up stops for failed or empty temporary directory creation" {
  export FAIL_MKTEMP=1
  run dev_hub_up
  [ "${status}" -ne 0 ]
  if grep -F 'admin-password:' "${APPLY_LOG}"; then return 1; fi
  if grep -F 'upgrade --install dev-hub-grafana' "${CALL_LOG}"; then return 1; fi
  : >"${CALL_LOG}" "${APPLY_LOG}" "${TEMP_PATH_LOG}" "${WRAPPER_LOG}"
  unset FAIL_MKTEMP
  export EMPTY_MKTEMP=1
  run dev_hub_up
  [ "${status}" -ne 0 ]
  if grep -F 'upgrade --install dev-hub-grafana' "${CALL_LOG}"; then return 1; fi
  if grep -F 'admin-password:' "${APPLY_LOG}"; then return 1; fi
}

@test "dev hub up stops for failed or empty OpenSSL output before Keychain write" {
  export SECURITY_MISSING=1 OPENSSL_EMPTY=1
  run dev_hub_up
  [ "${status}" -ne 0 ]
  if grep -Fx 'security -i' "${CALL_LOG}"; then return 1; fi
  if grep -F 'upgrade --install dev-hub-grafana' "${CALL_LOG}"; then return 1; fi
  : >"${CALL_LOG}" "${APPLY_LOG}" "${TEMP_PATH_LOG}" "${WRAPPER_LOG}"
  export OPENSSL_EMPTY=0 OPENSSL_FAIL=1
  run dev_hub_up
  [ "${status}" -ne 0 ]
  if grep -Fx 'security -i' "${CALL_LOG}"; then return 1; fi
  if grep -F 'upgrade --install dev-hub-grafana' "${CALL_LOG}"; then return 1; fi
}

@test "dev-hub sync removes its rendered ApplicationSet after apply failure" {
  setup_sync_repo
  SCRIPT_DIR="${SYNC_CLONE}/scripts"
  export FAIL_KUBECTL_APPLY=1
  run dev_hub_sync "release-branch"
  [ "${status}" -ne 0 ]
  [ -s "${TEMP_PATH_LOG}" ]
  while IFS= read -r temp_path; do [ ! -e "${temp_path}" ]; done <"${TEMP_PATH_LOG}"
}

@test "dispatcher reaches dev_hub_sync and preserves subshell state" {
  run env HOME="$HOME" PATH="$PATH" bash "$SCRIPT_DIR/k3d-manager" dev_hub_sync main
  [ "$status" -ne 0 ]
  [[ "$output" == *"refuses protected branch 'main'"* ]]
  [[ "$output" != *"not found in plugins"* ]]

  run bash -c 'SCRIPT_DIR="$1"; PLUGINS_DIR="$SCRIPT_DIR/plugins"; source "$SCRIPT_DIR/plugins/dev_hub.sh"; before=$PWD; SENTINEL=before; _dev_hub_load_vcluster() { cd /; SENTINEL=leaked; }; dev_hub_sync main >/dev/null 2>&1 || :; [[ $PWD == "$before" && $SENTINEL == before ]]' _ "$SOURCE_SCRIPTS_DIR"
  [ "$status" -eq 0 ]
}

@test "dev hub up refuses a non-hub current context before lifecycle calls" {
  export CURRENT_CONTEXT=ubuntu-k3s
  run dev_hub_up
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ubuntu-k3s"* && "${output}" == *"k3d-k3d-cluster"* ]]
  [ "$(wc -l <"${CALL_LOG}")" -eq 1 ]
  grep -Fx 'kubectl config current-context' "${CALL_LOG}"
  if grep -E 'vcluster-create|vcluster (create|delete|list)|(^| )apply( |$)|(^| )delete( |$)' "${CALL_LOG}"; then return 1; fi
}

@test "dev hub down refuses a non-hub current context before lifecycle calls" {
  export CURRENT_CONTEXT=ubuntu-k3s
  run dev_hub_down
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ubuntu-k3s"* && "${output}" == *"k3d-k3d-cluster"* ]]
  [ "$(wc -l <"${CALL_LOG}")" -eq 1 ]
  grep -Fx 'kubectl config current-context' "${CALL_LOG}"
  if grep -E 'vcluster-create|vcluster (create|delete|list)|(^| )apply( |$)|(^| )delete( |$)' "${CALL_LOG}"; then return 1; fi
}

@test "dev hub status refuses a non-hub current context before read calls" {
  export CURRENT_CONTEXT=ubuntu-k3s
  run dev_hub_status
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ubuntu-k3s"* && "${output}" == *"k3d-k3d-cluster"* ]]
  [ "$(wc -l <"${CALL_LOG}")" -eq 1 ]
  grep -Fx 'kubectl config current-context' "${CALL_LOG}"
  if grep -E 'vcluster-create|vcluster (create|delete|list)|(^| )apply( |$)|(^| )delete( |$)' "${CALL_LOG}"; then return 1; fi
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
  if grep -REin 'VAULT_ADDR|vault token|ExternalSecret|SecretStore|kubeconfig|pushgateway|remote_write' \
    "${SCRIPT_DIR}/etc/dev-hub" "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml"; then return 1; fi
}

@test "N3 positive control creates dev-hub in dev-hub and never uses vclusters" {
  dev_hub_up
  grep -F 'vcluster-create dev-hub namespace=dev-hub' "${CALL_LOG}"
  if grep -E ' -n vclusters([[:space:]]|$)' "${CALL_LOG}"; then return 1; fi
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
  if grep -REn 'all:[[:space:]]*true|mountPath:.*dashboard|configMap:.*dashboard' \
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
  if grep -En 'HubVmMemoryLow|DevHubNearQuota' "${route}"; then return 1; fi
  grep -F 'memory: 768Mi' "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml"
  grep -F 'memory: 128Mi' "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml"
  grep -A 4 '^redisSecretInit:' "${SCRIPT_DIR}/etc/dev-hub/argocd-values.yaml" | grep -F 'requests: {cpu: 20m, memory: 32Mi}'
  grep -A 4 '^redisSecretInit:' "${SCRIPT_DIR}/etc/dev-hub/argocd-values.yaml" | grep -F 'limits: {cpu: 100m, memory: 128Mi}'
  python3 - "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml" \
    "${SCRIPT_DIR}/etc/dev-hub/argocd-values.yaml" "${SCRIPT_DIR}/etc/dev-hub/grafana-values.yaml" \
    "${SCRIPT_DIR}/etc/dev-hub/resourcequota.yaml" <<'PY'
import re
import sys

files = [open(path, encoding="utf-8").read() for path in sys.argv[1:4]]
totals = {(kind, resource): 0 for kind in ("limits", "requests") for resource in ("cpu", "memory")}

def amount(value, resource):
    match = re.fullmatch(r"([0-9]+)(m|Ki|Mi|Gi)?", value)
    assert match, f"unsupported {resource} quantity: {value}"
    number, unit = int(match.group(1)), match.group(2) or ""
    if resource == "cpu":
        assert unit in ("", "m"), f"invalid CPU unit: {unit}"
        return number if unit == "m" else number * 1000
    factors = {"Ki": 1 / 1024, "Mi": 1, "Gi": 1024, "": 1}
    assert unit in factors, f"invalid memory unit: {unit}"
    return int(number * factors[unit])

for text in files:
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = re.match(r"^(\s*)(limits|requests):\s*(.*)$", line)
        if not match:
            continue
        kind, indent, initial = match.group(2), len(match.group(1)), match.group(3)
        block = initial
        for following in lines[index + 1:]:
            if following.strip() and len(following) - len(following.lstrip()) <= indent:
                break
            block += "\n" + following
        for resource, value in re.findall(r"\b(cpu|memory):\s*([0-9]+(?:m|Ki|Mi|Gi)?)", block):
            totals[(kind, resource)] += amount(value, resource)

quota_text = open(sys.argv[4], encoding="utf-8").read()
quota = {}
for line in quota_text.splitlines():
    match = re.match(r"^\s*(limits|requests)\.(cpu|memory):\s*\"?([0-9]+(?:m|Ki|Mi|Gi)?)\"?\s*$", line)
    if match:
        quota[(match.group(1), match.group(2))] = amount(match.group(3), match.group(2))
for key, total in totals.items():
    assert key in quota, f"ResourceQuota {key[0]}.{key[1]} is missing"
    assert total <= quota[key], f"container {key[0]} {key[1]} total {total} > quota {quota[key]}"
cpu_limit_total = totals[("limits", "cpu")]
assert cpu_limit_total <= 2700, f"container CPU limits total {cpu_limit_total}m > 2700m"
print("budget totals: " + "; ".join(f"{kind}.{resource}={total}" for (kind, resource), total in totals.items()))
PY
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

@test "N1 dev-hub sync applies dashboards only through the child kubeconfig" {
  setup_sync_repo
  export BRANCH_TEST=release-branch
  dev_hub_up
  SCRIPT_DIR="${SYNC_CLONE}/scripts"
  dev_hub_sync "${BRANCH_TEST}"
  grep -F -- '--kubeconfig '"${HOME}"'/.kube/vclusters/dev-hub.yaml apply -f ' "${CALL_LOG}"
  grep -F 'grafana-dashboards-hub' "${APPLY_LOG}"
  local call kubectl_count=0 helm_count=0
  while IFS= read -r call; do
    case "${call}" in
      'kubectl config current-context') continue ;;
      kubectl\ *|helm\ *)
        if [[ "${call}" != *"--kubeconfig ${DEV_HUB_KUBECONFIG}"* && \
          "${call}" != *"--context ${DEV_HUB_CONTEXT}"* ]]; then
          printf 'unscoped Kubernetes call: %s\n' "${call}" >&2
          return 1
        fi
        [[ "${call}" == kubectl\ * ]] && kubectl_count=$((kubectl_count + 1))
        [[ "${call}" == helm\ * ]] && helm_count=$((helm_count + 1))
        ;;
    esac
  done <"${CALL_LOG}"
  [ "${kubectl_count}" -gt 0 ]
  [ "${helm_count}" -gt 0 ]
  grep -F "targetRevision: '${BRANCH_TEST}'" "${APPLY_LOG}"
}

@test "N2 B values and helm argv contain no credentials" {
  local fixture="${TEST_ROOT}/fixture.yaml"
  printf 'endpoint: VAULT_ADDR\n' >"${fixture}"
  grep -Eq 'VAULT_ADDR' "${fixture}"
  [ -f "${SCRIPT_DIR}/etc/dev-hub/argocd-values.yaml" ]
  [ -f "${SCRIPT_DIR}/etc/dev-hub/grafana-values.yaml" ]
  dev_hub_up
  grep -F 'fixture-greppable-password' "${APPLY_LOG}" >/dev/null
  if grep -F 'fixture-greppable-password' "${CALL_LOG}"; then return 1; fi
  if grep -REin 'VAULT_ADDR|vault token|ExternalSecret|SecretStore|kubeconfig|pushgateway|remote_write' \
    "${SCRIPT_DIR}/etc/dev-hub" "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml"; then return 1; fi
  if grep -E -- '--set.*adminPassword|password=[^ ]+' "${CALL_LOG}"; then return 1; fi
}

@test "dev-hub generates a missing Grafana password through Keychain stdin" {
  export SECURITY_MISSING=1
  run _dev_hub_grafana_password
  [ "${status}" -eq 0 ]
  [ "${output}" = "fixture-generated-password" ]
  grep -F -- '-w fixture-generated-password' "${TEST_ROOT}/security.stdin" >/dev/null
  grep -Fx 'security -i' "${CALL_LOG}"
  if grep -F 'fixture-generated-password' "${CALL_LOG}"; then return 1; fi
}

@test "N4 sync allowlist applies only the dashboards ApplicationSet" {
  setup_sync_repo
  SCRIPT_DIR="${SYNC_CLONE}/scripts"
  dev_hub_sync "release-branch"
  [ "$(grep -c '^kubectl .* apply -f ' "${CALL_LOG}")" -eq 1 ]
  grep -F 'grafana-dashboards-hub' "${APPLY_LOG}"
  if grep -En 'name: (observability|platform-ops|vectordb|demo-rollout)|app-cluster-stage|projects/platform\.yaml|applicationsets/?([[:space:]]|$)' "${APPLY_LOG}" "${CALL_LOG}"; then return 1; fi
}

@test "M2 sync refuses a local branch head that differs from origin without applying" {
  setup_sync_repo
  SCRIPT_DIR="${SYNC_CLONE}/scripts"
  git commit --allow-empty -qm 'local-only head'
  run dev_hub_sync "release-branch"
  [ "${status}" -ne 0 ]
  if grep -q 'kubectl .*apply' "${CALL_LOG}"; then return 1; fi
}

@test "N6 Grafana dashboard sidecar is enabled without host ConfigMap sync" {
  grep -F 'enabled: true' "${SCRIPT_DIR}/etc/dev-hub/grafana-values.yaml"
  awk '/^sidecar:/ { inside=1; next } inside && /^[^ ]/ { exit } inside && /^  resources:/ { found=1 } END { exit !found }' \
    "${SCRIPT_DIR}/etc/dev-hub/grafana-values.yaml"
  if grep -E '^    resources:' "${SCRIPT_DIR}/etc/dev-hub/grafana-values.yaml"; then return 1; fi
  [ -f "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml" ]
  if grep -REn 'all:[[:space:]]*true|mountPath:.*dashboard|configMap:.*dashboard' \
    "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml" "${SCRIPT_DIR}/etc/dev-hub"; then return 1; fi
}

@test "dev-hub sync refuses protected and unpublished branches before apply" {
  setup_sync_repo
  SCRIPT_DIR="${SYNC_CLONE}/scripts"
  git checkout -qb unpublished
  git commit --allow-empty -qm 'unpublished branch'
  for branch in main deploy/hub; do
    run dev_hub_sync "${branch}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"refuses protected branch '${branch}'"* ]]
  done
  run dev_hub_sync unpublished
  [ "${status}" -ne 0 ]
  if grep -q 'kubectl .*apply' "${CALL_LOG}"; then return 1; fi
}

@test "dev-hub status reports branch and Grafana access" {
  dev_hub_status >"${TEST_ROOT}/status.out"
  grep -F 'ApplicationSet targetRevision: release-branch' "${TEST_ROOT}/status.out"
  grep -F 'kubectl --kubeconfig '"${HOME}"'/.kube/vclusters/dev-hub.yaml -n monitoring port-forward svc/dev-hub-grafana 13000:80' "${TEST_ROOT}/status.out"
  grep -F 'http://127.0.0.1:13000' "${TEST_ROOT}/status.out"
}

@test "dev-hub sync defaults to current branch and honors BRANCH environment" {
  setup_sync_repo
  SCRIPT_DIR="${SYNC_CLONE}/scripts"
  BRANCH=other-branch dev_hub_sync
  grep -F "targetRevision: 'other-branch'" "${APPLY_LOG}"
  : >"${APPLY_LOG}"
  unset BRANCH
  dev_hub_sync
  grep -F "targetRevision: 'release-branch'" "${APPLY_LOG}"
  [ "$(grep -c '^kubectl .* apply -f ' "${CALL_LOG}")" -eq 2 ]
}

@test "dev-hub sync stops on a failed mktemp without applying" {
  setup_sync_repo
  SCRIPT_DIR="${SYNC_CLONE}/scripts"
  export FAIL_MKTEMP=1
  run dev_hub_sync release-branch
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"could not create the rendered ApplicationSet file"* ]]
  if grep -q 'kubectl .*apply' "${CALL_LOG}"; then return 1; fi
}

@test "dev-hub sync stops when default git head lookup fails or is empty" {
  setup_sync_repo
  SCRIPT_DIR="${SYNC_CLONE}/scripts"
  export GIT_HEAD_FAIL=1
  run dev_hub_sync
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"could not determine the current branch"* ]]
  if grep -q 'kubectl .*apply' "${CALL_LOG}"; then return 1; fi
  unset GIT_HEAD_FAIL
  export EMPTY_GIT_HEAD=1
  run dev_hub_sync
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"current branch lookup returned an empty name"* ]]
  if grep -q 'kubectl .*apply' "${CALL_LOG}"; then return 1; fi
}

@test "dev_hub.sh has no unreachable returns after _err" {
  awk '/_err / { after_err=1; next } after_err && /^[[:space:]]*return [12]([[:space:]]|$)/ { exit 1 } \
    { after_err=0 }' "${SOURCE_SCRIPTS_DIR}/plugins/dev_hub.sh"
}

@test "chart setup xtrace never contains the Grafana password" {
  export SECURITY_MISSING=1
  local trace_file="${TEST_ROOT}/install.trace"
  if ( set -x; _dev_hub_install_charts ) 2>"${trace_file}"; then :; else return 1; fi
  grep -F '+ _dev_hub_install_charts' "${trace_file}"
  if grep -F 'fixture-generated-password' "${trace_file}"; then return 1; fi
  if ( set -x; _dev_hub_grafana_password >/dev/null ) 2>"${TEST_ROOT}/password.trace"; then :; else return 1; fi
  grep -F '+ _dev_hub_grafana_password' "${TEST_ROOT}/password.trace"
  if grep -E 'fixture-(generated|greppable)-password' "${TEST_ROOT}/password.trace"; then return 1; fi
}

@test "existing dev hub reports unreachable service without teardown guidance" {
  export EXIST_NAMESPACE=1 EXIST_VCLUSTER=1 SERVICE_ERROR=unreachable
  printf 'fixture kubeconfig\n' >"${HOME}/.kube/vclusters/dev-hub.yaml"
  run dev_hub_up
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"dev-hub is unreachable while checking Service hub-prometheus"* ]]
  [[ "${output}" != *"make dev-hub-down"* ]]
  [ "$(grep -c 'get service hub-prometheus' "${CALL_LOG}")" -eq 5 ]
  [ "$(grep -c 'get --raw=/readyz' "${CALL_LOG}")" -eq 1 ]
  [ "$(grep -c '^sleep 2$' "${CALL_LOG}")" -eq 4 ]
}

@test "existing dev hub readiness failure gives kubeconfig recovery guidance" {
  export EXIST_NAMESPACE=1 EXIST_VCLUSTER=1 EXIST_PROMETHEUS_SERVICE=1 READY_ALWAYS_FAIL=1
  printf 'fixture kubeconfig\n' >"${HOME}/.kube/vclusters/dev-hub.yaml"
  run dev_hub_up
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"dev-hub is unreachable; if the vCluster was recreated, remove ${DEV_HUB_KUBECONFIG} and rerun make dev-hub-up"* ]]
  [ "$(grep -c 'get --raw=/readyz' "${CALL_LOG}")" -eq 5 ]
  [ "$(grep -c 'get service hub-prometheus' "${CALL_LOG}" || true)" -eq 0 ]
}

@test "new dev hub fails closed when the readiness probe never succeeds" {
  export READY_ALWAYS_FAIL=1
  run dev_hub_up
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"dev-hub is unreachable; if the vCluster was recreated, remove ${DEV_HUB_KUBECONFIG} and rerun make dev-hub-up"* ]]
  [ "$(grep -c 'get --raw=/readyz' "${CALL_LOG}")" -eq 5 ]
  [ "$(grep -c '^sleep 2$' "${CALL_LOG}")" -eq 4 ]
  if grep -E '^(helm) ' "${CALL_LOG}"; then return 1; fi
}

@test "new dev hub installs charts after readiness succeeds on the third probe" {
  export READY_FAIL_COUNT=2
  dev_hub_up
  [ "$(grep -c 'get --raw=/readyz' "${CALL_LOG}")" -eq 3 ]
  [ "$(grep -c '^sleep 2$' "${CALL_LOG}")" -eq 2 ]
  grep -F 'upgrade --install argocd argo/argo-cd' "${CALL_LOG}"
}

@test "existing dev hub exports a missing kubeconfig before checking the service" {
  export EXIST_NAMESPACE=1 EXIST_VCLUSTER=1 EXIST_PROMETHEUS_SERVICE=1
  dev_hub_up
  [ -s "${HOME}/.kube/vclusters/dev-hub.yaml" ]
  grep -F 'vcluster connect dev-hub -n dev-hub --local-port 11444 --print' "${CALL_LOG}"
  grep -F -- "--kubeconfig ${HOME}/.kube/vclusters/dev-hub.yaml --request-timeout=5s -n monitoring get service hub-prometheus" "${CALL_LOG}"
}

@test "existing dev hub retries an unreachable Service check before succeeding" {
  export EXIST_NAMESPACE=1 EXIST_VCLUSTER=1 EXIST_PROMETHEUS_SERVICE=1 SERVICE_FAIL_TWICE=1
  printf 'fixture kubeconfig\n' >"${HOME}/.kube/vclusters/dev-hub.yaml"
  dev_hub_up
  [ "$(grep -c 'get service hub-prometheus' "${CALL_LOG}")" -eq 3 ]
  [ "$(grep -c '^sleep 2$' "${CALL_LOG}")" -eq 2 ]
}

@test "existing dev hub succeeds when Service lookup warns on stderr" {
  export EXIST_NAMESPACE=1 EXIST_VCLUSTER=1 EXIST_PROMETHEUS_SERVICE=1 SERVICE_WARNING=1
  printf 'fixture kubeconfig\n' >"${HOME}/.kube/vclusters/dev-hub.yaml"
  dev_hub_up
  [ "$(grep -c 'get service hub-prometheus' "${CALL_LOG}")" -eq 1 ]
  [ "$(grep -c '^sleep ' "${CALL_LOG}" || true)" -eq 0 ]
  grep -F -- '--request-timeout=5s' "${CALL_LOG}"
}

@test "refresh connection failure names the failed step" {
  export EXIST_NAMESPACE=1 EXIST_VCLUSTER=1
  printf 'fixture kubeconfig\n' >"${HOME}/.kube/vclusters/dev-hub.yaml"
  _vcluster_refresh_connection() { exit 1; }
  run dev_hub_up
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"connection refresh failed"* ]]
}

@test "dev-hub chart installs retain pins, wait flags, and AppProject apply" {
  local argocd_version
  argocd_version="$(sed -n 's/^export ARGOCD_HELM_CHART_VERSION="\([^"]*\)".*/\1/p' \
    "${SOURCE_SCRIPTS_DIR}/etc/argocd/vars.sh")"
  dev_hub_up
  grep -F 'upgrade --install argocd argo/argo-cd' "${CALL_LOG}" | grep -F -- "--version ${argocd_version} " | grep -F -- '--wait'
  grep -E '^kubectl --kubeconfig .* apply -f .*/argocd-project\.yaml$' "${CALL_LOG}"
  grep -E '^helm .*upgrade --install dev-hub-grafana grafana/grafana .*--version 8\.8\.2 .*--wait$' "${CALL_LOG}"
}

@test "dev-hub Argo CD default chart version comes from vars.sh" {
  local fixture_dir="${TEST_ROOT}/version-fixture" actual
  mkdir -p "${fixture_dir}/plugins" "${fixture_dir}/etc/argocd"
  cp "${SOURCE_SCRIPTS_DIR}/plugins/dev_hub.sh" "${fixture_dir}/plugins/dev_hub.sh"
  printf 'export ARGOCD_HELM_CHART_VERSION="10.10.6-fixture"\n' >"${fixture_dir}/etc/argocd/vars.sh"
  actual="$(bash -c 'SCRIPT_DIR="$1"; HOME="$2"; unset ARGOCD_HELM_CHART_VERSION; source "$SCRIPT_DIR/plugins/dev_hub.sh"; printf "%s" "$DEV_HUB_ARGOCD_VERSION"' \
    _ "${fixture_dir}" "${HOME}")"
  [ "${actual}" = "10.10.6-fixture" ]
}

@test "Keychain password read-back mismatch stops Grafana password setup" {
  export SECURITY_MISSING=1 SECURITY_MISMATCH=1
  run _dev_hub_grafana_password
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"read-back did not match"* ]]
  grep -E '^soft=1 security find-generic-password -w -s k3dm-dev-hub-grafana-admin -a k3dm$' "${WRAPPER_LOG}"
}

@test "Grafana secret quotes YAML-significant password characters" {
  export PASSWORD_FIXTURE='grafana: # operator value'
  dev_hub_up
  grep -F "admin-password: 'grafana: # operator value'" "${APPLY_LOG}"
}

@test "resource Deployment values use Recreate to avoid quota surges" {
  local values="${SCRIPT_DIR}/etc/dev-hub/argocd-values.yaml"
  # These chart templates render deploymentStrategy: templates/argocd-applicationset/deployment.yaml,
  # templates/argocd-repo-server/deployment.yaml, and templates/argocd-server/deployment.yaml.
  for component in applicationSet repoServer server; do
    awk -v key="${component}:" '$0 ~ "^" key { found=1; next } found && /^[^[:space:]]/ { exit } found && /deploymentStrategy: \{type: Recreate\}/ { ok=1; exit } END { exit !ok }' "${values}"
  done
  for component in controller redis; do
    if awk -v key="${component}:" '$0 ~ "^" key { found=1; next } found && /^[^[:space:]]/ { exit } found && /deploymentStrategy:/ { bad=1; exit } END { exit !bad }' "${values}"; then return 1; fi
  done
  grep -F 'deploymentStrategy: {type: Recreate}' "${SCRIPT_DIR}/etc/dev-hub/grafana-values.yaml"
}

@test "M3 Grafana has one hub Prometheus datasource and vCluster replicates its Service" {
  [ "$(grep -c 'uid: prometheus' "${SCRIPT_DIR}/etc/dev-hub/grafana-values.yaml")" -eq 1 ]
  grep -F 'url: http://hub-prometheus.monitoring.svc:9090' "${SCRIPT_DIR}/etc/dev-hub/grafana-values.yaml"
  grep -F 'from: monitoring/kube-prometheus-stack-prometheus' "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml"
  grep -F 'to: monitoring/hub-prometheus' "${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml"
  grep -F 'policy.default: role:readonly' "${SCRIPT_DIR}/etc/dev-hub/argocd-values.yaml"
  grep -Fx '    - https://github.com/wilddog64/k3d-manager' "${SCRIPT_DIR}/etc/dev-hub/argocd-project.yaml"
  grep -Fx '    - https://github.com/wilddog64/k3d-manager.git' "${SCRIPT_DIR}/etc/dev-hub/argocd-project.yaml"
  [ "$(grep -c '^      namespace:' "${SCRIPT_DIR}/etc/dev-hub/argocd-project.yaml")" -eq 1 ]
  grep -F 'namespace: monitoring' "${SCRIPT_DIR}/etc/dev-hub/argocd-project.yaml"
}
