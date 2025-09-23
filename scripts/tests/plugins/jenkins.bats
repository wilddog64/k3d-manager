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
  jhp="$SCRIPT_DIR/storage/jenkins_home"
  echo "JENKINS_HOME_PATH=$jhp"
  rm -rf "$jhp"
  CLUSTER_NAME="testcluster"
  export CLUSTER_NAME
  local mount_check_log="$BATS_TEST_TMPDIR/mount-check.log"
  : >"$mount_check_log"
  _jenkins_require_hostpath_mounts() {
    echo "$1" >"$MOUNT_CHECK_LOG"
    return 0
  }
  export MOUNT_CHECK_LOG="$mount_check_log"
  export -f _jenkins_require_hostpath_mounts
  run _create_jenkins_pv_pvc test-ns
  [ "$status" -eq 0 ]
  [[ -d "$jhp" ]]
  read_lines "$KUBECTL_LOG" kubectl_calls
  [[ "${kubectl_calls[1]}" == apply* ]]
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
  jhp="$SCRIPT_DIR/storage/jenkins_home"
  rm -rf "$jhp"
  unset CLUSTER_NAME
  local mount_check_log="$BATS_TEST_TMPDIR/mount-check.log"
  : >"$mount_check_log"
  _jenkins_require_hostpath_mounts() {
    echo "$1" >"$MOUNT_CHECK_LOG"
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
  jhp="$SCRIPT_DIR/storage/jenkins_home"
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
  [ "${#kubectl_calls[@]}" -eq 1 ]
  [[ "${kubectl_calls[0]}" == "get pv jenkins-home-pv" ]]
}

