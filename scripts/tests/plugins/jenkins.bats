#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/jenkins.sh"
  export_stubs
  K3D_LOG="$BATS_TEST_TMPDIR/k3d.log"
  : > "$K3D_LOG"
  _k3d() { echo "$*" >> "$K3D_LOG"; }
  export K3D_LOG
  export -f _k3d
  MINIMAL_JQ_HELPER="${BATS_TEST_DIRNAME}/minimal_jq.py"
  export MINIMAL_JQ_HELPER
  SYSTEM_JQ_CMD="${SYSTEM_JQ_CMD:-$(command -v jq || true)}"
  export SYSTEM_JQ_CMD
}

@test "Jenkins trap wrapper preserves original script arguments" {
  local helper="${BATS_TEST_DIRNAME}/../test_helpers.bash"
  local plugin="${BATS_TEST_DIRNAME}/../../plugins/jenkins.sh"
  local script="$BATS_TEST_TMPDIR/trap-wrapper.sh"
  local record="$BATS_TEST_TMPDIR/trap-args.log"

  cat <<'EOF' >"$script"
#!/usr/bin/env bash
set -euo pipefail

helper="$HELPER"
plugin="$PLUGIN"
record="$RECORD"

source "$helper"
init_test_env
source "$plugin"
export_stubs

: >"$record"

record_trap_args() {
  {
    printf 'argc=%s\n' "$#"
    printf 'args=%s\n' "$*"
    printf 'first=%s\n' "${1-}"
  } >>"$record"
}

trap 'record_trap_args "$@"' EXIT

_jenkins_capture_trap_state EXIT _JENKINS_PREV_EXIT_TRAP_CMD _JENKINS_PREV_EXIT_TRAP_HANDLER

exit_trap_cmd="_jenkins_cleanup_rendered_manifests EXIT"
if [[ -n "$_JENKINS_PREV_EXIT_TRAP_HANDLER" ]]; then
  exit_trap_cmd+="; _jenkins_run_saved_trap_literal EXIT ${_JENKINS_PREV_EXIT_TRAP_HANDLER} \"\$@\""
fi
trap "$exit_trap_cmd" EXIT

exit 0
EOF

  chmod +x "$script"

  BATS_TEST_DIRNAME="$BATS_TEST_DIRNAME" \
    BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" \
    HELPER="$helper" \
    PLUGIN="$plugin" \
    RECORD="$record" \
    "$script" arg-one arg-two

  read_lines "$record" trap_lines
  [ "${trap_lines[0]}" = "argc=2" ]
  [ "${trap_lines[1]}" = "args=arg-one arg-two" ]
  [ "${trap_lines[2]}" = "first=arg-one" ]
  [[ "${trap_lines[*]}" != *"_JENKINS_PREV_EXIT_TRAP_CMD"* ]]
}

@test "deploy_jenkins -h shows usage" {
  run deploy_jenkins -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_jenkins"* ]]
}

@test "_jenkins_configure_leaf_host_defaults picks sslip host for WSL k3s" {
  _is_wsl() { return 0; }
  export -f _is_wsl
  : >"$KUBECTL_LOG"
  unset VAULT_PKI_LEAF_HOST
  export CLUSTER_PROVIDER="k3s"
  export JENKINS_WSL_NODE_IP="198.51.100.27"

  _jenkins_configure_leaf_host_defaults

  [ "$VAULT_PKI_LEAF_HOST" = "jenkins.198.51.100.27.sslip.io" ]
  unset JENKINS_WSL_NODE_IP
  unset -f _is_wsl
  unset CLUSTER_PROVIDER
}

@test "_jenkins_configure_leaf_host_defaults leaves unset when not on WSL" {
  unset VAULT_PKI_LEAF_HOST
  export CLUSTER_PROVIDER="k3s"

  _jenkins_configure_leaf_host_defaults

  [ -z "${VAULT_PKI_LEAF_HOST:-}" ]
  unset CLUSTER_PROVIDER
}


@test "Namespace creation" {
  KUBECTL_EXIT_CODES=(1 0)
  run _create_jenkins_namespace test-ns
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" kubectl_calls
  [[ "${kubectl_calls[1]}" == apply* ]]
  [[ "$output" == *"Namespace test-ns created"* ]]
}

@test "PV/PVC setup" {
  KUBECTL_EXIT_CODES=(1 0)
  local jhp="$BATS_TEST_TMPDIR/jenkins_home"
  export JENKINS_HOME_PATH="$jhp"
  rm -rf "$jhp"
  CLUSTER_NAME="testcluster"
  export CLUSTER_NAME
  local mount_check_log="$BATS_TEST_TMPDIR/mount-check.log"
  : >"$mount_check_log"
  _jenkins_require_hostpath_mounts() {
    echo "$1" >"$MOUNT_CHECK_LOG"
    mkdir -p "$JENKINS_HOME_PATH"
    return 0
  }
  export MOUNT_CHECK_LOG="$mount_check_log"
  export -f _jenkins_require_hostpath_mounts
  run _create_jenkins_pv_pvc test-ns
  [ "$status" -eq 0 ]
  [[ -d "$jhp" ]]
  read_lines "$KUBECTL_LOG" kubectl_calls
  [ "${#kubectl_calls[@]}" -eq 1 ]
  [[ "${kubectl_calls[0]}" == apply* ]]
  read_lines "$mount_check_log" mount_calls
  [ "${mount_calls[0]}" = "$CLUSTER_NAME" ]
}

@test "_jenkins_require_hostpath_mounts omits cluster flag when listing nodes" {
  : >"$K3D_LOG"
  local cluster="testcluster"
  _k3d() {
    local cmd="$*"
    echo "$cmd" >> "$K3D_LOG"
    if [[ "$cmd" == *"node list"* ]]; then
      cat <<'EOF'
NAME   ROLE    CLUSTER   STATUS
k3d-testcluster-server-0   server  testcluster   running
k3d-testcluster-agent-0    agent   testcluster   running
k3d-other-server-0         server  other        running
EOF
    fi
  }
  _jenkins_node_has_mount() { return 0; }
  export -f _k3d
  export -f _jenkins_node_has_mount

  run _jenkins_require_hostpath_mounts "$cluster"
  [ "$status" -eq 0 ]

  read_lines "$K3D_LOG" k3d_calls
  [ "${#k3d_calls[@]}" -ge 1 ]
  [[ "${k3d_calls[0]}" == *"node list"* ]]
  [[ "${k3d_calls[0]}" != *"--cluster"* ]]
}

@test "PV/PVC setup auto-detects cluster" {
  KUBECTL_EXIT_CODES=(1 0)
  local jhp="$BATS_TEST_TMPDIR/jenkins_home"
  export JENKINS_HOME_PATH="$jhp"
  rm -rf "$jhp"
  unset CLUSTER_NAME
  local mount_check_log="$BATS_TEST_TMPDIR/mount-check.log"
  : >"$mount_check_log"
  _jenkins_require_hostpath_mounts() {
    echo "$1" >"$MOUNT_CHECK_LOG"
    mkdir -p "$JENKINS_HOME_PATH"
    return 0
  }
  export MOUNT_CHECK_LOG="$mount_check_log"
  export -f _jenkins_require_hostpath_mounts
  _k3d() {
    local cmd="$*"
    echo "$cmd" >> "$K3D_LOG"
    if [[ "$cmd" == *"cluster list"* ]]; then
      cat <<'EOF'
NAME   SERVERS   AGENTS   LOADBALANCER
k3d-auto   1/1       1/1      true
EOF
    fi
  }
  export -f _k3d

  run _create_jenkins_pv_pvc test-ns
  [ "$status" -eq 0 ]
  [[ -d "$jhp" ]]
  read_lines "$K3D_LOG" k3d_calls
  [ "${#k3d_calls[@]}" -eq 1 ]
  [[ "${k3d_calls[0]}" == *"cluster list"* ]]
  read_lines "$mount_check_log" mount_calls
  [ "${mount_calls[0]}" = "k3d-auto" ]
}

@test "PV/PVC setup aborts when Jenkins mount missing" {
  KUBECTL_EXIT_CODES=(1)
  local jhp="$BATS_TEST_TMPDIR/jenkins_home"
  export JENKINS_HOME_PATH="$jhp"
  rm -rf "$jhp"
  CLUSTER_NAME="broken"
  export CLUSTER_NAME
  _jenkins_require_hostpath_mounts() {
    JENKINS_MISSING_HOSTPATH_NODES="broken-agent"
    return 1
  }
  export -f _jenkins_require_hostpath_mounts

  run --separate-stderr _create_jenkins_pv_pvc test-ns
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"hostPath mount"* ]]
  [[ "$stderr" == *"broken-agent"* ]]
  [[ "$stderr" == *"Update your cluster configuration"* ]]
  [[ "$stderr" == *"create_cluster"* ]]
  read_lines "$KUBECTL_LOG" kubectl_calls
  [ "${#kubectl_calls[@]}" -eq 0 ]
}

@test "_create_jenkins_admin_vault_policy stores secret without logging password" {
  _vault_policy_exists() { return 1; }
  _vault_login() { echo "_vault_login" >> "$KUBECTL_LOG"; return 0; }
  export -f _vault_login

  # Mock secret backend functions
  secret_backend_init() { echo "secret_backend_init" >> "$KUBECTL_LOG"; return 0; }
  secret_backend_exists() { echo "secret_backend_exists $*" >> "$KUBECTL_LOG"; return 1; }
  secret_backend_put() {
    local args="$*"
    if [[ "$args" == *password=* ]]; then
      args="${args%%password=*}password=***"
    fi
    echo "secret_backend_put $args" >> "$KUBECTL_LOG"
    return 0
  }
  export -f secret_backend_init
  export -f secret_backend_exists
  export -f secret_backend_put

  _kubectl() {
    local cmd="$*"
    if [[ "$cmd" == *"vault kv get"* ]]; then
      echo "$cmd" >> "$KUBECTL_LOG"
      return 1
    fi
    if [[ "$cmd" == *"vault read -field=password sys/policies/password/jenkins-admin/generate"* ]]; then
      echo "$cmd" >> "$KUBECTL_LOG"
      echo "s3cr3t"
      return 0
    fi
    if [[ "$cmd" == *password=* ]]; then
      cmd="${cmd%%password=*}password=***"
    fi
    echo "$cmd" >> "$KUBECTL_LOG"
    return 0
  }
  export -f _vault_policy_exists
  export -f _kubectl

  _vault_exec() {
    local ns="$1" cmd="$2" release="$3"
    echo "_vault_exec $cmd" >> "$KUBECTL_LOG"
    if [[ "$cmd" == *"vault read -field=password sys/policies/password/jenkins-admin/generate"* ]]; then
      echo "s3cr3t"
      return 0
    fi
    return 0
  }
  export -f _vault_exec

  _no_trace() {
    _vault_exec "$@"
  }
  export -f _no_trace

  _cleanup_on_success() { rm -f "$1"; }
  export -f _cleanup_on_success

  run _create_jenkins_admin_vault_policy vault
  [ "$status" -eq 0 ]
  grep -q 'secret_backend_put' "$KUBECTL_LOG"
  grep -q 'username=jenkins-admin' "$KUBECTL_LOG"
  grep -Fq 'password=***' "$KUBECTL_LOG"
  ! grep -q 's3cr3t' "$KUBECTL_LOG"
  [[ ! -f jenkins-admin.hcl ]]
}

