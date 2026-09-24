#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  source "${BATS_TEST_DIRNAME}/../../plugins/istio_ambient.sh"
  ARGOCD_NAMESPACE=cicd
  APP_CLUSTER_NAME=ubuntu-hostinger
  ARGOCD_CONFIG_DIR="${BATS_TEST_TMPDIR}/argocd"
  mkdir -p "${ARGOCD_CONFIG_DIR}/applicationsets"
  printf '%s\n' '  name: istio-ambient' > "${ARGOCD_CONFIG_DIR}/applicationsets/istio-ambient.yaml"
  printf '%s\n' '  generators: ${AMBIENT_CNI_CONF_DIR} ${AMBIENT_CNI_BIN_DIR}' >> "${ARGOCD_CONFIG_DIR}/applicationsets/istio-ambient.yaml"
  export ARGOCD_NAMESPACE APP_CLUSTER_NAME ARGOCD_CONFIG_DIR
  _argocd_set_active_app_cluster() { :; }
  unset -f _acg_provider_context _acg_resolve_provider
}

configure_live_stub() {
  _kubectl() {
    [[ "${1:-}" == "--no-exit" ]] && shift
    if [[ "${1:-}" == "get" && "${2:-}" == "applicationset" ]]; then
      [[ -n "${LIVE_JSON:-}" ]] && printf '%s\n' "${LIVE_JSON}"
      return 0
    fi
    if [[ "${1:-}" == "apply" && "${2:-}" == "-f" && "${3:-}" == "-" ]]; then
      cat >/dev/null
      return 0
    fi
    return 1
  }
  export -f _kubectl
}

live_with_dirs() {
  LIVE_JSON='{"kind":"ApplicationSet","spec":{"generators":[{"list":{"elements":[{"name":"istio-cni","values":"cni:\n  cniConfDir: /etc/cni/net.d\n  cniBinDir: /opt/cni/bin"}]}}]}}'
}

set_provider() {
  local provider="$1" conf="$2" bin="$3"
  _istio_ambient_target_provider() { printf '%s\n' "${TEST_PROVIDER}"; }
  _istio_ambient_cni_dirs() { printf '%s %s\n' "${TEST_CONF}" "${TEST_BIN}"; }
  TEST_PROVIDER="${provider}" TEST_CONF="${conf}" TEST_BIN="${bin}"
  export TEST_PROVIDER TEST_CONF TEST_BIN
}

capture_overrides() {
  _argocd_appset_live_overrides "${ARGOCD_CONFIG_DIR}/applicationsets/istio-ambient.yaml" >"${BATS_TEST_TMPDIR}/overrides.out" 2>"${BATS_TEST_TMPDIR}/overrides.err"
  status=$?
  output="$(<"${BATS_TEST_TMPDIR}/overrides.out")"
  warnings="$(<"${BATS_TEST_TMPDIR}/overrides.err")"
}

@test "k3s provider wins over generic live CNI dirs" {
  live_with_dirs
  set_provider k3s /var/lib/rancher/k3s/agent/etc/cni/net.d /var/lib/rancher/k3s/data/cni
  configure_live_stub
  capture_overrides
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"AMBIENT_CNI_CONF_DIR=/var/lib/rancher/k3s/agent/etc/cni/net.d"* ]]
  [[ "${output}" == *"AMBIENT_CNI_BIN_DIR=/var/lib/rancher/k3s/data/cni"* ]]
  run grep -Fqx 'AMBIENT_CNI_CONF_DIR=/etc/cni/net.d' <<<"${output}"
  [ "${status}" -ne 0 ]
}

@test "orbstack provider wins over live CNI dirs" {
  live_with_dirs
  set_provider orbstack /orbstack/cni/net.d /orbstack/cni/bin
  configure_live_stub
  capture_overrides
  [[ "${output}" == *"AMBIENT_CNI_CONF_DIR=/orbstack/cni/net.d"* ]]
  [[ "${output}" == *"AMBIENT_CNI_BIN_DIR=/orbstack/cni/bin"* ]]
}

@test "usable live CNI dirs remain the fallback" {
  LIVE_JSON='{"kind":"ApplicationSet","spec":{"generators":[{"list":{"elements":[{"name":"istio-cni","values":"cni:\n  cniConfDir: /live/conf\n  cniBinDir: /live/bin"}]}}]}}'
  set_provider '' '' ''
  configure_live_stub
  capture_overrides
  [[ "${output}" == *"AMBIENT_CNI_CONF_DIR=/live/conf"* ]]
  [[ "${output}" == *"AMBIENT_CNI_BIN_DIR=/live/bin"* ]]
}

@test "no source emits no CNI override and returns zero" {
  LIVE_JSON=''
  set_provider '' '' ''
  configure_live_stub
  capture_overrides
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"AMBIENT_CNI_"* ]]
}

@test "k3s refuses generic CNI dirs" {
  live_with_dirs
  set_provider k3s-hostinger /etc/cni/net.d /opt/cni/bin
  configure_live_stub
  capture_overrides
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"AMBIENT_CNI_"* ]]
  [[ "${warnings}" == *"k3s-hostinger"* ]]
}

@test "live APP_CLUSTER_NAME override remains unchanged" {
  live_with_dirs
  set_provider k3s /k3s/conf /k3s/bin
  printf '%s\n' '  destination: ${APP_CLUSTER_NAME}' >> "${ARGOCD_CONFIG_DIR}/applicationsets/istio-ambient.yaml"
  LIVE_JSON='{"kind":"ApplicationSet","spec":{"template":{"spec":{"destination":{"name":"ubuntu-hostinger"}}}}}'
  configure_live_stub
  capture_overrides
  [[ "${output}" == *"APP_CLUSTER_NAME=ubuntu-hostinger"* ]]
  [[ "${output}" == *"AMBIENT_CNI_CONF_DIR=/k3s/conf"* ]]
}

@test "non-JSON live read still returns zero" {
  LIVE_JSON=''
  set_provider '' '' ''
  jq() {
    local input
    input="$(cat)"
    [[ -n "${input}" ]] || { echo "jq called with empty input" >&2; return 1; }
    if printf '%s' "${input}" | command jq "$@"; then
      return 0
    fi
    return 1
  }
  configure_live_stub
  capture_overrides
  [ "${status}" -eq 0 ]
  [ -z "${warnings}" ]
}

@test "ApplicationSet logging says resolved overrides" {
  live_with_dirs
  set_provider k3s /k3s/conf /k3s/bin
  export AMBIENT_CNI_CONF_DIR=/etc/cni/net.d AMBIENT_CNI_BIN_DIR=/opt/cni/bin
  configure_live_stub
  run _argocd_deploy_applicationsets
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"resolved overrides"* ]]
  [[ "${output}" != *"keeping live"* ]]
}
