#!/usr/bin/env bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"

setup() {
  export PLUGINS_DIR="${BATS_TEST_TMPDIR}/plugins"
  export OBSERVABILITY_PLUGIN_PATH="${OBSERVABILITY_PLUGIN_PATH:-${REPO_ROOT}/scripts/plugins/observability.sh}"
  KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  : > "${KUBECTL_LOG}"
  source "${OBSERVABILITY_PLUGIN_PATH}"

  _info() { printf '%s\n' "$*"; }
  _warn() { printf '%s\n' "$*"; }
  sleep() { :; }

  _kubectl() {
    printf '%s\n' "$*" >> "${KUBECTL_LOG}"
    case "$*" in
      *"get crd servicemonitors.monitoring.coreos.com"*)
        [[ "${CRD_PRESENT:-true}" == "true" ]]
        ;;
      *"get servicemonitor kube-prometheus-stack-apiserver"*)
        [[ "${SERVICEMONITOR_PRESENT:-true}" == "true" ]] || return 1
        printf '%s' "${CURRENT_TIMEOUT:-}"
        ;;
      *"patch servicemonitor kube-prometheus-stack-apiserver"*)
        printf '%s' "$*" | sed 's/.* -p //' > "${BATS_TEST_TMPDIR}/patch-payload.txt"
        : > "${BATS_TEST_TMPDIR}/patch.marker"
        ;;
    esac
  }
}

@test "apiserver scrape timeout: patches unset endpoint to 45s" {
  run _observability_ensure_apiserver_scrape_timeout hub-context
  [ "${status}" -eq 0 ]
  run jq -e 'length == 1 and .[0].op == "add" and .[0].path == "/spec/endpoints/0/scrapeTimeout" and .[0].value == "45s"' "${BATS_TEST_TMPDIR}/patch-payload.txt"
  [ "${status}" -eq 0 ]
}

@test "apiserver scrape timeout: skips an already matching endpoint" {
  export CURRENT_TIMEOUT=45s
  run _observability_ensure_apiserver_scrape_timeout hub-context
  [ "${status}" -eq 0 ]
  patch_markers="$(find "${BATS_TEST_TMPDIR}" -name patch.marker -type f | wc -l | tr -d ' ')"
  [ "${patch_markers}" -eq 0 ]
}

@test "apiserver scrape timeout: honors the environment override" {
  export OBSERVABILITY_APISERVER_SCRAPE_TIMEOUT=30s
  run _observability_ensure_apiserver_scrape_timeout hub-context
  [ "${status}" -eq 0 ]
  run jq -e '.[0].value == "30s"' "${BATS_TEST_TMPDIR}/patch-payload.txt"
  [ "${status}" -eq 0 ]
}

@test "apiserver scrape timeout: missing ServiceMonitor is non-fatal" {
  export SERVICEMONITOR_PRESENT=false
  run _observability_ensure_apiserver_scrape_timeout hub-context
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"NOT ensured"* ]]
  patch_markers="$(find "${BATS_TEST_TMPDIR}" -name patch.marker -type f | wc -l | tr -d ' ')"
  [ "${patch_markers}" -eq 0 ]
}

@test "apiserver scrape timeout: patch payload changes only scrapeTimeout" {
  run _observability_ensure_apiserver_scrape_timeout hub-context
  [ "${status}" -eq 0 ]
  run jq -e 'length == 1 and .[0].path == "/spec/endpoints/0/scrapeTimeout" and (.[0] | has("jobLabel") | not) and (.[0] | has("selector") | not) and (.[0] | has("namespaceSelector") | not) and (.[0] | has("targetLabels") | not)' "${BATS_TEST_TMPDIR}/patch-payload.txt"
  [ "${status}" -eq 0 ]
}