@test "_create_jenkins_vault_ad_policy creates policies" {
  _vault_policy_exists() { return 1; }
  _vault_policy() { return 1; }
  _vault_login() { return 0; }
  export -f _vault_login

  local VAULT_EXEC_LOG="$BATS_TEST_TMPDIR/vault-exec-ad-policy.log"
  : >"$VAULT_EXEC_LOG"
  export VAULT_EXEC_LOG

  _vault_exec() {
    local ns="$1"
    local cmd="$2"
    local release="$3"
    echo "$cmd" >> "$VAULT_EXEC_LOG"
    if [[ -p /dev/stdin ]]; then
      cat >/dev/null
    fi
    return 0
  }

  export -f _vault_policy_exists
  export -f _vault_policy
  export -f _vault_exec

  run _create_jenkins_vault_ad_policy vault jenkins
  [ "$status" -eq 0 ]
  grep -q 'vault policy write jenkins-jcasc-read' "$VAULT_EXEC_LOG"
  grep -q 'vault write auth/kubernetes/role/jenkins-jcasc-reader' "$VAULT_EXEC_LOG"
  grep -q 'vault policy write jenkins-jcasc-write' "$VAULT_EXEC_LOG"
  grep -q 'vault write auth/kubernetes/role/jenkins-jcasc-writer' "$VAULT_EXEC_LOG"
  ! grep -q 'vault kv put' "$VAULT_EXEC_LOG"
  ! grep -q 'password=' "$VAULT_EXEC_LOG"
}

@test "_create_jenkins_cert_rotator_policy writes role without stdin dash" {
  _vault_policy_exists() { return 1; }
  _vault_login() { return 0; }
  export -f _vault_policy_exists
  export -f _vault_login

  local policy_capture="$BATS_TEST_TMPDIR/jenkins-cert-rotator.hcl"
  : >"$policy_capture"

  local VAULT_EXEC_LOG="$BATS_TEST_TMPDIR/vault-exec-commands.log"
  : >"$VAULT_EXEC_LOG"
  export VAULT_EXEC_LOG

  _vault_exec() {
    # Skip --no-exit flag if present
    if [[ "$1" == "--no-exit" ]]; then
      shift
    fi

    local ns="$1"
    local cmd="$2"
    local release="$3"

    echo "$cmd" >> "$VAULT_EXEC_LOG"

    if [[ "$cmd" == *"vault policy write jenkins-cert-rotator -"* ]]; then
      cat >>"$policy_capture"
      return 0
    fi

    if [[ -p /dev/stdin ]]; then
      cat >/dev/null
    fi

    return 0
  }
  export POLICY_CAPTURE="$policy_capture"
  export -f _vault_exec

  VAULT_PKI_SECRET_NS="secret-ns" \
    run _create_jenkins_cert_rotator_policy vault-ns vault-release custom-pki custom-role jenkins-ns rotator-sa
  [ "$status" -eq 0 ]

  read_lines "$VAULT_EXEC_LOG" vault_calls

  local role_write_line=""
  local policy_write_count=0
  for line in "${vault_calls[@]}"; do
    if [[ "$line" == *"vault write auth/kubernetes/role/jenkins-cert-rotator"* ]]; then
      role_write_line="$line"
    fi
    if [[ "$line" == *"vault policy write jenkins-cert-rotator -"* ]]; then
      ((policy_write_count += 1))
    fi
  done

  [ -n "$role_write_line" ]
  [[ "$role_write_line" != *"jenkins-cert-rotator -"* ]]
  [[ "$role_write_line" == *"bound_service_account_names=rotator-sa"* ]]
  [[ "$role_write_line" == *"bound_service_account_namespaces=jenkins-ns"* ]]
  [[ "$role_write_line" != *"secret-ns"* ]]
  [[ "$role_write_line" == *"policies=jenkins-cert-rotator"* ]]
  [ "$policy_write_count" -eq 1 ]

  local policy_text
  policy_text=$(cat "$policy_capture")
  [[ "$policy_text" == *"path \"custom-pki/issue/custom-role\""*  ]]
  [[ "$policy_text" == *"path \"custom-pki/revoke\""*  ]]
  [[ "$policy_text" == *"capabilities = [\"update\"]"*  ]]
  grep -q 'path "custom-pki/revoke"' "$policy_capture"
}

@test "_create_jenkins_cert_rotator_policy refreshes policy missing revoke grant" {
  _vault_policy_exists() { return 0; }
  _vault_login() { return 0; }
  export -f _vault_policy_exists
  export -f _vault_login

  local policy_capture="$BATS_TEST_TMPDIR/jenkins-cert-rotator-refresh.hcl"
  : >"$policy_capture"

  local VAULT_EXEC_LOG="$BATS_TEST_TMPDIR/vault-exec-commands.log"
  : >"$VAULT_EXEC_LOG"
  export VAULT_EXEC_LOG

  _vault_exec() {
    # Skip --no-exit flag if present
    if [[ "$1" == "--no-exit" ]]; then
      shift
    fi

    local ns="$1"
    local cmd="$2"
    local release="$3"

    echo "$cmd" >> "$VAULT_EXEC_LOG"

    if [[ "$cmd" == *"vault policy read jenkins-cert-rotator"* ]]; then
      cat <<'HCL'
path "custom-pki/issue/custom-role" {
  capabilities = ["update"]
}
path "custom-pki/roles/custom-role" {
  capabilities = ["read"]
}
path "custom-pki/cert/ca" {
  capabilities = ["read"]
}
path "custom-pki/ca/pem" {
  capabilities = ["read"]
}
HCL
      return 0
    fi

    if [[ "$cmd" == *"vault policy write jenkins-cert-rotator -"* ]]; then
      cat >>"$policy_capture"
      return 0
    fi

    if [[ -p /dev/stdin ]]; then
      cat >/dev/null
    fi

    return 0
  }
  export -f _vault_exec

  run _create_jenkins_cert_rotator_policy vault-ns vault-release custom-pki custom-role jenkins-ns rotator-sa
  [ "$status" -eq 0 ]

  read_lines "$VAULT_EXEC_LOG" vault_calls

  local policy_write_count=0
  local policy_read_count=0
  for line in "${vault_calls[@]}"; do
    if [[ "$line" == *"vault policy write jenkins-cert-rotator -"* ]]; then
      ((policy_write_count += 1))
    fi
    if [[ "$line" == *"vault policy read jenkins-cert-rotator"* ]]; then
      ((policy_read_count += 1))
    fi
  done

  [ "$policy_write_count" -eq 1 ]
  [ "$policy_read_count" -eq 1 ]
  grep -q 'path "custom-pki/revoke"' "$policy_capture"
}

@test "_ensure_jenkins_cert sets up PKI and TLS secret" {
  local VAULT_EXEC_LOG="$BATS_TEST_TMPDIR/vault-exec-cert.log"
  : >"$VAULT_EXEC_LOG"
  export VAULT_EXEC_LOG

  _vault_exec() {
    # Skip --no-exit flag if present
    if [[ "$1" == "--no-exit" ]]; then
      shift
    fi
    local ns="$1"
    local cmd="$2"
    local release="$3"
    echo "$cmd" >> "$VAULT_EXEC_LOG"

    if [[ "$cmd" == "vault secrets list" ]]; then
      # Return empty to simulate PKI not enabled
      return 1
    fi
    if [[ "$cmd" == *"vault write -format=json pki/issue/jenkins"* ]]; then
      cat <<'JSON'
{"data":{"certificate":"CERT","private_key":"KEY"}}
JSON
      return 0
    fi
    return 0
  }
  export -f _vault_exec

  _kubectl() {
    local cmd="$*"
    echo "$cmd" >> "$KUBECTL_LOG"
    local secret_name="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
    if [[ "$cmd" == *"get secret ${secret_name}"* ]]; then
      return 1
    fi
    return 0
  }
  export -f _kubectl

  export VAULT_PKI_LEAF_HOST="jenkins.192.168.0.1.sslip.io"
  unset VAULT_PKI_ALLOWED

  run _ensure_jenkins_cert vault
  [ "$status" -eq 0 ]
  grep -q 'vault secrets enable pki' "$VAULT_EXEC_LOG"
  grep -Fq 'vault write pki/roles/jenkins allowed_domains=sslip.io allow_subdomains=true max_ttl=72h' "$VAULT_EXEC_LOG"
  grep -q 'vault write -format=json pki/issue/jenkins' "$VAULT_EXEC_LOG"
  local secret_name="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
  grep -q "create secret tls ${secret_name}" "$KUBECTL_LOG"
}

@test "_ensure_jenkins_cert honors VAULT_PKI_ALLOWED for wildcard domains" {
  local VAULT_EXEC_LOG="$BATS_TEST_TMPDIR/vault-exec-wildcard.log"
  : >"$VAULT_EXEC_LOG"
  export VAULT_EXEC_LOG

  _vault_exec() {
    # Skip --no-exit flag if present
    if [[ "$1" == "--no-exit" ]]; then
      shift
    fi
    local ns="$1"
    local cmd="$2"
    local release="$3"
    echo "$cmd" >> "$VAULT_EXEC_LOG"

    if [[ "$cmd" == "vault secrets list" ]]; then
      # Return empty to simulate PKI not enabled
      return 1
    fi
    if [[ "$cmd" == *"vault write -format=json pki/issue/jenkins"* ]]; then
      cat <<'JSON'
{"data":{"certificate":"CERT","private_key":"KEY"}}
JSON
      return 0
    fi
    return 0
  }
  export -f _vault_exec

  _kubectl() {
    local cmd="$*"
    echo "$cmd" >> "$KUBECTL_LOG"
    local secret_name="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
    if [[ "$cmd" == *"get secret ${secret_name}"* ]]; then
      return 1
    fi
    return 0
  }
  export -f _kubectl

  export VAULT_PKI_ALLOWED="jenkins.dev.local.me,*.dev.local.me"

  run _ensure_jenkins_cert vault
  [ "$status" -eq 0 ]
  grep -Fq 'allowed_domains=jenkins.dev.local.me,*.dev.local.me' "$VAULT_EXEC_LOG"
  grep -Fq 'max_ttl=72h' "$VAULT_EXEC_LOG"
  ! grep -q 'allow_subdomains=' "$VAULT_EXEC_LOG"
  unset VAULT_PKI_ALLOWED
}

@test "cert rotator honors kubectl directory override" {
  local cert_file="$BATS_TEST_TMPDIR/dir-override.crt"
  local key_file="$BATS_TEST_TMPDIR/dir-override.key"
  create_self_signed_cert "$cert_file" "$key_file" 0xAC1D

  local cert_b64
  cert_b64=$(base64 <"$cert_file" | tr -d '\n')
  local secret_json="$BATS_TEST_TMPDIR/dir-override-secret.json"
  cat <<JSON >"$secret_json"
{"data":{"tls.crt":"$cert_b64"}}
JSON

  local override_dir="$BATS_TEST_TMPDIR/override"
  mkdir -p "$override_dir"
  local kubectl_log="$BATS_TEST_TMPDIR/dir-override-kubectl.log"
  : >"$kubectl_log"

  cat <<'SCRIPT' >"$override_dir/kubectl"
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"$CERT_ROTATOR_KUBECTL_LOG"
if [[ "$1" == "-n" && "$3" == "get" && "$4" == "secret" ]]; then
  if [[ "${CERT_ROTATOR_HAS_SECRET:-0}" == "1" ]]; then
    cat "$CERT_ROTATOR_SECRET_JSON"
    exit 0
  else
    exit 1
  fi
elif [[ "$1" == "apply" && "$2" == "-f" ]]; then
  exit 0
fi
exit 0
SCRIPT
  chmod +x "$override_dir/kubectl"

  local fakebin="$BATS_TEST_TMPDIR/dir-override-fakebin"
  mkdir -p "$fakebin"
  local curl_log="$BATS_TEST_TMPDIR/dir-override-curl.log"
  : >"$curl_log"

  cat <<'SCRIPT' >"$fakebin/curl"
#!/usr/bin/env bash
set -euo pipefail
method=""
data=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --request)
      method="$2"
      shift 2
      ;;
    --data)
      data="$2"
      shift 2
      ;;
    --header)
      shift 2
      ;;
    --silent|--show-error|--fail|-k)
      shift
      ;;
    --cacert)
      shift 2
      ;;
    *)
      break
      ;;
  esac
