#!/usr/bin/env bats
# scripts/tests/providers/k3s_gcp.bats — unit tests for k3s-gcp provider

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.kube"
  _info() { :; }
  _err()  { printf 'ERROR: %s\n' "$*" >&2; }
  gcloud()  { :; }
  kubectl() { :; }
  k3sup()   { :; }
  _ensure_k3sup() { :; }
  gcp_get_credentials() { :; }
  _ensure_gcloud() { :; }
  _run_command() { shift; return 0; }
  _command_exist() { command -v "$1" >/dev/null 2>&1; }
  export -f _info _err gcloud kubectl k3sup _ensure_k3sup gcp_get_credentials _ensure_gcloud _run_command _command_exist
  export SCRIPT_DIR="scripts"
  _GCP_ZONE="us-central1-a"
  _GCP_INSTANCE_NAME="k3s-gcp-server"
  export _GCP_KUBECONFIG="${HOME}/.kube/k3s-gcp.yaml"
  : > "${_GCP_KUBECONFIG}"
  source "scripts/lib/providers/k3s-gcp.sh"
}

@test "_provider_k3s_gcp_destroy_cluster requires --confirm" {
  run _provider_k3s_gcp_destroy_cluster
  [ "$status" -ne 0 ]
  [[ "$output" == *"--confirm"* ]] || [[ "$stderr" == *"--confirm"* ]]
}

@test "_provider_k3s_gcp_destroy_cluster --help exits 0" {
  run _provider_k3s_gcp_destroy_cluster --help
  [ "$status" -eq 0 ]
}

@test "_ensure_gcloud returns 0 when gcloud is already installed" {
  gcloud() { :; }
  export -f gcloud
  run _ensure_gcloud
  [ "$status" -eq 0 ]
}

@test "_ensure_gcloud errors when gcloud missing and brew missing" {
  unset -f gcloud 2>/dev/null || true
  PATH_ORIG="$PATH"
  export PATH="/nonexistent"
  _command_exist() { return 1; }
  export -f _command_exist
  run _ensure_gcloud
  export PATH="$PATH_ORIG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"install manually"* ]] || [[ "$stderr" == *"install manually"* ]]
}

@test "gcp_grant_compute_admin returns 0 when gcloud grant succeeds" {
  source "${BATS_TEST_DIRNAME}/../../plugins/gcp.sh"
  local _tmpkey
  _tmpkey=$(mktemp)
  printf '{"client_email":"sa@proj.iam.gserviceaccount.com"}' > "${_tmpkey}"

  gcloud() {
    case "$*" in
      *"auth list"*"ACTIVE"*) echo "sandbox@example.com" ;;
      *"auth list"*) echo "sandbox@example.com" ;;
      *"add-iam-policy-binding"*) return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f gcloud

  GCP_PROJECT="test-proj" GCP_USERNAME="sandbox@example.com" \
    run gcp_grant_compute_admin "test-proj" "${_tmpkey}"
  rm -f "${_tmpkey}"
  [ "$status" -eq 0 ]
}

@test "_provider_k3s_gcp_status errors when kubeconfig missing" {
  rm -f "${_GCP_KUBECONFIG}"
  run _provider_k3s_gcp_status
  [ "$status" -ne 0 ]
  [[ "$output" == *"k3s-gcp"* ]] || [[ "$stderr" == *"k3s-gcp"* ]]
}

@test "_provider_k3s_gcp_status runs kubectl commands when kubeconfig present" {
  : > "${_GCP_KUBECONFIG}"
  _command_exist() { [[ "$1" == "gcloud" ]] && return 0 || command -v "$1" >/dev/null 2>&1; }
  export -f _command_exist
  kubectl() { printf 'kubectl %s\n' "$*"; }
  export -f kubectl
  GCP_PROJECT="test-proj" run _provider_k3s_gcp_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"kubectl get nodes"* ]]
  [[ "$output" == *"kubectl get pods"* ]]
}
