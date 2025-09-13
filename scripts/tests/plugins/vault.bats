#!/usr/bin/env bats

setup() {
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

@test "Namespace setup" {
  KUBECTL_EXIT_CODES=(1 0)
  run _vault_ns_ensure test-ns
  [ "$status" -eq 0 ]
  mapfile -t kubectl_calls <"$KUBECTL_LOG"
  [ "${kubectl_calls[1]}" = "create ns test-ns" ]
}

@test "Helm repo setup" {
  run _vault_repo_setup
  [ "$status" -eq 0 ]
  mapfile -t helm_calls <"$HELM_LOG"
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