done
url="$1"
echo "${method:-GET} ${url} ${data}" >>"$CERT_ROTATOR_CURL_LOG"
if [[ "$url" == *"/auth/kubernetes/login" ]]; then
  printf '{"auth":{"client_token":"dir-token"}}\n'
elif [[ "$url" == *"/issue/"* ]]; then
  printf '{"data":{"certificate":"DIR_CERT","private_key":"DIR_KEY","issuing_ca":"DIR_CA"}}\n'
else
  printf '{}\n'
fi
SCRIPT
  chmod +x "$fakebin/curl"

  cat <<'SCRIPT' >"$fakebin/jq"
#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${SYSTEM_JQ_CMD:-}" ]]; then
    echo "SYSTEM_JQ_CMD not set" >&2
    exit 127
  fi
  exec "${SYSTEM_JQ_CMD}" "$@"
SCRIPT
  chmod +x "$fakebin/jq"

  export PATH="$fakebin:/usr/bin:/bin"
  ! command -v kubectl >/dev/null 2>&1

  export CERT_ROTATOR_KUBECTL_LOG="$kubectl_log"
  export CERT_ROTATOR_CURL_LOG="$curl_log"
  export CERT_ROTATOR_HAS_SECRET=1
  export CERT_ROTATOR_SECRET_JSON="$secret_json"

  local token_file="$BATS_TEST_TMPDIR/dir-override-token"
  printf 'dir-token' >"$token_file"

  export VAULT_ADDR="http://vault.example:8200"
  export VAULT_PKI_ROLE="jenkins"
  export VAULT_PKI_SECRET_NS="jenkins"
  export VAULT_PKI_SECRET_NAME="jenkins-tls"
  export JENKINS_CERT_ROTATOR_VAULT_ROLE="jenkins-role"
  export SERVICE_ACCOUNT_TOKEN_FILE="$token_file"
  export VAULT_PKI_LEAF_HOST="dir.example"
  export JENKINS_CERT_ROTATOR_KUBECTL_BIN="$override_dir"

  run bash scripts/etc/jenkins/cert-rotator.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated TLS secret"* ]]
  [[ "$output" != *"Required command 'kubectl'"* ]]

  read_lines "$kubectl_log" kubectl_calls
  [ "${#kubectl_calls[@]}" -ge 2 ]
  [[ "${kubectl_calls[0]}" == "-n jenkins get secret jenkins-tls -o json" ]]
  printf '%s\n' "${kubectl_calls[@]}" | grep -Fq 'apply -f '
}

@test "cert rotator honors kubectl command override" {
  local cert_file="$BATS_TEST_TMPDIR/cmd-override.crt"
  local key_file="$BATS_TEST_TMPDIR/cmd-override.key"
  create_self_signed_cert "$cert_file" "$key_file" 0xAC1E

  local cert_b64
  cert_b64=$(base64 <"$cert_file" | tr -d '\n')
  local secret_json="$BATS_TEST_TMPDIR/cmd-override-secret.json"
  cat <<JSON >"$secret_json"
{"data":{"tls.crt":"$cert_b64"}}
JSON

  local fakebin="$BATS_TEST_TMPDIR/cmd-override-fakebin"
  mkdir -p "$fakebin"
  local kubectl_log="$BATS_TEST_TMPDIR/cmd-override-kubectl.log"
  : >"$kubectl_log"

  cat <<'SCRIPT' >"$fakebin/kubectl"
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"$CERT_ROTATOR_KUBECTL_LOG"
if [[ "$1" == "-n" && "$3" == "get" && "$4" == "secret" ]]; then
  if [[ "${CERT_ROTATOR_HAS_SECRET:-0}" == "1" ]]; then
    cat "$CERT_ROTATOR_SECRET_JSON"
    exit 0
  else
    exit 1
  fi
elif [[ "$1" == "apply" && "$2" == "-f" ]]; then
  exit 0
fi
exit 0
SCRIPT
  chmod +x "$fakebin/kubectl"

  local curl_log="$BATS_TEST_TMPDIR/cmd-override-curl.log"
  : >"$curl_log"

  cat <<'SCRIPT' >"$fakebin/curl"
#!/usr/bin/env bash
set -euo pipefail
method=""
data=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --request)
      method="$2"
      shift 2
      ;;
    --data)
      data="$2"
      shift 2
      ;;
    --header)
      shift 2
      ;;
    --silent|--show-error|--fail|-k)
      shift
      ;;
    --cacert)
      shift 2
      ;;
    *)
      break
      ;;
  esac
done
url="$1"
echo "${method:-GET} ${url} ${data}" >>"$CERT_ROTATOR_CURL_LOG"
if [[ "$url" == *"/auth/kubernetes/login" ]]; then
  printf '{"auth":{"client_token":"cmd-token"}}\n'
elif [[ "$url" == *"/issue/"* ]]; then
  printf '{"data":{"certificate":"CMD_CERT","private_key":"CMD_KEY","issuing_ca":"CMD_CA"}}\n'
else
  printf '{}\n'
fi
SCRIPT
  chmod +x "$fakebin/curl"

  cat <<'SCRIPT' >"$fakebin/jq"
#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${SYSTEM_JQ_CMD:-}" ]]; then
    echo "SYSTEM_JQ_CMD not set" >&2
    exit 127
  fi
  exec "${SYSTEM_JQ_CMD}" "$@"
SCRIPT
  chmod +x "$fakebin/jq"

  export PATH="$fakebin:/usr/bin:/bin"

  export CERT_ROTATOR_KUBECTL_LOG="$kubectl_log"
  export CERT_ROTATOR_CURL_LOG="$curl_log"
  export CERT_ROTATOR_HAS_SECRET=1
  export CERT_ROTATOR_SECRET_JSON="$secret_json"

  local token_file="$BATS_TEST_TMPDIR/cmd-override-token"
  printf 'cmd-token' >"$token_file"

  export VAULT_ADDR="http://vault.example:8200"
  export VAULT_PKI_ROLE="jenkins"
  export VAULT_PKI_SECRET_NS="jenkins"
  export VAULT_PKI_SECRET_NAME="jenkins-tls"
  export JENKINS_CERT_ROTATOR_VAULT_ROLE="jenkins-role"
  export SERVICE_ACCOUNT_TOKEN_FILE="$token_file"
  export VAULT_PKI_LEAF_HOST="cmd.example"
  export JENKINS_CERT_ROTATOR_KUBECTL_BIN="kubectl"
  unset JENKINS_CERT_ROTATOR_KUBECTL_PATHS

  run bash scripts/etc/jenkins/cert-rotator.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated TLS secret"* ]]
  [[ "$output" != *"Required command 'kubectl'"* ]]

  read_lines "$kubectl_log" kubectl_calls
  [ "${#kubectl_calls[@]}" -ge 2 ]
  [[ "${kubectl_calls[0]}" == "-n jenkins get secret jenkins-tls -o json" ]]
  printf '%s\n' "${kubectl_calls[@]}" | grep -Fq 'apply -f '
}

@test "cert rotator locates kubectl via fallback search paths" {
  local cert_file="$BATS_TEST_TMPDIR/fallback.crt"
  local key_file="$BATS_TEST_TMPDIR/fallback.key"
  create_self_signed_cert "$cert_file" "$key_file" 0xBEEF

  local cert_b64
  cert_b64=$(base64 <"$cert_file" | tr -d '\n')
  local secret_json="$BATS_TEST_TMPDIR/fallback-secret.json"
  cat <<JSON >"$secret_json"
{"data":{"tls.crt":"$cert_b64"}}
JSON

  local fallback_dir="$BATS_TEST_TMPDIR/cloud-sdk/bin"
  mkdir -p "$fallback_dir"
  local kubectl_log="$BATS_TEST_TMPDIR/fallback-kubectl.log"
  : >"$kubectl_log"

  cat <<'SCRIPT' >"$fallback_dir/kubectl"
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"$CERT_ROTATOR_KUBECTL_LOG"
if [[ "$1" == "-n" && "$3" == "get" && "$4" == "secret" ]]; then
  if [[ "${CERT_ROTATOR_HAS_SECRET:-0}" == "1" ]]; then
    cat "$CERT_ROTATOR_SECRET_JSON"
    exit 0
  else
    exit 1
  fi
elif [[ "$1" == "apply" && "$2" == "-f" ]]; then
  exit 0
fi
exit 0
SCRIPT
  chmod +x "$fallback_dir/kubectl"

  local fakebin="$BATS_TEST_TMPDIR/fallback-fakebin"
  mkdir -p "$fakebin"
  local curl_log="$BATS_TEST_TMPDIR/fallback-curl.log"
  : >"$curl_log"

  cat <<'SCRIPT' >"$fakebin/curl"
#!/usr/bin/env bash
set -euo pipefail
method=""
data=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --request)
      method="$2"
      shift 2
      ;;
    --data)
      data="$2"
      shift 2
      ;;
    --header)
      shift 2
      ;;
    --silent|--show-error|--fail|-k)
      shift
      ;;
    --cacert)
      shift 2
      ;;
    *)
      break
      ;;
  esac
done
url="$1"
echo "${method:-GET} ${url} ${data}" >>"$CERT_ROTATOR_CURL_LOG"
if [[ "$url" == *"/auth/kubernetes/login" ]]; then
  printf '{"auth":{"client_token":"test-token"}}\n'
elif [[ "$url" == *"/issue/"* ]]; then
  printf '{"data":{"certificate":"FALLBACK_CERT","private_key":"FALLBACK_KEY","issuing_ca":"FALLBACK_CA"}}\n'
else
  printf '{}\n'
fi
SCRIPT
  chmod +x "$fakebin/curl"

  cat <<'SCRIPT' >"$fakebin/jq"
#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${SYSTEM_JQ_CMD:-}" ]]; then
    echo "SYSTEM_JQ_CMD not set" >&2
    exit 127
  fi
  exec "${SYSTEM_JQ_CMD}" "$@"
