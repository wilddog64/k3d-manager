#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  SOURCE="${BATS_TEST_DIRNAME}/../../k3d-manager"
  SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
  PLUGINS_DIR="${SCRIPT_DIR}/plugins"
  source "${BATS_TEST_DIRNAME}/../../plugins/vault.sh"

  KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
  HELM_LOG="$BATS_TEST_TMPDIR/helm.log"
  : >"$KUBECTL_LOG"
  : >"$HELM_LOG"
  KUBECTL_EXIT_CODES=()
  HELM_EXIT_CODES=()

  CALLS=()

  _kubectl() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--quiet|--prefer-sudo|--require-sudo) shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    echo "$*" >>"$KUBECTL_LOG"
    local rc=0
    if ((${#KUBECTL_EXIT_CODES[@]})); then
      rc=${KUBECTL_EXIT_CODES[0]}
      KUBECTL_EXIT_CODES=("${KUBECTL_EXIT_CODES[@]:1}")
    fi
    return "$rc"
  }

  _helm() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--quiet|--prefer-sudo|--require-sudo) shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    echo "$*" >>"$HELM_LOG"
    local rc=0
    if ((${#HELM_EXIT_CODES[@]})); then
      rc=${HELM_EXIT_CODES[0]}
      HELM_EXIT_CODES=("${HELM_EXIT_CODES[@]:1}")
    fi
    return "$rc"
  }

  deploy_eso() {
    CALLS+=("deploy_eso")
  }

  _err() { echo "$*" >&2; return 1; }
  _cleanup_on_success() { :; }

  export -f _kubectl
  export -f _helm
  export -f deploy_eso
  export -f _err
  export -f _cleanup_on_success
}

kubectl_run_output_fixture() {
  local status="$1" marker="${2:-VAULT_HTTP_STATUS}"
  cat <<EOF
If you don't see a command prompt, try pressing enter.

${marker}:${status}
pod "vault-health-123" deleted (age 42s)
command terminated with exit code 0
EOF
}

setup_vault_bootstrap_stubs() {
  TEST_NS="${1:-custom-ns}"
  TEST_RELEASE="${2:-custom-release}"
  TEST_POD="${TEST_RELEASE}-0"
  TEST_POD_RESOURCE="pod/${TEST_POD}"
  HEALTH_CODE="${3:-200}"
  : >"$KUBECTL_LOG"

  _is_vault_deployed() { return 0; }
  _run_command() { return 1; }
  _no_trace() { "$@"; }
  _warn() { :; }

  export -f _is_vault_deployed
  export -f _run_command
  export -f _no_trace
  export -f _warn

  _kubectl() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--quiet|--prefer-sudo|--require-sudo) shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    local cmd="$*"
    echo "$cmd" >>"$KUBECTL_LOG"
    case "$cmd" in
      "wait -n ${TEST_NS} --for=condition=Podscheduled ${TEST_POD_RESOURCE} --timeout=120s")
        return 0 ;;
      "-n ${TEST_NS} get pod ${TEST_POD} -o jsonpath={.status.phase}")
        echo "Running"
        return 0 ;;
      "-n ${TEST_NS} exec -i ${TEST_POD} -- vault status -format json")
        echo '{"initialized": false}'
        return 0 ;;
      "-n ${TEST_NS} exec -it ${TEST_POD} -- sh -lc vault operator init -key-shares=1 -key-threshold=1 -format=json")
        printf '{"root_token":"root","unseal_keys_b64":["key"]}\n'
        return 0 ;;
      "-n ${TEST_NS} create secret generic vault-root --from-literal=root_token=root")
        return 0 ;;
      "-n ${TEST_NS} get pod -l app.kubernetes.io/name=vault,app.kubernetes.io/instance=${TEST_RELEASE} -o name")
        echo "pod/${TEST_POD}"
        return 0 ;;
      "-n ${TEST_NS} exec -i ${TEST_POD} -- sh -lc vault operator unseal key")
        return 0 ;;
      "-n ${TEST_NS} run "*)
        if [[ "$cmd" == *"vault-health-"* ]]; then
          kubectl_run_output_fixture "$HEALTH_CODE"
        fi
        return 0 ;;
      *)
        return 0 ;;
    esac
  }
  export -f _kubectl
}

@test "deploy_vault -h shows usage" {
  run deploy_vault -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_vault"* ]]
}

