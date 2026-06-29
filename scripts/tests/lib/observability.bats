#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
  _info() { :; }
  export -f _info
  export HOME="${BATS_TEST_TMPDIR}"
  REPO_ROOT="$(pwd)"
  SCRIPT_DIR="${REPO_ROOT}/scripts"
  export REPO_ROOT SCRIPT_DIR
  source scripts/lib/system.sh
  source scripts/lib/core.sh
  source scripts/lib/provider.sh
  source scripts/plugins/observability.sh
}

@test "deploy_observability calls envsubst with \$ARGOCD_NAMESPACE and \$K3D_MANAGER_BRANCH" {
  local envsubst_log kubectl_log
  envsubst_log="${BATS_TEST_TMPDIR}/envsubst.log"
  kubectl_log="${BATS_TEST_TMPDIR}/kubectl.log"
  export ENVSTUB_LOG="${envsubst_log}" KUBE_STUB_LOG="${kubectl_log}"
  run bash -c '
    set -e
    REPO_ROOT="$(pwd)"
    SCRIPT_DIR="${REPO_ROOT}/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/plugins/observability.sh
    envsubst() {
      printf "%s\n" "$*" > "${ENVSTUB_LOG}"
      cat
    }
    _kubectl() {
      case "$*" in
        *"get secret vault-root -n secrets --context k3d-k3d-cluster -o jsonpath='{.data.root_token}'"*)
          printf "%s" "dG9rZW4="
          ;;
        *)
          printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
          ;;
      esac
    }
    kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    export -f envsubst _kubectl kubectl
    export K3D_MANAGER_BRANCH=feature-branch
    deploy_observability
  '
  [ "$status" -eq 0 ]
  [[ -f "${envsubst_log}" ]]
  run cat "${envsubst_log}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\$ARGOCD_NAMESPACE \$K3D_MANAGER_BRANCH"* ]]
  run cat "${kubectl_log}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"apply -f -"* ]]
  [[ "$output" == *"--context k3d-k3d-cluster -f ${REPO_ROOT}/scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml"* ]]
  [[ "$output" == *"--context k3d-k3d-cluster -f ${REPO_ROOT}/scripts/etc/observability/promtail.yaml"* ]]
}

@test "deploy_observability_acg calls envsubst with \$ARGOCD_NAMESPACE, \$K3D_MANAGER_BRANCH, and \$APP_CLUSTER_NAME" {
  local envsubst_log kubectl_log
  envsubst_log="${BATS_TEST_TMPDIR}/envsubst-acg.log"
  kubectl_log="${BATS_TEST_TMPDIR}/kubectl-acg.log"
  export ENVSTUB_LOG="${envsubst_log}" KUBE_STUB_LOG="${kubectl_log}"
  _acg_resolve_provider() {
    printf "%s\n" "k3s-hostinger"
  }
  _acg_provider_context() {
    case "$1" in
      k3s-hostinger) printf "%s\n" "ubuntu-hostinger" ;;
      *)             printf "%s\n" "ubuntu-k3s" ;;
    esac
  }
  envsubst() {
    printf "%s\n" "$*" >> "${ENVSTUB_LOG}"
    cat
  }
  _kubectl() {
    case "$*" in
      *"get secret vault-root -n secrets --context k3d-k3d-cluster -o jsonpath='{.data.root_token}'"*)
        printf "%s" "dG9rZW4="
        ;;
      *)
        printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
        ;;
    esac
  }
  kubectl() {
    printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
  }
  helm() {
    printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    return 0
  }
  curl() {
    case "$*" in
      *"/v1/secret/data/k3d-manager/alertmanager"*)
        printf '{"data":{"data":{"gmail_from":"alerts@example.com","gmail_app_pw":"app-password","sms_gateway":"12345"}}}'
        ;;
      *"/v1/secret/data/k3d-manager/prometheus-basic-auth"*)
        printf '{"data":{"data":{"user":"admin","password_bcrypt":"test_hash"}}}'
        ;;
      *)
        return 0
        ;;
      esac
  }
  run deploy_observability_acg
  [ "$status" -eq 0 ]
  [[ -f "${envsubst_log}" ]]
  [[ "$output" == *"Alertmanager config secret created on ACG (ubuntu-hostinger)"* ]]
  [[ "$output" == *"Prometheus web config secret applied (monitoring/prometheus-web-config on ubuntu-hostinger)"* ]]
  run cat "${envsubst_log}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\$ARGOCD_NAMESPACE \$K3D_MANAGER_BRANCH \$APP_CLUSTER_NAME"* ]]
  run cat "${kubectl_log}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--context ubuntu-hostinger -n monitoring get configmap grafana-dashboard-argocd"* ]]
  [[ "$output" == *"--context ubuntu-hostinger -n monitoring delete configmap grafana-dashboard-argocd"* ]]
  [[ "$output" == *"create namespace monitoring --context ubuntu-hostinger --dry-run=client -o yaml"* ]]
  [[ "$output" == *"apply -f -"* ]]
}