@test "_create_jenkins_admin_vault_policy stores secret without logging password" {
  _vault_policy_exists() { return 1; }
  _kubectl() {
    local cmd="$*"
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
  _no_trace() {
    local cmd="$*"
    local script
    script=$(cat)
    if [[ "$script" == *password=* ]]; then
      script="${script/password=*/password=***}"
    fi
    echo "$cmd" >> "$KUBECTL_LOG"
    echo "$script" >> "$KUBECTL_LOG"
    echo "$script" | _kubectl "$@"
  }
  export -f _no_trace
  _cleanup_on_success() { rm -f "$1"; }
  export -f _cleanup_on_success

  run _create_jenkins_admin_vault_policy vault
  [ "$status" -eq 0 ]
  grep -q 'vault kv put secret/eso/jenkins-admin' "$KUBECTL_LOG"
  grep -q 'username=jenkins-admin' "$KUBECTL_LOG"
  grep -Fq 'password=***' "$KUBECTL_LOG"
  ! grep -q 's3cr3t' "$KUBECTL_LOG"
  [[ ! -f jenkins-admin.hcl ]]
}

@test "_create_jenkins_vault_ad_policy creates policies" {
  _vault_policy_exists() { return 1; }
  _vault_policy() { return 1; }
  _kubectl() {
    echo "$*" >> "$KUBECTL_LOG"
    return 0
  }
  export -f _vault_policy_exists
  export -f _vault_policy
  export -f _kubectl

  run _create_jenkins_vault_ad_policy vault jenkins
  [ "$status" -eq 0 ]
  grep -q 'vault policy write jenkins-jcasc-read' "$KUBECTL_LOG"
  grep -q 'vault write auth/kubernetes/role/jenkins-jcasc-reader' "$KUBECTL_LOG"
  grep -q 'vault policy write jenkins-jcasc-write' "$KUBECTL_LOG"
  grep -q 'vault write auth/kubernetes/role/jenkins-jcasc-writer' "$KUBECTL_LOG"
  ! grep -q 'vault kv put' "$KUBECTL_LOG"
  ! grep -q 'password=' "$KUBECTL_LOG"
}

@test "_create_jenkins_cert_rotator_policy writes role without stdin dash" {
  _vault_policy_exists() { return 1; }
  export -f _vault_policy_exists

  VAULT_PKI_SECRET_NS="secret-ns" \
    run _create_jenkins_cert_rotator_policy vault-ns vault-release custom-pki custom-role jenkins-ns rotator-sa
  [ "$status" -eq 0 ]

  read_lines "$KUBECTL_LOG" kubectl_calls

  local role_write_line=""
  local policy_write_count=0
  for line in "${kubectl_calls[@]}"; do
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
}

@test "_ensure_jenkins_cert sets up PKI and TLS secret" {
  _kubectl() {
    local cmd="$*"
    echo "$cmd" >> "$KUBECTL_LOG"
    local secret_name="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
    if [[ "$cmd" == *"get secret ${secret_name}"* ]]; then
      return 1
    fi
    if [[ "$cmd" == *"vault secrets list"* ]]; then
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
  export -f _kubectl

  export VAULT_PKI_LEAF_HOST="jenkins.192.168.0.1.sslip.io"
  unset VAULT_PKI_ALLOWED

  run _ensure_jenkins_cert vault
  [ "$status" -eq 0 ]
  grep -q 'vault secrets enable pki' "$KUBECTL_LOG"
  grep -Fq 'vault write pki/roles/jenkins allowed_domains=sslip.io allow_subdomains=true max_ttl=72h' "$KUBECTL_LOG"
  grep -q 'vault write -format=json pki/issue/jenkins' "$KUBECTL_LOG"
  local secret_name="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
  grep -q "create secret tls ${secret_name}" "$KUBECTL_LOG"
}

@test "_ensure_jenkins_cert honors VAULT_PKI_ALLOWED for wildcard domains" {
  _kubectl() {
    local cmd="$*"
    echo "$cmd" >> "$KUBECTL_LOG"
    local secret_name="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
    if [[ "$cmd" == *"get secret ${secret_name}"* ]]; then
      return 1
    fi
    if [[ "$cmd" == *"vault secrets list"* ]]; then
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
  export -f _kubectl

  export VAULT_PKI_ALLOWED="jenkins.dev.local.me,*.dev.local.me"

  run _ensure_jenkins_cert vault
  [ "$status" -eq 0 ]
  grep -Fq 'allowed_domains=jenkins.dev.local.me,*.dev.local.me' "$KUBECTL_LOG"
  grep -Fq 'max_ttl=72h' "$KUBECTL_LOG"
  ! grep -q 'allow_subdomains=' "$KUBECTL_LOG"
  unset VAULT_PKI_ALLOWED
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
  raw=${raw^^}

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
  expected_serial=${expected_serial^^}
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
exec /usr/bin/jq "${args[@]}"
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
exec /usr/bin/jq "${args[@]}"
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
  mapfile -t mktemp_paths <"$mktemp_log"
  (( ${#mktemp_paths[@]} >= 4 ))

  for path in "${mktemp_paths[@]}"; do
    [[ ! -e "$path" ]]
  done
}

@test "_deploy_jenkins calls vault helper with namespace, release, and TLS overrides" {
  VAULT_CALL_LOG="$BATS_TEST_TMPDIR/vault_call.log"
  _vault_issue_pki_tls_secret() {
    printf '%s\n' "$1" "$2" "$5" "$6" "$7" >"$VAULT_CALL_LOG"
  }
  export -f _vault_issue_pki_tls_secret

  run _deploy_jenkins ci-namespace ci-vault ci-release
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

@test "Full deployment" {
  CALLS_LOG="$BATS_TEST_TMPDIR/calls.log"
  : > "$CALLS_LOG"
  deploy_vault() { echo "deploy_vault:$*" >> "$CALLS_LOG"; }
  _create_jenkins_admin_vault_policy() { echo "_create_jenkins_admin_vault_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_vault_ad_policy() { echo "_create_jenkins_vault_ad_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_cert_rotator_policy() { echo "_create_jenkins_cert_rotator_policy:$*" >> "$CALLS_LOG"; }
  _create_jenkins_namespace() { echo "_create_jenkins_namespace:$*" >> "$CALLS_LOG"; }
  _create_jenkins_pv_pvc() { echo "_create_jenkins_pv_pvc:$*" >> "$CALLS_LOG"; }
  _ensure_jenkins_cert() { echo "_ensure_jenkins_cert:$*" >> "$CALLS_LOG"; }
  _deploy_jenkins() { echo "_deploy_jenkins:$*" >> "$CALLS_LOG"; }
  _wait_for_jenkins_ready() { echo "_wait_for_jenkins_ready:$*" >> "$CALLS_LOG"; }

  run deploy_jenkins sample-ns custom-vault
  [ "$status" -eq 0 ]

  read_lines "$CALLS_LOG" calls
  local release="${VAULT_RELEASE_DEFAULT:-vault}"
  expected=(
    "deploy_vault:ha custom-vault ${release}"
    "_create_jenkins_admin_vault_policy:custom-vault ${release}"
    "_create_jenkins_vault_ad_policy:custom-vault ${release} sample-ns"
    "_create_jenkins_cert_rotator_policy:custom-vault ${release}   sample-ns"
    "_create_jenkins_namespace:sample-ns"
    "_create_jenkins_pv_pvc:sample-ns"
    "_ensure_jenkins_cert:custom-vault ${release}"
    "_deploy_jenkins:sample-ns custom-vault ${release}"
    "_wait_for_jenkins_ready:sample-ns"
  )
  [ "${#calls[@]}" -eq "${#expected[@]}" ]
  for i in "${!expected[@]}"; do
    [ "${calls[$i]}" = "${expected[$i]}" ]
  done
}

@test "deploy_jenkins aborts readiness wait when deployment fails" {
  source "${BATS_TEST_DIRNAME}/../../plugins/jenkins.sh"
  export_stubs

  deploy_vault() { :; }
  _create_jenkins_admin_vault_policy() { :; }
  _create_jenkins_vault_ad_policy() { :; }
  _create_jenkins_cert_rotator_policy() { :; }
  _create_jenkins_namespace() { :; }
  _create_jenkins_pv_pvc() { :; }
  _ensure_jenkins_cert() { :; }
  _vault_issue_pki_tls_secret() { :; }

  WAIT_LOG="$BATS_TEST_TMPDIR/wait.log"
  : > "$WAIT_LOG"
  _wait_for_jenkins_ready() { echo "called" >> "$WAIT_LOG"; }

  KUBECTL_EXIT_CODES=(1)

  run --separate-stderr deploy_jenkins failing-ns
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"ERROR: Jenkins deployment failed; aborting readiness check."* ]]
  [[ ! -s "$WAIT_LOG" ]]
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

@test "VirtualService references Jenkins gateway" {
  run grep -q 'istio-system/jenkins-gw' "$SCRIPT_DIR/etc/jenkins/virtualservice.yaml.tmpl"
  [ "$status" -eq 0 ]
}

@test "_deploy_jenkins applies Istio resources" {
  run _deploy_jenkins sample-ns
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" kubectl_calls
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

@test "_deploy_jenkins renders cert rotator manifest with defaults" {
  unset JENKINS_CERT_ROTATOR_ENABLED
  unset JENKINS_CERT_ROTATOR_NAME
  unset JENKINS_CERT_ROTATOR_SERVICE_ACCOUNT
  unset JENKINS_CERT_ROTATOR_SCHEDULE

  ROTATOR_CAPTURE_DIR="$BATS_TEST_TMPDIR/rotator-manifests"
  mkdir -p "$ROTATOR_CAPTURE_DIR"

  _kubectl() {
    local original=("$@")
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--quiet|--prefer-sudo|--require-sudo)
          shift
          ;;
        --)
          shift
          original=("$@")
          break
          ;;
        *)
          shift
          ;;
      esac
    done

    printf '%s\n' "${original[*]}" >> "$KUBECTL_LOG"

    local dry_run=0 file=""
    for ((i=0; i<${#original[@]}; i++)); do
      case "${original[$i]}" in
        --dry-run=client)
          dry_run=1
          ;;
        -f)
          if (( i + 1 < ${#original[@]} )); then
            file="${original[$((i + 1))]}"
          fi
          ;;
      esac
    done

    if (( dry_run )) && [[ -n "$file" ]]; then
      local dest="$ROTATOR_CAPTURE_DIR/$(basename "$file")"
      cp "$file" "$dest"
    fi

    local rc=0
    if ((${#KUBECTL_EXIT_CODES[@]})); then
      rc=${KUBECTL_EXIT_CODES[0]}
      KUBECTL_EXIT_CODES=("${KUBECTL_EXIT_CODES[@]:1}")
    fi

    return "$rc"
  }

  export -f _kubectl

  _vault_issue_pki_tls_secret() { :; }
  export -f _vault_issue_pki_tls_secret

  run _deploy_jenkins sample-ns
  [ "$status" -eq 0 ]

  local rotator_file
  rotator_file=$(find "$ROTATOR_CAPTURE_DIR" -maxdepth 1 -type f -name 'jenkins-cert-rotator*' -print -quit)
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
readarray -t cleanup_paths <"$log_file"
expected_count=3
for path in "${cleanup_paths[@]}"; do
  if [[ "$path" == *jenkins-cert-rotator* ]]; then
    expected_count=4
    break
  fi
done
[[ "${#cleanup_paths[@]}" -eq "$expected_count" ]] || exit 1
mapfile -t unique_paths < <(printf '%s\n' "${cleanup_paths[@]}" | sort -u)
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
  deploy_vault() { :; }
  _create_jenkins_admin_vault_policy() { :; }
  _create_jenkins_vault_ad_policy() { :; }
  _create_jenkins_namespace() { :; }
  _create_jenkins_pv_pvc() { :; }
  _ensure_jenkins_cert() { :; }
  _wait_for_jenkins_ready() { :; }

  MANIFEST_CAPTURE_DIR="$BATS_TEST_TMPDIR/manifests"
  mkdir -p "$MANIFEST_CAPTURE_DIR"
  _kubectl() {
    local original=("$@")
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--quiet|--prefer-sudo|--require-sudo)
          shift
          ;;
        --)
          shift
          original=("$@")
          break
          ;;
        *)
          shift
          ;;
      esac
    done

    printf '%s\n' "${original[*]}" >> "$KUBECTL_LOG"

    local dry_run=0 file=""
    for ((i=0; i<${#original[@]}; i++)); do
      case "${original[$i]}" in
        --dry-run=client)
          dry_run=1
          ;;
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

  export VAULT_PKI_LEAF_HOST="jenkins.127.0.0.1.nip.io"

  run deploy_jenkins "$random_ns"
  [ "$status" -eq 0 ]

  local vs_file
  vs_file=$(find "$MANIFEST_CAPTURE_DIR" -maxdepth 1 -type f -name 'jenkins-virtualservice*' -print -quit)
  local dr_file
  dr_file=$(find "$MANIFEST_CAPTURE_DIR" -maxdepth 1 -type f -name 'jenkins-destinationrule*' -print -quit)

  [[ -n "$vs_file" ]]
  [[ -n "$dr_file" ]]
  grep -q "namespace: \"$random_ns\"" "$vs_file"
  grep -q '  hosts:' "$vs_file"
  grep -q '    - jenkins.127.0.0.1.nip.io' "$vs_file"
  grep -q "jenkins.$random_ns.svc.cluster.local" "$vs_file"
  grep -q "namespace: \"$random_ns\"" "$dr_file"
  grep -q "jenkins.$random_ns.svc.cluster.local" "$dr_file"
}