@test "deploy_vault loads optional config when vars file exists" {
  local stub_root="${BATS_TEST_TMPDIR}/vault-config"
  mkdir -p "${stub_root}/etc/vault"
  cat <<'EOF' >"${stub_root}/etc/vault/vars.sh"
export TEST_VAULT_OPTIONAL="from-config"
EOF

  SCRIPT_DIR="$stub_root"

  deploy_eso() { return 0; }
  _vault_ns_ensure() { return 0; }
  _vault_repo_setup() { return 0; }
  _deploy_vault_ha() { return 0; }
  _vault_bootstrap_ha() { return 0; }
  _enable_kv2_k8s_auth() { return 0; }

  export -f deploy_eso
  export -f _vault_ns_ensure
  export -f _vault_repo_setup
  export -f _deploy_vault_ha
  export -f _vault_bootstrap_ha
  export -f _enable_kv2_k8s_auth

  WARN_CALLED=0
  WARN_MESSAGE=""
  _warn() { WARN_CALLED=1; WARN_MESSAGE="$*"; }
  export -f _warn

  deploy_vault dev

  [ "$?" -eq 0 ]
  [ "${TEST_VAULT_OPTIONAL:-}" = "from-config" ]
  [ "$WARN_CALLED" -eq 0 ]
  [ -z "$WARN_MESSAGE" ]
}

@test "Namespace setup" {
  KUBECTL_EXIT_CODES=(1 0)
  run _vault_ns_ensure test-ns
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" kubectl_calls
  [ "${kubectl_calls[1]}" = "create ns test-ns" ]
}

@test "Helm repo setup" {
  run _vault_repo_setup
  [ "$status" -eq 0 ]
  read_lines "$HELM_LOG" helm_calls
  [[ "${helm_calls[0]}" == repo\ add\ hashicorp* ]]
  [[ "${helm_calls[1]}" == repo\ update* ]]
}

@test "_is_vault_health treats healthy HTTP statuses as success" {
  local statuses=(200 429 472 473)
  for code in "${statuses[@]}"; do
    _kubectl() {
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --no-exit|--quiet|--prefer-sudo|--require-sudo) shift ;;
          --) shift; break ;;
          *) break ;;
        esac
      done
      echo "VAULT_HTTP_STATUS:${code}"
      return 0
    }
    export -f _kubectl

    run _is_vault_health test-ns test-release
    [ "$status" -eq 0 ]
  done
}

@test "_is_vault_health ignores prompts and deletion digits for healthy status" {
  local statuses=(200 429 472 473)
  for code in "${statuses[@]}"; do
    _kubectl() {
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --no-exit|--quiet|--prefer-sudo|--require-sudo) shift ;;
          --) shift; break ;;
          *) break ;;
        esac
      done

      kubectl_run_output_fixture "$code"
      return 0
    }
    export -f _kubectl

    run _is_vault_health test-ns test-release
    [ "$status" -eq 0 ]
    [[ "$output" == *"return code: ${code}"* ]]
  done
}

@test "_is_vault_health fails for unhealthy HTTP statuses" {
  _kubectl() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--quiet|--prefer-sudo|--require-sudo) shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    echo "VAULT_HTTP_STATUS:503"
    return 0
  }
  export -f _kubectl

  run _is_vault_health test-ns test-release
  [ "$status" -ne 0 ]
  [[ "$output" == *"return code: 503"* ]]
}

@test "_is_vault_health fails for unhealthy status in kubectl run output" {
  local statuses=(500 503)
  for code in "${statuses[@]}"; do
    _kubectl() {
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --no-exit|--quiet|--prefer-sudo|--require-sudo) shift ;;
          --) shift; break ;;
          *) break ;;
        esac
      done

      kubectl_run_output_fixture "$code"
      return 0
    }
    export -f _kubectl

    run _is_vault_health test-ns test-release
    [ "$status" -ne 0 ]
    [[ "$output" == *"return code: ${code}"* ]]
  done
}

