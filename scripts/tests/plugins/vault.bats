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

@test "_vault_bootstrap_ha lists pods in provided namespace" {
  TEST_NS="custom-ns"
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
      "wait -n ${TEST_NS} --for=condition=Podscheduled pod/vault-0 --timeout=120s")
        return 0 ;;
      "-n ${TEST_NS} get pod vault-0 -o jsonpath={.status.phase}")
        echo "Running"
        return 0 ;;
      "-n ${TEST_NS} exec -i vault-0 -- vault status -format json")
        echo '{"initialized": false}'
        return 0 ;;
      "-n ${TEST_NS} exec -it vault-0 -- sh -lc vault operator init -key-shares=1 -key-threshold=1 -format=json")
        printf '{"root_token":"root","unseal_keys_b64":["key"]}\n'
        return 0 ;;
      "-n ${TEST_NS} create secret generic vault-root --from-literal=root_token=root")
        return 0 ;;
      "-n ${TEST_NS} get pod -l app.kubernetes.io/name=vault,app.kubernetes.io/instance=vault -o name")
        echo "pod/vault-0"
        return 0 ;;
      "-n ${TEST_NS} exec -i vault-0 -- sh -lc vault operator unseal key")
        return 0 ;;
      *)
        return 0 ;;
    esac
  }
  export -f _kubectl

  run _vault_bootstrap_ha "$TEST_NS"
  [ "$status" -eq 0 ]

  read_lines "$KUBECTL_LOG" kubectl_calls
  expected="-n ${TEST_NS} get pod -l app.kubernetes.io/name=vault,app.kubernetes.io/instance=vault -o name"
  found=0
  for call in "${kubectl_calls[@]}"; do
    if [[ "$call" == "$expected" ]]; then
      found=1
      break
    fi
  done
  [ "$found" -eq 1 ]
}