@test "deploy_observability: ensures apiserver timeout after ArgoCD ServiceMonitors" {
  call_log="${BATS_TEST_TMPDIR}/call-order.log"
  : > "${call_log}"
  _observability_apply_grafana_rotator() { :; }
  _observability_install_prometheus_rotator() { :; }
  _observability_apply_argocd_dashboard() { :; }
  _deploy_promtail_acg() { :; }
  _observability_ensure_argocd_servicemonitors() { printf '%s\n' argocd >> "${call_log}"; }
  _observability_ensure_apiserver_scrape_timeout() { printf '%s\n' apiserver >> "${call_log}"; }
  _vault_login() { :; }
  _observability_ensure_alertmanager_login() { :; }
  _observability_install_alertmanager_port_forward() { :; }
  _observability_install_alertmanager_auth_proxy() { :; }
  _observability_refresh_prometheus_auth_proxy() { :; }
  envsubst() { cat; }
  curl() { return 1; }
  export K3D_MANAGER_BRANCH=test-branch

  run deploy_observability
  [ "${status}" -eq 0 ]
  run awk 'NR == 1 { first = $0 } NR == 2 { print first, $0; exit }' "${call_log}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "argocd apiserver" ]
}

_fresh_hub_deploy_observability() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  export SCRIPT_DIR="${REPO_ROOT}/scripts"
  mkdir -p "${HOME}"
  [[ "${HOME}" == "${BATS_TEST_TMPDIR}"/* ]]
  NS_MARKER="${BATS_TEST_TMPDIR}/monitoring-ns.created"
  curl() { return 1; }
  _vault_login() { :; }
  _observability_ensure_alertmanager_login() { :; }
  _observability_install_alertmanager_port_forward() { :; }
  _observability_install_alertmanager_auth_proxy() { :; }
  _observability_refresh_prometheus_auth_proxy() { :; }
  _observability_ensure_prometheus_login() { :; }
  _observability_apply_grafana_rotator() { :; }
  _observability_install_prometheus_rotator() { :; }
  _observability_apply_argocd_dashboard() { :; }
  _deploy_promtail_acg() { :; }
  _observability_ensure_argocd_servicemonitors() { :; }
  _observability_ensure_apiserver_scrape_timeout() { :; }
  _observability_apply_alertmanager_config() { :; }
  envsubst() { cat; }
  export K3D_MANAGER_BRANCH=test-branch
  # A fresh hub: the monitoring namespace does not exist until something creates it,
  # and a namespaced apply into it fails NotFound (M5, 2026-10-30).
  _kubectl() {
    printf '%s\n' "$*" >> "${KUBECTL_LOG}"
    case "$*" in
      "create namespace monitoring --dry-run=client -o yaml")
        printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: monitoring\n'
        ;;
      "apply -f -")
        if grep -q '^kind: Namespace' && [[ ! -e "${NS_MARKER}" ]]; then : > "${NS_MARKER}"; fi
        ;;
      "apply -f "*grafana-admin-externalsecret.yaml)
        [[ -e "${NS_MARKER}" ]] || { echo 'namespaces "monitoring" not found' >&2; return 1; }
        ;;
    esac
  }
}

@test "deploy_observability: creates the monitoring namespace before the Grafana ExternalSecret on a fresh hub" {
  _fresh_hub_deploy_observability
  [ ! -e "${NS_MARKER}" ]
  run deploy_observability
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Grafana admin credential ExternalSecret applied"* ]]
  ns_line="$(grep -n '^create namespace monitoring' "${KUBECTL_LOG}" | head -1 | cut -d: -f1)"
  es_line="$(grep -n 'grafana-admin-externalsecret.yaml' "${KUBECTL_LOG}" | head -1 | cut -d: -f1)"
  [ -n "${ns_line}" ] && [ -n "${es_line}" ]
  [ "${ns_line}" -lt "${es_line}" ]
}

@test "deploy_observability: Grafana ExternalSecret stub rejects an apply with no monitoring namespace" {
  _fresh_hub_deploy_observability
  run _kubectl apply -f "${REPO_ROOT}/scripts/etc/argocd/platform-ops/grafana-admin-externalsecret.yaml"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'namespaces "monitoring" not found'* ]]
}