@test "_is_vault_health retries unhealthy statuses before succeeding" {
  KUBECTL_RESPONSES=(500 503 200)
  KUBECTL_CALL_FILE="$BATS_TEST_TMPDIR/kubectl-call-count"
  printf '0\n' >"$KUBECTL_CALL_FILE"
  WARN_LOG="$BATS_TEST_TMPDIR/warn.log"
  : >"$WARN_LOG"

  _kubectl() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--quiet|--prefer-sudo|--require-sudo) shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done

    local idx
    idx=$(cat "$KUBECTL_CALL_FILE")
    local response="${KUBECTL_RESPONSES[idx]}"
    printf '%s\n' "$((idx + 1))" >"$KUBECTL_CALL_FILE"
    kubectl_run_output_fixture "$response"
    return 0
  }

  _warn() {
    printf '%s\n' "$*" >>"$WARN_LOG"
  }

  export -f _kubectl
  export -f _warn

  run _is_vault_health test-ns test-release

  [ "$status" -eq 0 ]
  local calls
  calls=$(cat "$KUBECTL_CALL_FILE")
  [ "$calls" -eq 3 ]
  mapfile -t WARN_MESSAGES <"$WARN_LOG"
  [ "${#WARN_MESSAGES[@]}" -eq 2 ]
  [[ "${WARN_MESSAGES[0]}" == *"attempt 1/3"* ]]
  [[ "${WARN_MESSAGES[1]}" == *"attempt 2/3"* ]]
}

@test "_is_vault_health fails after three unhealthy statuses" {
  KUBECTL_RESPONSES=(500 503 501)
  KUBECTL_CALL_FILE="$BATS_TEST_TMPDIR/kubectl-call-count"
  printf '0\n' >"$KUBECTL_CALL_FILE"
  WARN_LOG="$BATS_TEST_TMPDIR/warn.log"
  : >"$WARN_LOG"

  _kubectl() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--quiet|--prefer-sudo|--require-sudo) shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done

    local idx
    idx=$(cat "$KUBECTL_CALL_FILE")
    local response="${KUBECTL_RESPONSES[idx]}"
    printf '%s\n' "$((idx + 1))" >"$KUBECTL_CALL_FILE"
    kubectl_run_output_fixture "$response"
    return 0
  }

  _warn() {
    printf '%s\n' "$*" >>"$WARN_LOG"
  }

  export -f _kubectl
  export -f _warn

  run _is_vault_health test-ns test-release

  [ "$status" -ne 0 ]
  local calls
  calls=$(cat "$KUBECTL_CALL_FILE")
  [ "$calls" -eq 3 ]
  mapfile -t WARN_MESSAGES <"$WARN_LOG"
  [ "${#WARN_MESSAGES[@]}" -eq 2 ]
  [[ "${WARN_MESSAGES[0]}" == *"attempt 1/3"* ]]
  [[ "${WARN_MESSAGES[1]}" == *"attempt 2/3"* ]]
}

@test "_vault_enable_pki skips enabling when mount exists" {
  VAULT_LOGIN_CALLED=0
  VAULT_EXEC_LOG="$BATS_TEST_TMPDIR/vault_exec.log"
  JQ_ARGS_LOG="$BATS_TEST_TMPDIR/jq_args.log"
  : >"$VAULT_EXEC_LOG"
  : >"$JQ_ARGS_LOG"

  jq() {
    printf '%s\n' "$@" >"$JQ_ARGS_LOG"
    cat >/dev/null
    return 0
  }

  _vault_login() { VAULT_LOGIN_CALLED=1; }
  _vault_exec() {
    local ns="$1" cmd="$2" release="$3"
    printf '%s\n' "$cmd" >>"$VAULT_EXEC_LOG"
    if [[ "$cmd" == "vault secrets list -format=json" ]]; then
      printf '{"pki/":{"type":"pki"}}\n'
    fi
    return 0
  }

  export -f jq
  export -f _vault_login
  export -f _vault_exec

  _vault_enable_pki custom-ns custom-release custom-path
  status=$?

  [ "$status" -eq 0 ]
  [ "$VAULT_LOGIN_CALLED" -eq 0 ]
  mapfile -t exec_log <"$VAULT_EXEC_LOG"
  local expected_enable="vault secrets enable -path=custom-path pki"
  local expected_tune="vault secrets tune -max-lease-ttl=${VAULT_PKI_MAX_TTL:-87600h} custom-path"
  [[ "${exec_log[*]}" != *"${expected_enable}"* ]]
  [[ "${exec_log[*]}" == *"${expected_tune}"* ]]
  mapfile -t jq_args <"$JQ_ARGS_LOG"
  [[ "${jq_args[*]}" == "-e --arg PATH custom-path/ has(\$PATH) and .[\$PATH].type == \"pki\"" ]]
}

