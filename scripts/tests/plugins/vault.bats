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

  export -f _kubectl
  export -f _helm
  export -f deploy_eso
}

kubectl_run_output_fixture() {
  local status="$1"
  cat <<EOF
If you don't see a command prompt, try pressing enter.

pod "vault-health-123" deleted
command terminated with exit code 0
${status}
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
          echo "$HEALTH_CODE"
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
      echo "$code"
      return 0
    }
    export -f _kubectl

    run _is_vault_health test-ns test-release
    [ "$status" -eq 0 ]
  done
}

@test "_is_vault_health ignores kubectl run prompts for healthy status" {
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
    echo 503
    return 0
  }
  export -f _kubectl

  run _is_vault_health test-ns test-release
  [ "$status" -ne 0 ]
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
  done
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
