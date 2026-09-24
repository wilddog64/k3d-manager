#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  source "${BATS_TEST_DIRNAME}/../../plugins/istio_ambient.sh"

  ARGOCD_CONFIG_DIR="${BATS_TEST_TMPDIR}/argocd"
  mkdir -p "${ARGOCD_CONFIG_DIR}/applicationsets"
  cp "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/istio-ambient.yaml" "${ARGOCD_CONFIG_DIR}/applicationsets/"
  cp "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/observability-acg.yaml" "${ARGOCD_CONFIG_DIR}/applicationsets/"
  cp "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/observability.yaml" "${ARGOCD_CONFIG_DIR}/applicationsets/"
  export ARGOCD_CONFIG_DIR ARGOCD_NAMESPACE=cicd K3D_MANAGER_BRANCH=test-branch
  export APP_CLUSTER_NAME=ubuntu-k3s AMBIENT_ISTIO_VERSION=1.24.2
  export AMBIENT_CNI_CONF_DIR=/etc/cni/net.d AMBIENT_CNI_BIN_DIR=/opt/cni/bin

  _argocd_set_active_app_cluster() { :; }
  unset -f _acg_provider_context _acg_resolve_provider
}

_live_istio_ambient() {
  printf '%s\n' '{"kind":"ApplicationSet","spec":{"template":{"spec":{"destination":{"name":"ubuntu-k3s"}}},"generators":[{"list":{"elements":[{"name":"istio-cni","values":"cni:\n  cniConfDir: /var/lib/rancher/k3s/agent/etc/cni/net.d\n  cniBinDir: /bin"}]}}]}}'
}

_live_observability_acg() {
  printf '%s\n' '{"kind":"ApplicationSet","spec":{"template":{"spec":{"destination":{"name":"ubuntu-hostinger"}}}}}'
}

_stub_appset_kubectl() {
  _kubectl() {
    [[ "${1:-}" == "--no-exit" ]] && shift
    printf '%s\n' "$*" >> "${KUBECTL_LOG}"
    if [[ "${1:-}" == "get" && "${2:-}" == "applicationset" ]]; then
      case "${3:-}" in
        istio-ambient) _live_istio_ambient ;;
        observability-acg) _live_observability_acg ;;
        *) printf '%s\n' 'Error from server (NotFound)' >&2; return 1 ;;
      esac
      return 0
    fi
    if [[ "${1:-}" == "apply" && "${2:-}" == "-f" && "${3:-}" == "-" ]]; then
      cat > "$(mktemp "${BATS_TEST_TMPDIR}/applied.XXXX")"
      return 0
    fi
    return 1
  }
}

_stub_no_live_appsets() {
  _kubectl() {
    [[ "${1:-}" == "--no-exit" ]] && shift
    printf '%s\n' "$*" >> "${KUBECTL_LOG}"
    if [[ "${1:-}" == "get" && "${2:-}" == "applicationset" ]]; then
      printf '%s\n' 'Error from server (NotFound)' >&2
      return 1
    fi
    if [[ "${1:-}" == "apply" && "${2:-}" == "-f" && "${3:-}" == "-" ]]; then
      cat > "$(mktemp "${BATS_TEST_TMPDIR}/applied.XXXX")"
      return 0
    fi
    return 1
  }
}

_applied_for() {
  local name applied
  name="$1"
  for applied in "${BATS_TEST_TMPDIR}"/applied.*; do
    [[ -f "${applied}" ]] || continue
    if [[ "$(yq -r '.metadata.name' "${applied}")" == "${name}" ]]; then
      printf '%s\n' "${applied}"
      return 0
    fi
  done
  return 1
}

@test "ApplicationSet reapply preserves live destination and CNI dirs" {
  _stub_appset_kubectl
  export APP_CLUSTER_NAME=ubuntu-hostinger

  run _argocd_deploy_applicationsets
  [ "$status" -eq 0 ]
  [[ "$output" == *"resolved overrides"* ]]

  local acg istio
  acg="$(_applied_for observability-acg)"
  istio="$(_applied_for istio-ambient)"
  [ "$(yq -r '.spec.template.spec.destination.name' "${acg}")" = "ubuntu-hostinger" ]
  [ "$(yq -r '.spec.template.spec.destination.name' "${istio}")" = "ubuntu-k3s" ]
  [[ "$(yq -r '.spec.template.metadata.name' "${istio}")" == *"-ubuntu-k3s" ]]
  [[ "$(yq -r '.spec.generators[0].list.elements[] | select(.name == "istio-cni") | .values' "${istio}")" == *"cniBinDir: /bin"* ]]
}

@test "ApplicationSet reapply uses CNI resolver when no live set exists" {
  _stub_no_live_appsets
  _istio_ambient_target_provider() { printf 'k3d\n'; }

  run _argocd_deploy_applicationsets
  [ "$status" -eq 0 ]

  local acg istio
  acg="$(_applied_for observability-acg)"
  istio="$(_applied_for istio-ambient)"
  [ "$(yq -r '.spec.template.spec.destination.name' "${acg}")" = "ubuntu-k3s" ]
  [[ "$(yq -r '.spec.generators[0].list.elements[] | select(.name == "istio-cni") | .values' "${istio}")" == *"cniConfDir: /var/lib/rancher/k3s/agent/etc/cni/net.d"* ]]
  [[ "$(yq -r '.spec.generators[0].list.elements[] | select(.name == "istio-cni") | .values' "${istio}")" == *"cniBinDir: /bin"* ]]
}

@test "ApplicationSet reapply keeps CNI environment defaults without a provider label" {
  _stub_no_live_appsets
  _istio_ambient_target_provider() { :; }

  run _argocd_deploy_applicationsets
  [ "$status" -eq 0 ]

  local istio
  istio="$(_applied_for istio-ambient)"
  [[ "$(yq -r '.spec.generators[0].list.elements[] | select(.name == "istio-cni") | .values' "${istio}")" == *"cniBinDir: /opt/cni/bin"* ]]
}

@test "ApplicationSet reapply ignores live values when requested" {
  _stub_appset_kubectl
  export ARGOCD_APPSET_IGNORE_LIVE=1 APP_CLUSTER_NAME=ubuntu-k3s

  run _argocd_deploy_applicationsets
  [ "$status" -eq 0 ]
  run grep -q -- 'get applicationset' "${KUBECTL_LOG}"
  [ "$status" -ne 0 ]

  local acg
  acg="$(_applied_for observability-acg)"
  [ "$(yq -r '.spec.template.spec.destination.name' "${acg}")" = "ubuntu-k3s" ]
}

@test "ApplicationSet reapply leaves sets without live overrides untouched" {
  _stub_appset_kubectl

  run _argocd_deploy_applicationsets
  [ "$status" -eq 0 ]

  local observability
  observability="$(_applied_for observability)"
  [ "$(yq -r '.spec.template.spec.sources[0].targetRevision' "${observability}")" = "test-branch" ]
  run _argocd_appset_live_overrides "${ARGOCD_CONFIG_DIR}/applicationsets/observability.yaml"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
