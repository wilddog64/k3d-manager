#!/usr/bin/env bats
# scripts/tests/providers/k3s_gcp.bats — unit tests for k3s-gcp provider

setup() {
  _info() { :; }
  _err()  { printf 'ERROR: %s\n' "$*" >&2; }
  gcloud()  { :; }
  kubectl() { :; }
  k3sup()   { :; }
  _ensure_k3sup() { :; }
  gcp_get_credentials() { :; }
  export -f _info _err gcloud kubectl k3sup _ensure_k3sup gcp_get_credentials
  export SCRIPT_DIR="scripts"
  _GCP_ZONE="us-central1-a"
  _GCP_INSTANCE_NAME="k3s-gcp-server"
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