@test "_vault_pki_issue_tls_secret forwards overrides to secret issuance" {
  : >"$KUBECTL_LOG"

  _is_vault_pki_ready() { return 0; }
  _vault_issue_pki_tls_secret() {
    VAULT_ISSUE_ARGS=("$@")
    _kubectl --no-exit -n "$1" echo "vault_issue_called"
  }

  export -f _is_vault_pki_ready
  export -f _vault_issue_pki_tls_secret

  VAULT_PKI_ISSUE_SECRET=1
  export VAULT_PKI_ISSUE_SECRET

  _vault_pki_issue_tls_secret custom-ns custom-release custom-path custom-role \
    custom.host custom-secret-ns custom-secret-name
  status=$?

  [ "$status" -eq 0 ]
  [ "${VAULT_ISSUE_ARGS[0]}" = "custom-ns" ]
  [ "${VAULT_ISSUE_ARGS[1]}" = "custom-release" ]
  [ "${VAULT_ISSUE_ARGS[2]}" = "custom-path" ]
  [ "${VAULT_ISSUE_ARGS[3]}" = "custom-role" ]
  [ "${VAULT_ISSUE_ARGS[4]}" = "custom.host" ]
  [ "${VAULT_ISSUE_ARGS[5]}" = "custom-secret-ns" ]
  [ "${VAULT_ISSUE_ARGS[6]}" = "custom-secret-name" ]

  read_lines "$KUBECTL_LOG" kubectl_calls
  [ "${kubectl_calls[0]}" = "-n custom-ns echo vault_issue_called" ]
}

@test "_vault_issue_pki_tls_secret revokes existing certificate" {
  local cert_file="$BATS_TEST_TMPDIR/existing.crt"
  local key_file="$BATS_TEST_TMPDIR/existing.key"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$key_file" -out "$cert_file" -days 1 \
    -subj "/CN=jenkins.example" -set_serial 0xBCDA >/dev/null 2>&1
  local expected_serial
  expected_serial=$(extract_certificate_serial "$cert_file")

  local cert_b64
  cert_b64=$(base64 <"$cert_file" | tr -d '\n')
  local secret_json="$BATS_TEST_TMPDIR/secret.json"
  cat <<JSON >"$secret_json"
{"data":{"tls.crt":"$cert_b64"}}
JSON

  local kube_log="$BATS_TEST_TMPDIR/kubectl-existing.log"
  local vault_log="$BATS_TEST_TMPDIR/vault-existing.log"
  : >"$kube_log"
  : >"$vault_log"

  _kubectl() {
    echo "$*" >>"$KUBE_LOG"
    if [[ "$1" == "-n" && "$3" == "get" && "$4" == "secret" ]]; then
      cat "$SECRET_JSON_PATH"
      return 0
    elif [[ "$1" == "apply" && "$2" == "-f" ]]; then
      return 0
    fi
    return 0
  }

  _vault_exec() {
    local cmd="$2"
    echo "$cmd" >>"$VAULT_LOG"
    if [[ "$cmd" == "vault write -format=json pki/issue/jenkins"* ]]; then
      printf '{"data":{"certificate":"NEW_CERT","private_key":"NEW_KEY","issuing_ca":"NEW_CA"}}\n'
    fi
    return 0
  }

  export -f _kubectl
  export -f _vault_exec

  KUBE_LOG="$kube_log"
  VAULT_LOG="$vault_log"
  SECRET_JSON_PATH="$secret_json"
  export KUBE_LOG VAULT_LOG SECRET_JSON_PATH

  _vault_issue_pki_tls_secret

  read_lines "$vault_log" vault_calls
  local revoke_cmd="vault write pki/revoke serial_number=${expected_serial}"
  [[ "${vault_calls[*]}" == *"${revoke_cmd}"* ]]
}

