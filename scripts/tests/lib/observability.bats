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
      printf "%s\n" "$*" > "${KUBE_STUB_LOG}"
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
}

@test "deploy_observability_acg calls envsubst with \$ARGOCD_NAMESPACE and \$K3D_MANAGER_BRANCH" {
  local envsubst_log kubectl_log
  envsubst_log="${BATS_TEST_TMPDIR}/envsubst-acg.log"
  kubectl_log="${BATS_TEST_TMPDIR}/kubectl-acg.log"
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
      printf "%s\n" "$*" > "${KUBE_STUB_LOG}"
    }
    kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    export -f envsubst _kubectl kubectl
    export K3D_MANAGER_BRANCH=feature-branch
    deploy_observability_acg
  '
  [ "$status" -eq 0 ]
  [[ -f "${envsubst_log}" ]]
  run cat "${envsubst_log}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\$ARGOCD_NAMESPACE \$K3D_MANAGER_BRANCH"* ]]
  run cat "${kubectl_log}"
  [ "$status" -eq 0 ]
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
    _kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    export -f _kubectl kubectl
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
    _kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    export -f _kubectl kubectl
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
    _kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    kubectl() {
      printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
    }
    export -f _kubectl kubectl
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
