#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
  PLUGINS_DIR="$BATS_TEST_TMPDIR/plugins"
  mkdir -p "$PLUGINS_DIR"
  
  # Mock primitives used by vault.sh during sourcing
  # We want the real _err behavior (exit 1) for the 'run' command to capture status
  _err() { 
     printf 'ERROR: %s\n' "$*" >&2
     exit 1
  }
  _warn() { printf 'WARN: %s\n' "$*" >&2; }
  _info() { printf 'INFO: %s\n' "$*" >&2; }
  export -f _err _warn _info

  # Create dummy dependency files so sourcing vault.sh doesn't fail
  touch "$PLUGINS_DIR/eso.sh"
  mkdir -p "$SCRIPT_DIR/lib"
  touch "$SCRIPT_DIR/lib/vault_pki.sh"
  
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/plugins/vault.sh"

  KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
  VAULT_EXEC_LOG="$BATS_TEST_TMPDIR/vault_exec.log"
  VAULT_EXEC_STREAM_LOG="$BATS_TEST_TMPDIR/vault_exec_stream.log"
  : >"$KUBECTL_LOG"
  : >"$VAULT_EXEC_LOG"
  : >"$VAULT_EXEC_STREAM_LOG"

  _kubectl() {
    # Skip options
    local pre=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--quiet|--prefer-sudo|--require-sudo) pre+=("$1"); shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    echo "kubectl $*" >>"$KUBECTL_LOG"
    return 0
  }

  # Override functions defined in vault.sh for testing
  _vault_exec() {
    echo "vault_exec $*" >>"$VAULT_EXEC_LOG"
    return 0
  }

  _vault_exec_stream() {
    local kflags=()
    local pod_override=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--prefer-sudo|--require-sudo) kflags+=("$1"); shift ;;
        --pod) pod_override="${2:-}"; shift 2 ;;
        --pod=*) pod_override="${1#*=}"; shift ;;
        *) break ;;
      esac
    done
    echo "vault_exec_stream --pod $pod_override $*" >>"$VAULT_EXEC_STREAM_LOG"
    # Capture stdin if possible (bats 'run' can pipe to this mock)
    cat >> "$VAULT_EXEC_STREAM_LOG"
    return 0
  }

  _vault_login() {
    echo "vault_login $*" >>"$VAULT_EXEC_LOG"
    return 0
  }

  _vault_policy_exists_val=1
  _vault_policy_exists() {
    echo "vault_policy_exists $*" >>"$VAULT_EXEC_LOG"
    return $_vault_policy_exists_val
  }

  export -f _kubectl
  export -f _vault_exec
  export -f _vault_exec_stream
  export -f _vault_login
  export -f _vault_policy_exists

  # Test defaults
  export VAULT_NS_DEFAULT="secrets"
  export VAULT_RELEASE_DEFAULT="vault"
}

@test "configure_vault_app_auth exits 1 when APP_CLUSTER_API_URL is unset" {
  unset APP_CLUSTER_API_URL
  export APP_CLUSTER_CA_CERT_PATH="/tmp/fake-ca.crt"
  touch "$APP_CLUSTER_CA_CERT_PATH"
  run configure_vault_app_auth
  [ "$status" -eq 1 ]
  [[ "$output" == *"APP_CLUSTER_API_URL is required"* ]]
}

@test "configure_vault_app_auth exits 1 when APP_CLUSTER_CA_CERT_PATH is unset" {
  export APP_CLUSTER_API_URL="https://1.2.3.4:6443"
  unset APP_CLUSTER_CA_CERT_PATH
  run configure_vault_app_auth
  [ "$status" -eq 1 ]
  [[ "$output" == *"APP_CLUSTER_CA_CERT_PATH is required"* ]]
}

@test "configure_vault_app_auth exits 1 when CA cert file missing" {
  export APP_CLUSTER_API_URL="https://1.2.3.4:6443"
  export APP_CLUSTER_CA_CERT_PATH="/tmp/non-existent-ca.crt"
  run configure_vault_app_auth
  [ "$status" -eq 1 ]
  [[ "$output" == *"app cluster CA cert file not found"* ]]
}

@test "configure_vault_app_auth calls vault commands with correct args" {
  export APP_CLUSTER_API_URL="https://10.211.55.14:6443"
  export APP_CLUSTER_CA_CERT_PATH="$BATS_TEST_TMPDIR/app-ca.crt"
  touch "$APP_CLUSTER_CA_CERT_PATH"
  
  export APP_K8S_AUTH_MOUNT="custom-mount"
  export APP_ESO_VAULT_ROLE="custom-role"
  export APP_ESO_SA_NAME="custom-sa"
  export APP_ESO_SA_NS="custom-ns"

  # Mock policy not existing
  _vault_policy_exists_val=1

  run configure_vault_app_auth
  [ "$status" -eq 0 ]

  # Verify kubectl cp
  grep -q "kubectl -n secrets cp $APP_CLUSTER_CA_CERT_PATH vault-0:/tmp/app-cluster-ca.crt" "$KUBECTL_LOG"

  # Verify vault auth enable
  grep -q "vault_exec secrets vault auth enable -path=custom-mount kubernetes vault" "$VAULT_EXEC_LOG"

  # Verify vault write config
  grep -q "vault_exec secrets vault write auth/custom-mount/config" "$VAULT_EXEC_LOG"
  grep -q "kubernetes_host=https://10.211.55.14:6443" "$VAULT_EXEC_LOG"
  grep -q "disable_local_ca_jwt=true" "$VAULT_EXEC_LOG"

  # Verify eso-reader policy ensure
  grep -q "vault_policy_exists secrets vault eso-reader" "$VAULT_EXEC_LOG"
  grep -q "vault_exec_stream --pod vault-0 secrets vault -- vault policy write eso-reader -" "$VAULT_EXEC_STREAM_LOG"
  grep -q "path \"secret/data/eso/\*\"      { capabilities = \[\"read\"\] }" "$VAULT_EXEC_STREAM_LOG"

  # Verify vault write role
  grep -q "vault_exec secrets vault write auth/custom-mount/role/custom-role" "$VAULT_EXEC_LOG"
  grep -q "bound_service_account_names=custom-sa" "$VAULT_EXEC_LOG"
  grep -q "bound_service_account_namespaces=custom-ns" "$VAULT_EXEC_LOG"
  grep -q "policies=eso-reader" "$VAULT_EXEC_LOG"
}

@test "configure_vault_app_auth skips policy creation if it exists" {
  export APP_CLUSTER_API_URL="https://10.211.55.14:6443"
  export APP_CLUSTER_CA_CERT_PATH="$BATS_TEST_TMPDIR/app-ca.crt"
  touch "$APP_CLUSTER_CA_CERT_PATH"

  # Mock policy existing
  _vault_policy_exists_val=0

  run configure_vault_app_auth
  [ "$status" -eq 0 ]

  grep -q "vault_policy_exists secrets vault eso-reader" "$VAULT_EXEC_LOG"
  ! grep -q "vault policy write eso-reader" "$VAULT_EXEC_STREAM_LOG"
}

@test "configure_vault_app_auth is idempotent" {
  export APP_CLUSTER_API_URL="https://10.211.55.14:6443"
  export APP_CLUSTER_CA_CERT_PATH="$BATS_TEST_TMPDIR/app-ca.crt"
  touch "$APP_CLUSTER_CA_CERT_PATH"

  # First run
  run configure_vault_app_auth
  [ "$status" -eq 0 ]

  # Second run
  run configure_vault_app_auth
  [ "$status" -eq 0 ]
}