@test "_vault_issue_pki_tls_secret skips revoke when secret missing" {
  local kube_log="$BATS_TEST_TMPDIR/kubectl-missing.log"
  local vault_log="$BATS_TEST_TMPDIR/vault-missing.log"
  : >"$kube_log"
  : >"$vault_log"

  _kubectl() {
    echo "$*" >>"$KUBE_LOG"
    if [[ "$1" == "-n" && "$3" == "get" && "$4" == "secret" ]]; then
      return 1
    elif [[ "$1" == "apply" && "$2" == "-f" ]]; then
      return 0
    fi
    return 0
  }

  _vault_exec() {
    local cmd="$2"
    echo "$cmd" >>"$VAULT_LOG"
    if [[ "$cmd" == "vault write -format=json pki/issue/jenkins"* ]]; then
      printf '{"data":{"certificate":"NEW_CERT","private_key":"NEW_KEY","issuing_ca":"NEW_CA"}}\n'
    fi
    return 0
  }

  export -f _kubectl
  export -f _vault_exec

  KUBE_LOG="$kube_log"
  VAULT_LOG="$vault_log"
  export KUBE_LOG VAULT_LOG

  _vault_issue_pki_tls_secret

  read_lines "$vault_log" vault_calls
  local revoke_cmd="vault write pki/revoke serial_number="
  [[ "${vault_calls[*]}" != *"${revoke_cmd}"* ]]
}

@test "Full deployment" {
  _vault_ns_ensure() { CALLS+=("_vault_ns_ensure"); }
  _vault_repo_setup() { CALLS+=("_vault_repo_setup"); }
  _deploy_vault_ha() { CALLS+=("_deploy_vault_ha"); }
  _vault_bootstrap_ha() { CALLS+=("_vault_bootstrap_ha"); }
  _enable_kv2_k8s_auth() { CALLS+=("_enable_kv2_k8s_auth"); }

  export -f _vault_ns_ensure
  export -f _vault_repo_setup
  export -f _deploy_vault_ha
  export -f _vault_bootstrap_ha
  export -f _enable_kv2_k8s_auth

  deploy_vault ha sample-ns
  [ "$?" -eq 0 ]
  expected=(deploy_eso _vault_ns_ensure _vault_repo_setup _deploy_vault_ha _vault_bootstrap_ha _enable_kv2_k8s_auth)
  [ "${#CALLS[@]}" -eq "${#expected[@]}" ]
  for i in "${!expected[@]}"; do
    [ "${CALLS[$i]}" = "${expected[$i]}" ]
  done
}

@test "_vault_bootstrap_ha uses release selector and unseals listed pods" {
  TEST_NS="custom-ns"
  TEST_RELEASE="custom-release"
  TEST_POD="${TEST_RELEASE}-0"
  TEST_POD_RESOURCE="pod/${TEST_POD}"
  : >"$KUBECTL_LOG"

  _is_vault_deployed() { return 0; }
  _run_command() { return 1; }
  _no_trace() { "$@"; }
  _info() { :; }
  _warn() { :; }
  _is_vault_health() { return 0; }
  _vault_portforward_help() { :; }

  export -f _is_vault_deployed
  export -f _run_command
  export -f _no_trace
  export -f _info
  export -f _warn
  export -f _is_vault_health
  export -f _vault_portforward_help

  _kubectl() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--quiet|--prefer-sudo|--require-sudo) shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    local cmd="$*"
    echo "$cmd" >>"$KUBECTL_LOG"
    case "$cmd" in
      "wait -n ${TEST_NS} --for=condition=Podscheduled ${TEST_POD_RESOURCE} --timeout=120s")
        return 0 ;;
      "-n ${TEST_NS} get pod ${TEST_POD} -o jsonpath={.status.phase}")
        echo "Running"
        return 0 ;;
      "-n ${TEST_NS} exec -i ${TEST_POD} -- vault status -format json")
        echo '{"initialized": false}'
        return 0 ;;
      "-n ${TEST_NS} exec -it ${TEST_POD} -- sh -lc vault operator init -key-shares=1 -key-threshold=1 -format=json")
        printf '{"root_token":"root","unseal_keys_b64":["key"]}\n'
        return 0 ;;
      "-n ${TEST_NS} create secret generic vault-root --from-literal=root_token=root")
        return 0 ;;
      "-n ${TEST_NS} get pod -l app.kubernetes.io/name=vault,app.kubernetes.io/instance=${TEST_RELEASE} -o name")
        echo "pod/${TEST_POD}"
        return 0 ;;
      "-n ${TEST_NS} exec -i ${TEST_POD} -- sh -lc vault operator unseal key")
        return 0 ;;
      *)
        return 0 ;;
    esac
  }
  export -f _kubectl

  run _vault_bootstrap_ha "$TEST_NS" "$TEST_RELEASE"
  [ "$status" -eq 0 ]

  read_lines "$KUBECTL_LOG" kubectl_calls
  expected_wait="wait -n ${TEST_NS} --for=condition=Podscheduled ${TEST_POD_RESOURCE} --timeout=120s"
  expected_get="-n ${TEST_NS} get pod ${TEST_POD} -o jsonpath={.status.phase}"
  expected_status="-n ${TEST_NS} exec -i ${TEST_POD} -- vault status -format json"
  expected_init="-n ${TEST_NS} exec -it ${TEST_POD} -- sh -lc vault operator init -key-shares=1 -key-threshold=1 -format=json"
  expected_selector="-n ${TEST_NS} get pod -l app.kubernetes.io/name=vault,app.kubernetes.io/instance=${TEST_RELEASE} -o name"
  expected_unseal="-n ${TEST_NS} exec -i ${TEST_POD} -- sh -lc vault operator unseal key"

  expected_calls=(
    "$expected_wait"
    "$expected_get"
    "$expected_status"
    "$expected_init"
    "$expected_selector"
    "$expected_unseal"
  )

  for expected_call in "${expected_calls[@]}"; do
    call_found=0
    for call in "${kubectl_calls[@]}"; do
      if [[ "$call" == "$expected_call" ]]; then
        call_found=1
        break
      fi
    done
    [ "$call_found" -eq 1 ]
  done
}