@test "trivy_scan_report calls kubectl get vulnerabilityreports -A for Hub context" {
  local kubectl_log
  kubectl_log="${BATS_TEST_TMPDIR}/kubectl-trivy-hub.log"
  export KUBE_STUB_LOG="${kubectl_log}"
  run bash -c '
    REPO_ROOT="$(pwd)"
    SCRIPT_DIR="${REPO_ROOT}/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/plugins/observability.sh
    _acg_resolve_provider() {
      printf "%s\n" "k3s-aws"
    }
    _acg_provider_context() {
      case "$1" in
        k3s-aws) printf "%s\n" "ubuntu-k3s" ;;
        *)       printf "%s\n" "ubuntu-k3s" ;;
      esac
    }
    _kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    export -f _acg_resolve_provider _acg_provider_context _kubectl kubectl
    trivy_scan_report
  '
  [ "$status" -eq 0 ]
  run cat "${kubectl_log}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"get vulnerabilityreports -A --no-headers"* ]]
}

@test "trivy_scan_report calls kubectl get vulnerabilityreports -A --context ubuntu-k3s for ACG" {
  local kubectl_log
  kubectl_log="${BATS_TEST_TMPDIR}/kubectl-trivy-acg.log"
  export KUBE_STUB_LOG="${kubectl_log}"
  run bash -c '
    REPO_ROOT="$(pwd)"
    SCRIPT_DIR="${REPO_ROOT}/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/plugins/observability.sh
    _acg_resolve_provider() {
      printf "%s\n" "k3s-aws"
    }
    _acg_provider_context() {
      case "$1" in
        k3s-aws) printf "%s\n" "ubuntu-k3s" ;;
        *)       printf "%s\n" "ubuntu-k3s" ;;
      esac
    }
    _kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    export -f _acg_resolve_provider _acg_provider_context _kubectl kubectl
    trivy_scan_report
  '
  [ "$status" -eq 0 ]
  run cat "${kubectl_log}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"get vulnerabilityreports -A --context ubuntu-k3s --no-headers"* ]]
}

@test "observability_status iterates over monitoring trivy-system for both contexts" {
  local kubectl_log
  kubectl_log="${BATS_TEST_TMPDIR}/kubectl-status.log"
  export KUBE_STUB_LOG="${kubectl_log}"
  run bash -c '
    REPO_ROOT="$(pwd)"
    SCRIPT_DIR="${REPO_ROOT}/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/plugins/observability.sh
    _acg_resolve_provider() {
      printf "%s\n" "k3s-aws"
    }
    _acg_provider_context() {
      case "$1" in
        k3s-aws) printf "%s\n" "ubuntu-k3s" ;;
        *)       printf "%s\n" "ubuntu-k3s" ;;
      esac
    }
    _kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    export -f _acg_resolve_provider _acg_provider_context _kubectl kubectl
    observability_status
  '
  [ "$status" -eq 0 ]
  run cat "${kubectl_log}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"_kubectl get pods -n monitoring --no-headers"* || "$output" == *"get pods -n monitoring --no-headers"* ]]
  [[ "$output" == *"_kubectl get pods -n trivy-system --no-headers"* || "$output" == *"get pods -n trivy-system --no-headers"* ]]
  [[ "$output" == *"kubectl get pods -n monitoring --context ubuntu-k3s --no-headers"* || "$output" == *"get pods -n monitoring --context ubuntu-k3s --no-headers"* ]]
  [[ "$output" == *"kubectl get pods -n trivy-system --context ubuntu-k3s --no-headers"* || "$output" == *"get pods -n trivy-system --context ubuntu-k3s --no-headers"* ]]
}