SCRIPT
  chmod +x "$fakebin/jq"

  export PATH="$fakebin:/usr/bin:/bin"
  ! command -v kubectl >/dev/null 2>&1

  export CERT_ROTATOR_KUBECTL_LOG="$kubectl_log"
  export CERT_ROTATOR_CURL_LOG="$curl_log"
  export CERT_ROTATOR_HAS_SECRET=1
  export CERT_ROTATOR_SECRET_JSON="$secret_json"

  local token_file="$BATS_TEST_TMPDIR/fallback-token"
  printf 'fallback-token' >"$token_file"

  export VAULT_ADDR="http://vault.example:8200"
  export VAULT_PKI_ROLE="jenkins"
  export VAULT_PKI_SECRET_NS="jenkins"
  export VAULT_PKI_SECRET_NAME="jenkins-tls"
  export JENKINS_CERT_ROTATOR_VAULT_ROLE="jenkins-role"
  export SERVICE_ACCOUNT_TOKEN_FILE="$token_file"
  export VAULT_PKI_LEAF_HOST="fallback.example"
  export JENKINS_CERT_ROTATOR_KUBECTL_PATHS="$fallback_dir"

  run bash scripts/etc/jenkins/cert-rotator.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated TLS secret"* ]]
  [[ "$output" != *"Required command 'kubectl'"* ]]

  read_lines "$kubectl_log" kubectl_calls
  [ "${#kubectl_calls[@]}" -ge 2 ]
  [[ "${kubectl_calls[0]}" == "-n jenkins get secret jenkins-tls -o json" ]]
  printf '%s\n' "${kubectl_calls[@]}" | grep -Fq 'apply -f '
  unset CERT_ROTATOR_KUBECTL_LOG CERT_ROTATOR_CURL_LOG CERT_ROTATOR_HAS_SECRET CERT_ROTATOR_SECRET_JSON
}
@test "_jenkins_warn_on_cert_rotator_pull_failure highlights image pull issues" {
  local warn_log="$BATS_TEST_TMPDIR/warn.log"
  : >"$warn_log"
  _warn() {
    echo "$*" >> "$WARN_LOG"
  }
  export WARN_LOG="$warn_log"
  export -f _warn

  local pods_json='{
    "items": [
      {
        "metadata": {
          "labels": {
            "job-name": "jenkins-cert-rotator-123456"
          }
        },
        "status": {
          "containerStatuses": [
            {
              "state": {
                "waiting": {
                  "reason": "ImagePullBackOff",
                  "message": "Back-off pulling image \"registry.example.com/rotator:latest\""
                }
              }
            }
          ]
        }
      }
    ]
  }'

  _kubectl() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--quiet|--prefer-sudo|--require-sudo)
          shift
          ;;
        -n)
          shift 2
          ;;
        --)
          shift
          break
          ;;
        *)
          break
          ;;
      esac
    done
    local cmd="$*"
    echo "$cmd" >> "$KUBECTL_LOG"
    if [[ "$cmd" == "get pods -l job-name -o json" ]]; then
      printf '%s\n' "$PODS_JSON"
    fi
    return 0
  }
  export PODS_JSON="$pods_json"
  export -f _kubectl

  run _jenkins_warn_on_cert_rotator_pull_failure jenkins
  [ "$status" -eq 0 ]
  read_lines "$WARN_LOG" warn_lines
  [ "${#warn_lines[@]}" -eq 1 ]
  [[ "${warn_lines[0]}" == *"ImagePullBackOff"* ]]
  [[ "${warn_lines[0]}" == *"JENKINS_CERT_ROTATOR_IMAGE"* ]]
  [[ "${warn_lines[0]}" == *"scripts/etc/jenkins/jenkins-vars.sh"* ]]
}

create_self_signed_cert() {
  local cert_out="$1" key_out="$2" serial_hex="$3"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$key_out" -out "$cert_out" -days 1 \
    -subj "/CN=test.local" -set_serial "$serial_hex" >/dev/null 2>&1
}