@test "_vault_bootstrap_ha errors when vault health check fails" {
  setup_vault_bootstrap_stubs

  ERR_LOG="$BATS_TEST_TMPDIR/err.log"
  INFO_LOG="$BATS_TEST_TMPDIR/info.log"
  PORT_LOG="$BATS_TEST_TMPDIR/port.log"
  : >"$ERR_LOG"
  : >"$INFO_LOG"
  : >"$PORT_LOG"

  _err() { printf '%s\n' "$*" >>"$ERR_LOG"; return 1; }
  _info() { printf '%s\n' "$*" >>"$INFO_LOG"; }
  _is_vault_health() { _info "return code: 503"; return 1; }
  _vault_portforward_help() { echo called >>"$PORT_LOG"; }

  export -f _err
  export -f _info
  export -f _is_vault_health
  export -f _vault_portforward_help

  run _vault_bootstrap_ha "$TEST_NS" "$TEST_RELEASE"
  [ "$status" -ne 0 ]

  read_lines "$ERR_LOG" err_messages
  read_lines "$INFO_LOG" info_messages
  read_lines "$PORT_LOG" port_calls

  [ "${#port_calls[@]}" -eq 0 ]
  [ "${#err_messages[@]}" -eq 1 ]
  [[ "${err_messages[0]}" == *"vault not healthy after init/unseal"* ]]
  for msg in "${info_messages[@]}"; do
    [[ "$msg" != "[vault] vault is ready to serve" ]]
  done
}

@test "_vault_bootstrap_ha reports ready when health check succeeds" {
  setup_vault_bootstrap_stubs

  INFO_LOG="$BATS_TEST_TMPDIR/info.log"
  PORT_LOG="$BATS_TEST_TMPDIR/port.log"
  ERR_LOG="$BATS_TEST_TMPDIR/err.log"
  : >"$INFO_LOG"
  : >"$PORT_LOG"
  : >"$ERR_LOG"

  _info() { printf '%s\n' "$*" >>"$INFO_LOG"; }
  _is_vault_health() { _info "return code: 200"; return 0; }
  _err() { printf '%s\n' "$*" >>"$ERR_LOG"; return 1; }
  _vault_portforward_help() { echo called >>"$PORT_LOG"; }

  export -f _info
  export -f _is_vault_health
  export -f _err
  export -f _vault_portforward_help

  run _vault_bootstrap_ha "$TEST_NS" "$TEST_RELEASE"
  [ "$status" -eq 0 ]

  read_lines "$ERR_LOG" err_messages
  read_lines "$PORT_LOG" port_calls
  read_lines "$INFO_LOG" info_messages

  [ "${#err_messages[@]}" -eq 0 ]
  [ "${#port_calls[@]}" -eq 1 ]

  ready_found=0
  for msg in "${info_messages[@]}"; do
    if [[ "$msg" == "[vault] vault is ready to serve" ]]; then
      ready_found=1
    fi
  done
  [ "$ready_found" -eq 1 ]
}
