#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT_DIR="${REPO_ROOT}/scripts"
  PLUGINS_DIR="${SCRIPT_DIR}/plugins"
  source "${REPO_ROOT}/scripts/plugins/argocd.sh"
  source "${REPO_ROOT}/scripts/lib/providers/k3s-hostinger.sh"
  _HOSTINGER_KUBE_CONTEXT="ubuntu-hostinger"
  ARGOCD_NAMESPACE="cicd"
  ARGOCD_CHART_VERSION="7.8.1"
  _argocd_hub_kubectl_cmd() { printf '%s\n' "kubectl --context k3d-k3d-cluster"; }
  _hostinger_ensure_argocd_manager_sa() { :; }
  _argocd_set_active_app_cluster() { :; }
  _info() { :; }
  _warn() { printf '%s\n' "$*" >&2; }
  _err() { printf '%s\n' "$*" >&2; return 1; }
  kubectl() {
    case "$*" in
      *'config view --raw -o jsonpath='*'server}'*) printf '%s' 'https://2.25.146.252:6443' ;;
      *'config view --raw -o jsonpath='*'certificate-authority-data}'*) printf '%s' 'ca-data' ;;
      *'create token argocd-manager'*) printf '%s' 'hostinger-token' ;;
      *'apply -f '* )
        local file="${*: -1}"
        cp "${file}" "${BATS_TEST_TMPDIR}/rendered-secret.yaml"
        ;;
      *) return 0 ;;
    esac
  }
  unset ARGOCD_APP_CLUSTER_PROVIDER
}

@test "hostinger registration sets the k3s-hostinger provider label" {
  run _hostinger_register_cluster
  [ "$status" -eq 0 ]
  run grep -F 'k3d-manager/provider: "k3s-hostinger"' "${BATS_TEST_TMPDIR}/rendered-secret.yaml"
  [ "$status" -eq 0 ]
}

@test "an explicit provider override still wins" {
  export ARGOCD_APP_CLUSTER_PROVIDER="k3s-other"
  run _hostinger_register_cluster
  [ "$status" -eq 0 ]
  run grep -F 'k3d-manager/provider: "k3s-other"' "${BATS_TEST_TMPDIR}/rendered-secret.yaml"
  [ "$status" -eq 0 ]
}

@test "register_app_cluster warns when the provider is unset" {
  ARGOCD_APP_CLUSTER_SECRET_NAME="cluster-test"
  ARGOCD_APP_CLUSTER_NAME="test"
  ARGOCD_APP_CLUSTER_SERVER="https://test.example:6443"
  ARGOCD_APP_CLUSTER_TOKEN="token"
  ARGOCD_APP_CLUSTER_INSECURE="true"
  _kubectl() { :; }
  run register_app_cluster
  [ "$status" -eq 0 ]
  [[ "$output" == *"ARGOCD_APP_CLUSTER_PROVIDER unset"* ]]
  [[ "$output" == *"fall back to generic defaults"* ]]
}