format_serial_hex_pairs() {
  local raw="${1//:/}"
  raw=${raw//[[:space:]]/}
  raw=$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]')

  if (( ${#raw} % 2 == 1 )); then
    raw="0${raw}"
  fi

  local formatted=""
  local i len=${#raw}
  for (( i = 0; i < len; i += 2 )); do
    if (( i > 0 )); then
      formatted+=':'
    fi
    formatted+="${raw:i:2}"
  done

  printf '%s' "$formatted"
}

@test "cert rotator revokes superseded certificate" {
  local cert_file="$BATS_TEST_TMPDIR/existing.crt"
  local key_file="$BATS_TEST_TMPDIR/existing.key"
  create_self_signed_cert "$cert_file" "$key_file" 0xABCD
  local expected_serial
  expected_serial=$(openssl x509 -noout -serial -in "$cert_file")
  expected_serial=${expected_serial#serial=}
  expected_serial=${expected_serial//:/}
  expected_serial=${expected_serial//[[:space:]]/}
  expected_serial=$(printf '%s' "$expected_serial" | tr '[:lower:]' '[:upper:]')
  expected_serial=$(printf '%s' "$expected_serial" | sed 's/../&:/g; s/:$//')

  local cert_b64
  cert_b64=$(base64 <"$cert_file" | tr -d '\n')
  local secret_json="$BATS_TEST_TMPDIR/secret.json"
  cat <<JSON >"$secret_json"
{"data":{"tls.crt":"$cert_b64"}}
JSON

  local fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  local kubectl_log="$BATS_TEST_TMPDIR/kubectl-calls.log"
  local curl_log="$BATS_TEST_TMPDIR/curl.log"
  : >"$kubectl_log"
  : >"$curl_log"

  cat <<'SCRIPT' >"$fakebin/kubectl"
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"$CERT_ROTATOR_KUBECTL_LOG"
if [[ "$1" == "-n" && "$3" == "get" && "$4" == "secret" ]]; then
  if [[ "${CERT_ROTATOR_HAS_SECRET:-0}" == "1" ]]; then
    cat "$CERT_ROTATOR_SECRET_JSON"
    exit 0
  else
    exit 1
  fi
elif [[ "$1" == "apply" && "$2" == "-f" ]]; then
  exit 0
fi
exit 0
SCRIPT
  chmod +x "$fakebin/kubectl"

  cat <<'SCRIPT' >"$fakebin/curl"
#!/usr/bin/env bash
set -euo pipefail
method=""
data=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --request)
      method="$2"
      shift 2
      ;;
    --data)
      data="$2"
      shift 2
      ;;
    --header)
      shift 2
      ;;
    --silent|--show-error|--fail|-k)
      shift
      ;;
    --cacert)
      shift 2
      ;;
    *)
      break
      ;;
  esac
done
url="$1"
echo "${method:-GET} ${url} ${data}" >>"$CERT_ROTATOR_CURL_LOG"
if [[ "$url" == *"/auth/kubernetes/login" ]]; then
  printf '{"auth":{"client_token":"test-token"}}\n'
elif [[ "$url" == *"/issue/"* ]]; then
  printf '{"data":{"certificate":"NEW_CERT","private_key":"NEW_KEY","issuing_ca":"NEW_CA"}}\n'
elif [[ "$url" == *"/revoke" ]]; then
  printf '{"revoked":true}\n'
else
  printf '{}\n'
fi
SCRIPT
  chmod +x "$fakebin/curl"

  cat <<'SCRIPT' >"$fakebin/jq"
#!/usr/bin/env bash
set -euo pipefail
args=("$@")
if (( ${#args[@]} )); then
  last_index=$((${#args[@]} - 1))
  if [[ "${args[last_index]}" == *"{common_name: \$cn}, alt_names: \$alt"* ]]; then
    args[last_index]='{common_name: $cn, alt_names: $alt}'
  fi
fi
if [[ -z "${SYSTEM_JQ_CMD:-}" ]]; then
    echo "SYSTEM_JQ_CMD not set" >&2
    exit 127
  fi
  exec "${SYSTEM_JQ_CMD}" "${args[@]}"
SCRIPT
  chmod +x "$fakebin/jq"

  export PATH="$fakebin:$PATH"
  export CERT_ROTATOR_KUBECTL_LOG="$kubectl_log"
  export CERT_ROTATOR_CURL_LOG="$curl_log"
  export CERT_ROTATOR_HAS_SECRET=1
  export CERT_ROTATOR_SECRET_JSON="$secret_json"

  local token_file="$BATS_TEST_TMPDIR/token"
  printf 'sa-token' >"$token_file"

  export VAULT_ADDR="http://vault.local:8200"
  export VAULT_PKI_ROLE="jenkins"
  export VAULT_PKI_SECRET_NS="jenkins"
  export VAULT_PKI_SECRET_NAME="jenkins-tls"
  export JENKINS_CERT_ROTATOR_VAULT_ROLE="jenkins-role"
  export SERVICE_ACCOUNT_TOKEN_FILE="$token_file"
  export VAULT_PKI_LEAF_HOST="jenkins.example"

  run bash scripts/etc/jenkins/cert-rotator.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated TLS secret"* ]]

  grep -Fq "pki/revoke" "$curl_log"
  grep -Fq "\"serial_number\": \"${expected_serial}\"" "$curl_log"
}

@test "cert rotator skips revoke when no prior certificate" {
  local fakebin="$BATS_TEST_TMPDIR/fakebin-no-secret"
  mkdir -p "$fakebin"
  local kubectl_log="$BATS_TEST_TMPDIR/kubectl-calls-no-secret.log"
  local curl_log="$BATS_TEST_TMPDIR/curl-no-secret.log"
  : >"$kubectl_log"
  : >"$curl_log"

  cat <<'SCRIPT' >"$fakebin/kubectl"
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"$CERT_ROTATOR_KUBECTL_LOG"
if [[ "$1" == "-n" && "$3" == "get" && "$4" == "secret" ]]; then
  exit 1
elif [[ "$1" == "apply" && "$2" == "-f" ]]; then
  exit 0
fi
exit 0
SCRIPT
  chmod +x "$fakebin/kubectl"

  cat <<'SCRIPT' >"$fakebin/curl"
#!/usr/bin/env bash
set -euo pipefail
method=""
data=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --request)
      method="$2"
      shift 2
      ;;
    --data)
      data="$2"
      shift 2
      ;;
    --header)
      shift 2
      ;;
    --silent|--show-error|--fail|-k)
      shift
      ;;
    --cacert)
      shift 2
      ;;
    *)
      break
      ;;
  esac
done
url="$1"
echo "${method:-GET} ${url} ${data}" >>"$CERT_ROTATOR_CURL_LOG"
if [[ "$url" == *"/auth/kubernetes/login" ]]; then
  printf '{"auth":{"client_token":"test-token"}}\n'
elif [[ "$url" == *"/issue/"* ]]; then
  printf '{"data":{"certificate":"NEW_CERT","private_key":"NEW_KEY","issuing_ca":"NEW_CA"}}\n'
elif [[ "$url" == *"/revoke" ]]; then
  printf '{"revoked":true}\n'
else
  printf '{}\n'
fi
SCRIPT
  chmod +x "$fakebin/curl"

  cat <<'SCRIPT' >"$fakebin/jq"
#!/usr/bin/env bash
set -euo pipefail
args=("$@")
if (( ${#args[@]} )); then
  last_index=$((${#args[@]} - 1))
  if [[ "${args[last_index]}" == *"{common_name: \$cn}, alt_names: \$alt"* ]]; then
    args[last_index]='{common_name: $cn, alt_names: $alt}'
  fi
fi
if [[ -z "${SYSTEM_JQ_CMD:-}" ]]; then
    echo "SYSTEM_JQ_CMD not set" >&2
    exit 127
  fi
  exec "${SYSTEM_JQ_CMD}" "${args[@]}"
SCRIPT
  chmod +x "$fakebin/jq"

  export PATH="$fakebin:$PATH"
  export CERT_ROTATOR_KUBECTL_LOG="$kubectl_log"
  export CERT_ROTATOR_CURL_LOG="$curl_log"

  local token_file="$BATS_TEST_TMPDIR/token-no-secret"
  printf 'sa-token' >"$token_file"

  export VAULT_ADDR="http://vault.local:8200"
  export VAULT_PKI_ROLE="jenkins"
  export VAULT_PKI_SECRET_NS="jenkins"
  export VAULT_PKI_SECRET_NAME="jenkins-tls"
  export JENKINS_CERT_ROTATOR_VAULT_ROLE="jenkins-role"
  export SERVICE_ACCOUNT_TOKEN_FILE="$token_file"
  export VAULT_PKI_LEAF_HOST="jenkins.example"

  run bash scripts/etc/jenkins/cert-rotator.sh
  [ "$status" -eq 0 ]

  ! grep -Fq "pki/revoke" "$curl_log"
}

@test "_ensure_jenkins_cert EXIT trap survives _deploy_jenkins cleanup" {
  local helper="${BATS_TEST_DIRNAME}/../test_helpers.bash"
  local plugin="${BATS_TEST_DIRNAME}/../../plugins/jenkins.sh"
  local script="$BATS_TEST_TMPDIR/ensure-cert-trap.sh"
  local mktemp_log="$BATS_TEST_TMPDIR/ensure-cert-mktemp.log"

  : > "$mktemp_log"

  cat <<'EOF' >"$script"
#!/usr/bin/env bash
set -eo pipefail

source "$HELPER"
init_test_env
source "$PLUGIN"
export_stubs

mktemp() {
  local path
  path=$(command mktemp "$@")
  echo "$path" >> "$MK_TEMP_LOG"
  printf '%s\n' "$path"
}
export -f mktemp

_cleanup_on_success() {
  for path in "$@"; do
    rm -f "$path"
  done
}
export -f _cleanup_on_success

jq() {
  local _input
  _input=$(cat)
  case "$2" in
    .data.certificate)
      printf '%s\n' CERT
      ;;
    .data.private_key)
      printf '%s\n' KEY
      ;;
    *)
      if command -v jq >/dev/null 2>&1; then
        printf '%s' "$_input" | command jq "$@"
      else
        return 1
      fi
      ;;
  esac
}
export -f jq

_kubectl() {
  local cmd="$*"
  echo "$cmd" >> "$KUBECTL_LOG"
  local secret_name="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
  case "$cmd" in
    *"get secret ${secret_name}"*)
      return 1
      ;;
    *"vault secrets list"*)
      return 1
      ;;
    *"vault write -format=json pki/issue/jenkins"*)
      cat <<'JSON'
{"data":{"certificate":"CERT","private_key":"KEY"}}
JSON
      return 0
      ;;
  esac
  return 0
}
export -f _kubectl

_vault_issue_pki_tls_secret() { return 0; }
export -f _vault_issue_pki_tls_secret

_ensure_jenkins_cert test-vault test-release
_deploy_jenkins sample-ns test-vault test-release
EOF

  chmod +x "$script"
  BATS_TEST_DIRNAME="$BATS_TEST_DIRNAME" \
    BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" \
    HELPER="$helper" \
    PLUGIN="$plugin" \
    MK_TEMP_LOG="$mktemp_log" \
    "$script"

  [ -s "$mktemp_log" ]
  read_lines "$mktemp_log" mktemp_paths
  (( ${#mktemp_paths[@]} >= 4 ))

  for path in "${mktemp_paths[@]}"; do
    [[ ! -e "$path" ]]
  done
}

@test "_deploy_jenkins calls vault helper with namespace, release, and TLS overrides" {
  local helper="${BATS_TEST_DIRNAME}/../test_helpers.bash"
  local plugin="${BATS_TEST_DIRNAME}/../../plugins/jenkins.sh"
  local script="$BATS_TEST_TMPDIR/deploy-jenkins-helper.sh"
  VAULT_CALL_LOG="$BATS_TEST_TMPDIR/vault_call.log"

  cat <<'EOF' >"$script"
#!/usr/bin/env bash
set -euo pipefail

helper="$HELPER"
plugin="$PLUGIN"
vault_log="$VAULT_CALL_LOG"

source "$helper"
init_test_env
source "$plugin"
export_stubs

_vault_issue_pki_tls_secret() {
  printf '%s\n' "$1" "$2" "$5" "$6" "$7" >"$vault_log"
}

_deploy_jenkins "$@"
EOF

  chmod +x "$script"

  BATS_TEST_DIRNAME="$BATS_TEST_DIRNAME" \
    BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" \
    HELPER="$helper" \
    PLUGIN="$plugin" \
    VAULT_CALL_LOG="$VAULT_CALL_LOG" \
    run "$script" ci-namespace ci-vault ci-release

  [ "$status" -eq 0 ]

  read_lines "$VAULT_CALL_LOG" vault_args
  [ "${vault_args[0]}" = "ci-vault" ]
  [ "${vault_args[1]}" = "ci-release" ]
  local leaf_host="${VAULT_PKI_LEAF_HOST:-jenkins.dev.local.me}"
  local secret_ns="${VAULT_PKI_SECRET_NS:-istio-system}"
  local secret_name="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
  [ "${vault_args[2]}" = "$leaf_host" ]
  [ "${vault_args[3]}" = "$secret_ns" ]
  [ "${vault_args[4]}" = "$secret_name" ]
}

@test "Full deployment with --enable-vault --enable-ldap" {
  CALLS_LOG="$BATS_TEST_TMPDIR/calls.log"
  : > "$CALLS_LOG"
  deploy_eso() { echo "deploy_eso:$*" >> "$CALLS_LOG"; }
  deploy_vault() { echo "deploy_vault:$*" >> "$CALLS_LOG"; }
  deploy_ldap() { echo "deploy_ldap:$*" >> "$CALLS_LOG"; }
  _vault_seed_ldap_service_accounts() { echo "_vault_seed_ldap_service_accounts:$*" >> "$CALLS_LOG"; }
  _create_jenkins_admin_vault_policy() { echo "_create_jenkins_admin_vault_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_vault_ad_policy() { echo "_create_jenkins_vault_ad_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_cert_rotator_policy() { echo "_create_jenkins_cert_rotator_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_namespace() { echo "_create_jenkins_namespace:$*" >> "$CALLS_LOG"; }
  _vault_configure_secret_reader_role() { echo "_vault_configure_secret_reader_role:$*" >> "$CALLS_LOG"; }
  _jenkins_apply_eso_resources() { echo "_jenkins_apply_eso_resources:$*" >> "$CALLS_LOG"; }
  _jenkins_wait_for_secret() { echo "_jenkins_wait_for_secret:$*" >> "$CALLS_LOG"; }
  _create_jenkins_pv_pvc() { echo "_create_jenkins_pv_pvc:$*" >> "$CALLS_LOG"; }
  _ensure_jenkins_cert() { echo "_ensure_jenkins_cert:$*" >> "$CALLS_LOG"; }
  _deploy_jenkins() { echo "_deploy_jenkins:$*" >> "$CALLS_LOG"; }
  _wait_for_jenkins_ready() { echo "_wait_for_jenkins_ready:$*" >> "$CALLS_LOG"; }

  run deploy_jenkins --enable-vault --enable-ldap sample-ns custom-vault
  [ "$status" -eq 0 ]

  read_lines "$CALLS_LOG" calls
  local release="${VAULT_RELEASE_DEFAULT:-vault}"
  local -a expected_prefix_sources=()
  if [[ -n "${JENKINS_VAULT_POLICY_PREFIX:-}" ]]; then
    local _configured="${JENKINS_VAULT_POLICY_PREFIX//,/ }"
    local -a _configured_array=()
    read -r -a _configured_array <<< "$_configured"
    expected_prefix_sources+=("${_configured_array[@]}")
  fi
  expected_prefix_sources+=(
    "${JENKINS_ADMIN_VAULT_PATH:-eso/jenkins-admin}"
    "${JENKINS_LDAP_VAULT_PATH:-ldap/openldap-admin}"
  )

  local -a expected_unique_prefixes=()
  for prefix in "${expected_prefix_sources[@]}"; do
    [[ -z "$prefix" ]] && continue
    local trimmed="${prefix#/}"
    trimmed="${trimmed%/}"
    [[ -z "$trimmed" ]] && continue
    local seen=0 existing
    for existing in "${expected_unique_prefixes[@]}"; do
      if [[ "$existing" == "$trimmed" ]]; then
        seen=1
        break
      fi
    done
    (( seen )) && continue
    expected_unique_prefixes+=("$trimmed")
  done

  local expected_prefix_arg=""
  for prefix in "${expected_unique_prefixes[@]}"; do
    if [[ -n "$expected_prefix_arg" ]]; then
      expected_prefix_arg+=","
    fi
    expected_prefix_arg+="$prefix"
  done

  expected=(
    "deploy_eso:"
    "deploy_vault:custom-vault ${release}"
    "deploy_ldap:${LDAP_NAMESPACE:-directory} ${LDAP_RELEASE:-openldap}"
    "_vault_seed_ldap_service_accounts:custom-vault ${release}"
    "_create_jenkins_admin_vault_policy:custom-vault ${release}"
    "_create_jenkins_vault_ad_policy:custom-vault ${release} sample-ns"
    "_create_jenkins_cert_rotator_policy:custom-vault ${release}   sample-ns"
    "_create_jenkins_namespace:sample-ns"
    "_vault_configure_secret_reader_role:custom-vault ${release} ${JENKINS_ESO_SERVICE_ACCOUNT:-eso-jenkins-sa} sample-ns ${JENKINS_VAULT_KV_MOUNT:-secret} ${expected_prefix_arg} ${JENKINS_ESO_ROLE:-eso-jenkins-admin}"
    "_jenkins_apply_eso_resources:sample-ns"
    "_jenkins_wait_for_secret:sample-ns ${JENKINS_ADMIN_SECRET_NAME:-jenkins-admin}"
    "_jenkins_wait_for_secret:sample-ns ${JENKINS_LDAP_SECRET_NAME:-jenkins-ldap-config}"
    "_create_jenkins_pv_pvc:sample-ns"
    "_ensure_jenkins_cert:custom-vault ${release}"
    "_deploy_jenkins:sample-ns custom-vault ${release}"
    "_wait_for_jenkins_ready:sample-ns"
  )
  [ "${#calls[@]}" -eq "${#expected[@]}" ]
  for i in "${!expected[@]}"; do
    [ "${calls[$i]}" = "${expected[$i]}" ]
  done

  local configure_call="${calls[8]}"
  [[ "$configure_call" == *"${JENKINS_ADMIN_VAULT_PATH:-eso/jenkins-admin}"* ]]
  [[ "$configure_call" == *"${JENKINS_LDAP_VAULT_PATH:-ldap/openldap-admin}"* ]]
}

@test "deploy_jenkins without arguments shows help message" {
  run deploy_jenkins
  [ "$status" -eq 0 ]

  # Check that help message is displayed
  [[ "$output" == *"Usage: deploy_jenkins"* ]]
  [[ "$output" == *"Options:"* ]]
  [[ "$output" == *"--enable-ldap"* ]]
  [[ "$output" == *"--enable-vault"* ]]
  [[ "$output" == *"Examples:"* ]]
}

@test "deploy_jenkins with --disable flags deploys minimal Jenkins (no Vault, no LDAP)" {
  CALLS_LOG="$BATS_TEST_TMPDIR/calls-default.log"
  : > "$CALLS_LOG"
  deploy_eso() { echo "deploy_eso:$*" >> "$CALLS_LOG"; }
  deploy_vault() { echo "deploy_vault:$*" >> "$CALLS_LOG"; }
  deploy_ldap() { echo "deploy_ldap:$*" >> "$CALLS_LOG"; }
  _vault_seed_ldap_service_accounts() { echo "_vault_seed_ldap_service_accounts:$*" >> "$CALLS_LOG"; }
  _create_jenkins_admin_vault_policy() { echo "_create_jenkins_admin_vault_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_vault_ad_policy() { echo "_create_jenkins_vault_ad_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_cert_rotator_policy() { echo "_create_jenkins_cert_rotator_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_namespace() { echo "_create_jenkins_namespace:$*" >> "$CALLS_LOG"; }
  _vault_configure_secret_reader_role() { echo "_vault_configure_secret_reader_role:$*" >> "$CALLS_LOG"; }
  _jenkins_apply_eso_resources() { echo "_jenkins_apply_eso_resources:$*" >> "$CALLS_LOG"; }
  _jenkins_wait_for_secret() { echo "_jenkins_wait_for_secret:$*" >> "$CALLS_LOG"; }
  _create_jenkins_pv_pvc() { echo "_create_jenkins_pv_pvc:$*" >> "$CALLS_LOG"; }
  _ensure_jenkins_cert() { echo "_ensure_jenkins_cert:$*" >> "$CALLS_LOG"; }
  _deploy_jenkins() { echo "_deploy_jenkins:$*" >> "$CALLS_LOG"; }
  _wait_for_jenkins_ready() { echo "_wait_for_jenkins_ready:$*" >> "$CALLS_LOG"; }

  run deploy_jenkins --disable-ldap --disable-vault
  [ "$status" -eq 0 ]

  read_lines "$CALLS_LOG" calls

  # ESO, Vault, and LDAP should NOT be called (explicitly disabled)
  for call in "${calls[@]}"; do
    [[ "$call" != "deploy_eso:"* ]]
    [[ "$call" != "deploy_vault:"* ]]
    [[ "$call" != "deploy_ldap:"* ]]
    [[ "$call" != "_vault_seed_ldap_service_accounts:"* ]]
  done

  # Jenkins core deployment should still happen
  local jenkins_found=0
  for call in "${calls[@]}"; do
    if [[ "$call" == "_deploy_jenkins:"* ]]; then
      jenkins_found=1
      break
    fi
  done
  [ "$jenkins_found" -eq 1 ]
}

@test "deploy_jenkins --enable-ldap without Vault deploys LDAP only" {
  CALLS_LOG="$BATS_TEST_TMPDIR/calls-ldap-only.log"
  : > "$CALLS_LOG"
  deploy_eso() { echo "deploy_eso:$*" >> "$CALLS_LOG"; }
  deploy_vault() { echo "deploy_vault:$*" >> "$CALLS_LOG"; }
  deploy_ldap() { echo "deploy_ldap:$*" >> "$CALLS_LOG"; }
  _vault_seed_ldap_service_accounts() { echo "_vault_seed_ldap_service_accounts:$*" >> "$CALLS_LOG"; }
  _create_jenkins_admin_vault_policy() { echo "_create_jenkins_admin_vault_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_vault_ad_policy() { echo "_create_jenkins_vault_ad_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_cert_rotator_policy() { echo "_create_jenkins_cert_rotator_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_namespace() { echo "_create_jenkins_namespace:$*" >> "$CALLS_LOG"; }
  _vault_configure_secret_reader_role() { echo "_vault_configure_secret_reader_role:$*" >> "$CALLS_LOG"; }
  _jenkins_apply_eso_resources() { echo "_jenkins_apply_eso_resources:$*" >> "$CALLS_LOG"; }
  _jenkins_wait_for_secret() { echo "_jenkins_wait_for_secret:$*" >> "$CALLS_LOG"; }
  _create_jenkins_pv_pvc() { echo "_create_jenkins_pv_pvc:$*" >> "$CALLS_LOG"; }
  _ensure_jenkins_cert() { echo "_ensure_jenkins_cert:$*" >> "$CALLS_LOG"; }
  _deploy_jenkins() { echo "_deploy_jenkins:$*" >> "$CALLS_LOG"; }
  _wait_for_jenkins_ready() { echo "_wait_for_jenkins_ready:$*" >> "$CALLS_LOG"; }

  run deploy_jenkins --enable-ldap
  [ "$status" -eq 0 ]

  read_lines "$CALLS_LOG" calls

  # ESO and Vault should NOT be called (Vault disabled by default)
  for call in "${calls[@]}"; do
    [[ "$call" != "deploy_eso:"* ]]
    [[ "$call" != "deploy_vault:"* ]]
  done

  # LDAP should be called (explicitly enabled)
  local ldap_found=0
  for call in "${calls[@]}"; do
    if [[ "$call" == "deploy_ldap:"* ]]; then
      ldap_found=1
      break
    fi
  done
  [ "$ldap_found" -eq 1 ]
}

@test "deploy_jenkins --enable-vault without LDAP deploys Vault only" {
  CALLS_LOG="$BATS_TEST_TMPDIR/calls-vault-only.log"
  : > "$CALLS_LOG"
  deploy_eso() { echo "deploy_eso:$*" >> "$CALLS_LOG"; }
  deploy_vault() { echo "deploy_vault:$*" >> "$CALLS_LOG"; }
  deploy_ldap() { echo "deploy_ldap:$*" >> "$CALLS_LOG"; }
  _vault_seed_ldap_service_accounts() { echo "_vault_seed_ldap_service_accounts:$*" >> "$CALLS_LOG"; }
  _create_jenkins_admin_vault_policy() { echo "_create_jenkins_admin_vault_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_vault_ad_policy() { echo "_create_jenkins_vault_ad_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_cert_rotator_policy() { echo "_create_jenkins_cert_rotator_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_namespace() { echo "_create_jenkins_namespace:$*" >> "$CALLS_LOG"; }
  _vault_configure_secret_reader_role() { echo "_vault_configure_secret_reader_role:$*" >> "$CALLS_LOG"; }
  _jenkins_apply_eso_resources() { echo "_jenkins_apply_eso_resources:$*" >> "$CALLS_LOG"; }
  _jenkins_wait_for_secret() { echo "_jenkins_wait_for_secret:$*" >> "$CALLS_LOG"; }
  _create_jenkins_pv_pvc() { echo "_create_jenkins_pv_pvc:$*" >> "$CALLS_LOG"; }
  _ensure_jenkins_cert() { echo "_ensure_jenkins_cert:$*" >> "$CALLS_LOG"; }
  _deploy_jenkins() { echo "_deploy_jenkins:$*" >> "$CALLS_LOG"; }
  _wait_for_jenkins_ready() { echo "_wait_for_jenkins_ready:$*" >> "$CALLS_LOG"; }

  run deploy_jenkins --enable-vault
  [ "$status" -eq 0 ]

  read_lines "$CALLS_LOG" calls

  # ESO and Vault SHOULD be called (explicitly enabled)
  local eso_found=0 vault_found=0
  for call in "${calls[@]}"; do
    [[ "$call" == "deploy_eso:"* ]] && eso_found=1
    [[ "$call" == "deploy_vault:"* ]] && vault_found=1
  done
  [ "$eso_found" -eq 1 ]
  [ "$vault_found" -eq 1 ]

  # LDAP should NOT be called (disabled by default)
  for call in "${calls[@]}"; do
    [[ "$call" != "deploy_ldap:"* ]]
  done

  # LDAP service accounts should NOT be seeded
  for call in "${calls[@]}"; do
    [[ "$call" != "_vault_seed_ldap_service_accounts:"* ]]
  done
}

@test "deploy_jenkins --disable-vault --disable-ldap skips all integrations" {
  CALLS_LOG="$BATS_TEST_TMPDIR/calls-minimal.log"
  : > "$CALLS_LOG"
  deploy_eso() { echo "deploy_eso:$*" >> "$CALLS_LOG"; }
  deploy_vault() { echo "deploy_vault:$*" >> "$CALLS_LOG"; }
  deploy_ldap() { echo "deploy_ldap:$*" >> "$CALLS_LOG"; }
  _vault_seed_ldap_service_accounts() { echo "_vault_seed_ldap_service_accounts:$*" >> "$CALLS_LOG"; }
  _create_jenkins_admin_vault_policy() { echo "_create_jenkins_admin_vault_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_vault_ad_policy() { echo "_create_jenkins_vault_ad_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_cert_rotator_policy() { echo "_create_jenkins_cert_rotator_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_namespace() { echo "_create_jenkins_namespace:$*" >> "$CALLS_LOG"; }
  _vault_configure_secret_reader_role() { echo "_vault_configure_secret_reader_role:$*" >> "$CALLS_LOG"; }
  _jenkins_apply_eso_resources() { echo "_jenkins_apply_eso_resources:$*" >> "$CALLS_LOG"; }
  _jenkins_wait_for_secret() { echo "_jenkins_wait_for_secret:$*" >> "$CALLS_LOG"; }
  _create_jenkins_pv_pvc() { echo "_create_jenkins_pv_pvc:$*" >> "$CALLS_LOG"; }
  _ensure_jenkins_cert() { echo "_ensure_jenkins_cert:$*" >> "$CALLS_LOG"; }
  _deploy_jenkins() { echo "_deploy_jenkins:$*" >> "$CALLS_LOG"; }
  _wait_for_jenkins_ready() { echo "_wait_for_jenkins_ready:$*" >> "$CALLS_LOG"; }

  run deploy_jenkins --disable-vault --disable-ldap
  [ "$status" -eq 0 ]

  read_lines "$CALLS_LOG" calls

  # ESO, Vault, and LDAP should NOT be called
  for call in "${calls[@]}"; do
    [[ "$call" != "deploy_eso:"* ]]
    [[ "$call" != "deploy_vault:"* ]]
    [[ "$call" != "deploy_ldap:"* ]]
    [[ "$call" != "_vault_seed_ldap_service_accounts:"* ]]
  done

  # Jenkins core deployment should still happen
  local jenkins_found=0
  for call in "${calls[@]}"; do
    if [[ "$call" == "_deploy_jenkins:"* ]]; then
      jenkins_found=1
      break
    fi
  done
  [ "$jenkins_found" -eq 1 ]
}

@test "deploy_jenkins aborts readiness wait when deployment fails" {
  source "${BATS_TEST_DIRNAME}/../../plugins/jenkins.sh"
  export_stubs

  deploy_vault() { :; }
  deploy_eso() { :; }
  deploy_ldap() { :; }
  _vault_seed_ldap_service_accounts() { :; }
  _create_jenkins_admin_vault_policy() { :; }
  _create_jenkins_vault_ad_policy() { :; }
  _create_jenkins_cert_rotator_policy() { :; }
  _create_jenkins_namespace() { :; }
  _vault_configure_secret_reader_role() { :; }
  _jenkins_apply_eso_resources() { :; }
  SECRET_WAIT_LOG="$BATS_TEST_TMPDIR/secret-waits.log"
  : > "$SECRET_WAIT_LOG"
  _jenkins_wait_for_secret() { echo "$*" >> "$SECRET_WAIT_LOG"; }
  _create_jenkins_pv_pvc() { :; }
  _ensure_jenkins_cert() { :; }
  _vault_issue_pki_tls_secret() { :; }

  WAIT_LOG="$BATS_TEST_TMPDIR/wait.log"
  : > "$WAIT_LOG"
  _wait_for_jenkins_ready() { echo "called" >> "$WAIT_LOG"; }

  local helper="${BATS_TEST_DIRNAME}/../test_helpers.bash"
  local plugin="${BATS_TEST_DIRNAME}/../../plugins/jenkins.sh"
  local script="$BATS_TEST_TMPDIR/deploy-jenkins-fail.sh"

  cat <<'EOF' >"$script"
#!/usr/bin/env bash
set -euo pipefail

helper="$HELPER"
plugin="$PLUGIN"
wait_log="$WAIT_LOG"

source "$helper"
init_test_env
source "$plugin"
export_stubs

deploy_vault() { :; }
deploy_eso() { :; }
deploy_ldap() { :; }
_vault_seed_ldap_service_accounts() { :; }
_create_jenkins_admin_vault_policy() { :; }
_create_jenkins_vault_ad_policy() { :; }
_create_jenkins_cert_rotator_policy() { :; }
_create_jenkins_namespace() { :; }
_vault_configure_secret_reader_role() { :; }
_jenkins_apply_eso_resources() { :; }
_jenkins_wait_for_secret() { echo "$*" >> "$SECRET_WAIT_LOG"; }
_create_jenkins_pv_pvc() { :; }
_ensure_jenkins_cert() { :; }
_vault_issue_pki_tls_secret() { :; }

_wait_for_jenkins_ready() { echo "called" >> "$wait_log"; }

KUBECTL_EXIT_CODES=(1)

set +e
set +u
JENKINS_DEPLOY_RETRIES=1 deploy_jenkins "$@"
rc=$?
set -e
set -u
exit "$rc"
EOF

  chmod +x "$script"

  BATS_TEST_DIRNAME="$BATS_TEST_DIRNAME" \
    BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" \
    HELPER="$helper" \
    PLUGIN="$plugin" \
    WAIT_LOG="$WAIT_LOG" \
    SECRET_WAIT_LOG="$SECRET_WAIT_LOG" \
    run --separate-stderr "$script" failing-ns
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Jenkins deployment failed"* ]]
  [[ ! -s "$WAIT_LOG" ]]
  read_lines "$SECRET_WAIT_LOG" waited_secrets
  [[ "${waited_secrets[*]}" == *"${JENKINS_ADMIN_SECRET_NAME:-jenkins-admin}"* ]]
  # LDAP secret should NOT be waited for when LDAP is disabled (default)
  [[ "${waited_secrets[*]}" != *"${JENKINS_LDAP_SECRET_NAME:-jenkins-ldap-config}"* ]]
}

@test "_wait_for_jenkins_ready waits for controller" {
  KUBECTL_EXIT_CODES=(1 0)
  sleep() { :; }
  export -f sleep
  run _wait_for_jenkins_ready test-ns 1s
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" kubectl_calls
  [ "${#kubectl_calls[@]}" -eq 2 ]
  expected="-n test-ns wait --for=condition=Ready pod -l app.kubernetes.io/component=jenkins-controller --timeout=5s"
  [ "${kubectl_calls[0]}" = "$expected" ]
}

@test "_wait_for_jenkins_ready respects JENKINS_READY_TIMEOUT" {
  KUBECTL_EXIT_CODES=(1 1)
  sleep() {
    local duration="${1:-0}"
    duration=${duration%s}
    if [[ -n "$duration" ]]; then
      SECONDS=$((SECONDS + duration))
    fi
  }
  export -f sleep
  SECONDS=0
  export JENKINS_READY_TIMEOUT=5s
  run --separate-stderr _wait_for_jenkins_ready test-ns
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Timed out waiting for Jenkins controller pod to be ready"* ]]
  read_lines "$KUBECTL_LOG" kubectl_calls
  [ "${#kubectl_calls[@]}" -eq 2 ]
  unset JENKINS_READY_TIMEOUT
}

@test "VirtualService template configures Jenkins gateway and reverse proxy headers" {
  local template="$SCRIPT_DIR/etc/jenkins/virtualservice.yaml.tmpl"

  run grep -q 'istio-system/jenkins-gw' "$template"
  [ "$status" -eq 0 ]

  run grep -q 'X-Forwarded-Proto: "https"' "$template"
  [ "$status" -eq 0 ]

  run grep -q 'X-Forwarded-Port: "443"' "$template"
  [ "$status" -eq 0 ]

  run grep -q 'number: 8081' "$template"
  [ "$status" -eq 0 ]
}

@test "_deploy_jenkins applies Istio resources" {
  local script="$BATS_TEST_TMPDIR/jenkins-apply.sh"
  local out_kubectl="$BATS_TEST_TMPDIR/out-kubectl.log"

  cat <<'EOF' >"$script"
#!/usr/bin/env bash
set -eo pipefail
source "$BATS_TEST_DIRNAME/../test_helpers.bash"
init_test_env
source "$BATS_TEST_DIRNAME/../../plugins/jenkins.sh"
export_stubs
_vault_issue_pki_tls_secret() { :; }
JENKINS_SKIP_TLS=1 _deploy_jenkins sample-ns
cp "$KUBECTL_LOG" "$OUT_KUBECTL"
EOF
  chmod +x "$script"

  run env BATS_TEST_DIRNAME="$BATS_TEST_DIRNAME" \
      BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" \
      OUT_KUBECTL="$out_kubectl" \
      "$script"
  [ "$status" -eq 0 ]

  read_lines "$out_kubectl" kubectl_calls
  expected_gw_prefix="apply -n istio-system --dry-run=client -f /tmp/jenkins-gateway"
  expected_gw_apply_prefix="apply -n istio-system -f /tmp/jenkins-gateway"
  expected_vs_prefix="apply -n sample-ns --dry-run=client -f /tmp/jenkins-virtualservice"
  expected_vs_apply_prefix="apply -n sample-ns -f /tmp/jenkins-virtualservice"
  expected_dr_prefix="apply -n sample-ns --dry-run=client -f /tmp/jenkins-destinationrule"
  expected_dr_apply_prefix="apply -n sample-ns -f /tmp/jenkins-destinationrule"
  expected_rotator_prefix="apply --dry-run=client -f /tmp/jenkins-cert-rotator"
  expected_rotator_apply_prefix="apply -f /tmp/jenkins-cert-rotator"
  [[ "${kubectl_calls[0]}" == ${expected_gw_prefix}* ]]
  [[ "${kubectl_calls[1]}" == ${expected_gw_apply_prefix}* ]]
  [[ "${kubectl_calls[2]}" == ${expected_vs_prefix}* ]]
  [[ "${kubectl_calls[3]}" == ${expected_vs_apply_prefix}* ]]
  [[ "${kubectl_calls[4]}" == ${expected_dr_prefix}* ]]
  [[ "${kubectl_calls[5]}" == ${expected_dr_apply_prefix}* ]]
  [[ "${kubectl_calls[6]}" == ${expected_rotator_prefix}*  ]]
  [[ "${kubectl_calls[7]}" == ${expected_rotator_apply_prefix}*  ]]
}

@test "_deploy_jenkins skips repo add when local chart provided" {
  export JENKINS_HELM_CHART_REF="$BATS_TEST_TMPDIR/jenkins-chart.tgz"
  export JENKINS_HELM_REPO_URL=""

  local script="$BATS_TEST_TMPDIR/jenkins-helm.sh"
  local out_helm="$BATS_TEST_TMPDIR/out-helm.log"

  cat <<'EOF' >"$script"
#!/usr/bin/env bash
set -eo pipefail
source "$BATS_TEST_DIRNAME/../test_helpers.bash"
init_test_env
source "$BATS_TEST_DIRNAME/../../plugins/jenkins.sh"
export_stubs
_vault_issue_pki_tls_secret() { :; }
JENKINS_SKIP_TLS=1 _deploy_jenkins sample-ns
cp "$HELM_LOG" "$OUT_HELM"
EOF
  chmod +x "$script"

  run env BATS_TEST_DIRNAME="$BATS_TEST_DIRNAME" \
      BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" \
      OUT_HELM="$out_helm" \
      "$script"
  [ "$status" -eq 0 ]

  read_lines "$out_helm" helm_calls
  [ "${#helm_calls[@]}" -eq 1 ]
  # Check that helm upgrade was called with the chart ref and namespace
  # The values file may be original or a temp file (when LDAP filtering is active)
  [[ "${helm_calls[0]}" == upgrade\ --install\ jenkins\ ${JENKINS_HELM_CHART_REF}\ --namespace\ sample-ns\ -f\ * ]]
  # Ensure no repo operations were called
  for call in "${helm_calls[@]}"; do
    [[ "$call" != repo\ add* ]]
    [[ "$call" != repo\ update* ]]
  done
}

@test "_deploy_jenkins renders cert rotator manifest with defaults" {
  unset JENKINS_CERT_ROTATOR_ENABLED
  unset JENKINS_CERT_ROTATOR_NAME
  unset JENKINS_CERT_ROTATOR_SERVICE_ACCOUNT
  unset JENKINS_CERT_ROTATOR_SCHEDULE
  local helper="${BATS_TEST_DIRNAME}/../test_helpers.bash"
  local plugin="${BATS_TEST_DIRNAME}/../../plugins/jenkins.sh"
  local script="$BATS_TEST_TMPDIR/jenkins-rotator-defaults.sh"
  local out_kubectl="$BATS_TEST_TMPDIR/rotator-kubectl.log"
  local capture_dir="$BATS_TEST_TMPDIR/rotator-manifests"
  mkdir -p "$capture_dir"

  cat <<'EOF' >"$script"
#!/usr/bin/env bash
set -euo pipefail

helper="$HELPER"
plugin="$PLUGIN"
capture_dir="$ROTATOR_CAPTURE_DIR"
out_kubectl="$OUT_KUBECTL"

source "$helper"
init_test_env
source "$plugin"
export_stubs

_kubectl() {
  local args=("$@")
  local filtered=()
  local passthrough=0
  for arg in "${args[@]}"; do
    if (( passthrough )); then
      filtered+=("$arg")
      continue
    fi
    case "$arg" in
      --no-exit|--quiet|--prefer-sudo|--require-sudo)
        ;;
      --)
        passthrough=1
        ;;
      *)
        filtered+=("$arg")
        ;;
    esac
  done

  printf '%s\n' "${filtered[*]}" >> "$KUBECTL_LOG"

  local dry_run=0 file=""
  for ((i=0; i<${#filtered[@]}; i++)); do
    case "${filtered[$i]}" in
      --dry-run=client)
        dry_run=1
        ;;
      -f)
        if (( i + 1 < ${#filtered[@]} )); then
          file="${filtered[$((i + 1))]}"
        fi
        ;;
    esac
  done

  if (( dry_run )) && [[ -n "$file" ]]; then
    cp "$file" "$capture_dir/$(basename "$file")"
  fi

  local rc=0
  if ((${#KUBECTL_EXIT_CODES[@]})); then
    rc=${KUBECTL_EXIT_CODES[0]}
    KUBECTL_EXIT_CODES=("${KUBECTL_EXIT_CODES[@]:1}")
  fi
  return "$rc"
}

_vault_issue_pki_tls_secret() { :; }

JENKINS_SKIP_TLS=1 _deploy_jenkins sample-ns
cp "$KUBECTL_LOG" "$out_kubectl"
EOF

  chmod +x "$script"

  run env BATS_TEST_DIRNAME="$BATS_TEST_DIRNAME" \
      BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" \
      HELPER="$helper" \
      PLUGIN="$plugin" \
      OUT_KUBECTL="$out_kubectl" \
      ROTATOR_CAPTURE_DIR="$capture_dir" \
      "$script"
  [ "$status" -eq 0 ]

  local rotator_file
  rotator_file=$(find "$capture_dir" -maxdepth 1 -type f -name 'jenkins-cert-rotator*' -print -quit)
  [[ -n "$rotator_file" ]]
  [[ -s "$rotator_file" ]]
  grep -q 'kind: CronJob' "$rotator_file"
  grep -q 'name: jenkins-cert-rotator' "$rotator_file"
  grep -Fq 'schedule: "0 */12 * * *"' "$rotator_file"
  grep -q 'serviceAccountName: jenkins-cert-rotator' "$rotator_file"
}

@test "_deploy_jenkins cleans up rendered manifests on success and failure" {
  local helper="${BATS_TEST_DIRNAME}/../test_helpers.bash"
  local plugin="${BATS_TEST_DIRNAME}/../../plugins/jenkins.sh"

  run_cleanup_check() {
    local mode="$1"
    local script="$BATS_TEST_TMPDIR/check-${mode}.sh"
    local log_file="$BATS_TEST_TMPDIR/cleanup-${mode}.log"
    {
      cat <<EOF
#!/usr/bin/env bash
set -eo pipefail
BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME}"
BATS_TEST_TMPDIR="${BATS_TEST_TMPDIR}"
helper="$helper"
plugin="$plugin"
mode="$mode"
log_file="$log_file"
EOF
      cat <<'EOF'
source "$helper"
init_test_env
source "$plugin"
export_stubs
_cleanup_on_success() {
  for path in "$@"; do
    echo "$path" >> "$log_file"
    rm -f "$path"
  done
}
_vault_issue_pki_tls_secret() { :; }
export -f _cleanup_on_success
export -f _vault_issue_pki_tls_secret
: >"$log_file"
if [[ "$mode" == failure ]]; then
  KUBECTL_EXIT_CODES=(0 0 1)
fi
set +e
_deploy_jenkins sample-ns >/dev/null 2>&1
status=$?
set -e
if [[ "$mode" == success ]]; then
  [[ "$status" -eq 0 ]] || exit 1
else
  kubectl_calls=$(wc -l <"$KUBECTL_LOG")
  [[ "$kubectl_calls" -lt 6 ]] || exit 1
fi
  cleanup_paths=()
  while IFS= read -r line; do
    cleanup_paths+=("$line")
  done <"$log_file"
expected_count=4
for path in "${cleanup_paths[@]}"; do
  if [[ "$path" == *jenkins-cert-rotator* ]]; then
    expected_count=5
    break
  fi
done
[[ "${#cleanup_paths[@]}" -eq "$expected_count" ]] || exit 1
  unique_paths=()
  while IFS= read -r line; do
    unique_paths+=("$line")
  done < <(printf '%s\n' "${cleanup_paths[@]}" | sort -u)
[[ "${#unique_paths[@]}" -eq "$expected_count" ]] || exit 1
for path in "${unique_paths[@]}"; do
  [[ "$path" == /tmp/* ]] || exit 1
  [[ ! -e "$path" ]] || exit 1
done
EOF
    } >"$script"

    chmod +x "$script"
    "$script"
  }

  run_cleanup_check success
  run_cleanup_check failure
}
@test "deploy_jenkins renders manifests for namespace" {
  local random_ns="jenkins-${RANDOM}"
  local capture_dir="$BATS_TEST_TMPDIR/manifests"
  local script="$BATS_TEST_TMPDIR/jenkins-manifests.sh"
  local out_kubectl="$BATS_TEST_TMPDIR/out-manifests.log"

  SECRET_WAIT_LOG="$BATS_TEST_TMPDIR/manifest-secret-waits.log"
  : > "$SECRET_WAIT_LOG"

  cat <<'EOF' >"$script"
#!/usr/bin/env bash
set -eo pipefail
source "$BATS_TEST_DIRNAME/../test_helpers.bash"
init_test_env
source "$BATS_TEST_DIRNAME/../../plugins/jenkins.sh"
export_stubs
deploy_vault() { :; }
deploy_eso() { :; }
deploy_ldap() { :; }
_vault_seed_ldap_service_accounts() { :; }
_create_jenkins_admin_vault_policy() { :; }
_create_jenkins_vault_ad_policy() { :; }
_create_jenkins_cert_rotator_policy() { :; }
_create_jenkins_namespace() { :; }
_vault_configure_secret_reader_role() { :; }
_jenkins_apply_eso_resources() { :; }
_jenkins_wait_for_secret() { echo "$*" >> "$SECRET_WAIT_LOG"; }
_create_jenkins_pv_pvc() { :; }
_ensure_jenkins_cert() { :; }
_wait_for_jenkins_ready() { :; }
_vault_issue_pki_tls_secret() { :; }
MANIFEST_CAPTURE_DIR="$CAPTURE_DIR"
mkdir -p "$MANIFEST_CAPTURE_DIR"
_kubectl() {
  local original=("$@")
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-exit|--quiet|--prefer-sudo|--require-sudo) shift ;;
      --) shift; original=("$@"); break ;;
      *) shift;;
    esac
  done
  printf '%s
' "${original[*]}" >> "$KUBECTL_LOG"
  local dry_run=0 file=""
  for ((i=0; i<${#original[@]}; i++)); do
    case "${original[$i]}" in
      --dry-run=client) dry_run=1 ;;
      -f)
        if (( i + 1 < ${#original[@]} )); then
          file="${original[$((i+1))]}"
        fi
        ;;
    esac
  done
  if (( dry_run )) && [[ -n "$file" ]]; then
    local dest="$MANIFEST_CAPTURE_DIR/$(basename "$file")"
    cp "$file" "$dest"
  fi
  return 0
}
export -f _kubectl
JENKINS_SKIP_TLS=1 deploy_jenkins "$TARGET_NS"
cp "$KUBECTL_LOG" "$OUT_KUBECTL"
EOF
  chmod +x "$script"

  run env BATS_TEST_DIRNAME="$BATS_TEST_DIRNAME" \
      BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" \
      CAPTURE_DIR="$capture_dir" \
      TARGET_NS="$random_ns" \
      OUT_KUBECTL="$out_kubectl" \
      SECRET_WAIT_LOG="$SECRET_WAIT_LOG" \
      "$script"
  if [ "$status" -ne 0 ]; then
    echo "$output" >&2
    cat "$out_kubectl" >&2 || true
  fi
  [ "$status" -eq 0 ]

  local vs_file
  vs_file=$(find "$capture_dir" -maxdepth 1 -type f -name 'jenkins-virtualservice*' -print -quit)
  local dr_file
  dr_file=$(find "$capture_dir" -maxdepth 1 -type f -name 'jenkins-destinationrule*' -print -quit)

  [[ -n "$vs_file" ]]
  [[ -n "$dr_file" ]]
  grep -Eq "namespace: \"?$random_ns\"?" "$vs_file"
  grep -q '  hosts:' "$vs_file"
  grep -q '    - jenkins.dev.local.me' "$vs_file"
  grep -q '    - jenkins.dev.k3d.internal' "$vs_file"
  grep -q "jenkins.$random_ns.svc.cluster.local" "$vs_file"
  grep -Eq "namespace: \"?$random_ns\"?" "$dr_file"
  grep -q "jenkins.$random_ns.svc.cluster.local" "$dr_file"
  read_lines "$SECRET_WAIT_LOG" manifest_waits
  [[ "${manifest_waits[*]}" == *"${JENKINS_ADMIN_SECRET_NAME:-jenkins-admin}"* ]]
  # LDAP secret should NOT be waited for when LDAP is disabled (default)
  [[ "${manifest_waits[*]}" != *"${JENKINS_LDAP_SECRET_NAME:-jenkins-ldap-config}"* ]]
}

@test "_jenkins_apply_eso_resources filters LDAP ExternalSecret when LDAP disabled" {
  export JENKINS_CONFIG_DIR="${SCRIPT_DIR}/etc/jenkins"
  export JENKINS_NAMESPACE="jenkins"
  export JENKINS_ESO_SERVICE_ACCOUNT="eso-jenkins-sa"
  export JENKINS_ESO_SECRETSTORE="vault-kv-store"
  export VAULT_ENDPOINT="http://vault.vault.svc:8200"
  export JENKINS_VAULT_KV_MOUNT="secret"
  export JENKINS_ESO_ROLE="eso-jenkins-admin"
  export JENKINS_ADMIN_SECRET_NAME="jenkins-admin"
  export JENKINS_ADMIN_K8S_USER_KEY="jenkins-admin-user"
  export JENKINS_ADMIN_VAULT_PATH="eso/jenkins-admin"
  export JENKINS_ADMIN_USERNAME_KEY="username"
  export JENKINS_ADMIN_K8S_PASS_KEY="jenkins-admin-password"
  export JENKINS_ADMIN_PASSWORD_KEY="password"
  export JENKINS_LDAP_SECRET_NAME="jenkins-ldap-config"
  export JENKINS_LDAP_VAULT_PATH="ldap/service-accounts/jenkins-admin"
  export JENKINS_LDAP_BINDDN_KEY="bind_dn"
  export JENKINS_LDAP_PASSWORD_KEY="password"
  export JENKINS_LDAP_BASE_DN_KEY="base_dn"
  export JENKINS_LDAP_ENABLED=0

  local KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl-eso-filter.log"
  : >"$KUBECTL_LOG"
  export KUBECTL_LOG

  _kubectl() {
    local cmd="$*"
    echo "$cmd" >> "$KUBECTL_LOG"
    if [[ "$cmd" == "apply -f "* ]]; then
      local manifest_file="${cmd#apply -f }"
      # Verify LDAP ExternalSecret is NOT in the manifest
      if grep -q "name: jenkins-ldap-config" "$manifest_file"; then
        echo "ERROR: LDAP ExternalSecret found in manifest when LDAP disabled" >&2
        return 1
      fi
      # Verify jenkins-admin ExternalSecret IS in the manifest
      if ! grep -q "name: jenkins-admin" "$manifest_file"; then
        echo "ERROR: jenkins-admin ExternalSecret not found in manifest" >&2
        return 1
      fi
      return 0
    fi
    return 0
  }
  export -f _kubectl

  run _jenkins_apply_eso_resources "$JENKINS_NAMESPACE"
  [ "$status" -eq 0 ]
}

@test "_jenkins_apply_eso_resources includes LDAP ExternalSecret when LDAP enabled" {
  export JENKINS_CONFIG_DIR="${SCRIPT_DIR}/etc/jenkins"
  export JENKINS_NAMESPACE="jenkins"
  export JENKINS_ESO_SERVICE_ACCOUNT="eso-jenkins-sa"
  export JENKINS_ESO_SECRETSTORE="vault-kv-store"
  export VAULT_ENDPOINT="http://vault.vault.svc:8200"
  export JENKINS_VAULT_KV_MOUNT="secret"
  export JENKINS_ESO_ROLE="eso-jenkins-admin"
  export JENKINS_ADMIN_SECRET_NAME="jenkins-admin"
  export JENKINS_ADMIN_K8S_USER_KEY="jenkins-admin-user"
  export JENKINS_ADMIN_VAULT_PATH="eso/jenkins-admin"
  export JENKINS_ADMIN_USERNAME_KEY="username"
  export JENKINS_ADMIN_K8S_PASS_KEY="jenkins-admin-password"
  export JENKINS_ADMIN_PASSWORD_KEY="password"
  export JENKINS_LDAP_SECRET_NAME="jenkins-ldap-config"
  export JENKINS_LDAP_VAULT_PATH="ldap/service-accounts/jenkins-admin"
  export JENKINS_LDAP_BINDDN_KEY="bind_dn"
  export JENKINS_LDAP_PASSWORD_KEY="password"
  export JENKINS_LDAP_BASE_DN_KEY="base_dn"
  export JENKINS_LDAP_ENABLED=1

  local KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl-eso-include.log"
  : >"$KUBECTL_LOG"
  export KUBECTL_LOG

  _kubectl() {
    local cmd="$*"
    echo "$cmd" >> "$KUBECTL_LOG"
    if [[ "$cmd" == "apply -f "* ]]; then
      local manifest_file="${cmd#apply -f }"
      # Verify LDAP ExternalSecret IS in the manifest
      if ! grep -q "name: jenkins-ldap-config" "$manifest_file"; then
        echo "ERROR: LDAP ExternalSecret not found in manifest when LDAP enabled" >&2
        return 1
      fi
      # Verify jenkins-admin ExternalSecret IS in the manifest
      if ! grep -q "name: jenkins-admin" "$manifest_file"; then
        echo "ERROR: jenkins-admin ExternalSecret not found in manifest" >&2
        return 1
      fi
      return 0
    fi
    return 0
  }
  export -f _kubectl

  run _jenkins_apply_eso_resources "$JENKINS_NAMESPACE"
  [ "$status" -eq 0 ]
}
