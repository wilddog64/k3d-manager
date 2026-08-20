#!/usr/bin/env bats
# shellcheck shell=bash

@test "_provider_k3s_aws_deploy_cluster --help prints k3s-aws usage" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    # stub sourced plugins to avoid side-effects
    acg_provision() { return 0; }
    deploy_app_cluster() { return 0; }
    tunnel_start() { return 0; }
    source scripts/lib/providers/k3s-aws.sh
    _provider_k3s_aws_deploy_cluster --help
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3s-aws"* ]]
}

@test "_provider_k3s_aws_destroy_cluster --help prints k3s-aws usage" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    acg_teardown() { return 0; }
    tunnel_stop() { return 0; }
    source scripts/lib/providers/k3s-aws.sh
    _provider_k3s_aws_destroy_cluster --help
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3s-aws"* ]]
}

@test "_provider_k3s_aws_destroy_cluster without --confirm fails" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    acg_teardown() { return 0; }
    tunnel_stop() { return 0; }
    source scripts/lib/providers/k3s-aws.sh
    _provider_k3s_aws_destroy_cluster
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"--confirm"* ]]
}

@test "_provider_k3s_aws_deploy_cluster runs acg_provision once" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/lib/providers/k3s-aws.sh
    # stubs after source — override real implementations from acg.sh
    _acg_extend_playwright() { return 0; }
    acg_provision() { echo "[stub] acg_provision"; return 0; }
    deploy_app_cluster() { return 0; }
    tunnel_start() { return 0; }
    kubectl() { printf "n1 Ready\nn2 Ready\nn3 Ready\n"; }
    acg_watch() { return 0; }
    _ACG_WATCH_PID_FILE="$(mktemp)"; rm -f "$_ACG_WATCH_PID_FILE"
    _provider_k3s_aws_deploy_cluster
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"[stub] acg_provision"* ]]
  [ "$(echo "$output" | grep -c "\[stub\] acg_provision")" -eq 1 ]
}

@test "k3s-aws retries app provisioning over SSH after SSM bootstrap fails" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/lib/providers/k3s-aws.sh
    _provider_k3s_aws_autoselect_tunnel_mode() { export K3S_AWS_SSM_ENABLED=true; }
    _acg_extend_playwright() { return 0; }
    acg_provision() { return 0; }
    deploy_calls=0
    deploy_app_cluster() {
      deploy_calls=$((deploy_calls + 1))
      printf "[stub] deploy %s mode=%s\n" "$deploy_calls" "${K3S_AWS_SSM_ENABLED}"
      [[ "${K3S_AWS_SSM_ENABLED}" == "true" ]] && return 1
      return 0
    }
    _provider_k3s_aws_start_tunnel() { return 0; }
    KUBECTL_SEEN="$(mktemp)"; rm -f "${KUBECTL_SEEN}"
    kubectl() {
      if [[ ! -e "${KUBECTL_SEEN}" ]]; then touch "${KUBECTL_SEEN}"; return 1; fi
      printf "n1 Ready\nn2 Ready\nn3 Ready\n"
    }
    acg_watch() { return 0; }
    _ACG_WATCH_PID_FILE="$(mktemp)"; rm -f "${_ACG_WATCH_PID_FILE}"
    _provider_k3s_aws_deploy_cluster
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"Provisioning app cluster via SSM (SSH fallback armed)"* ]]
  [[ "$output" == *"SSM bootstrap failed — falling back to SSH provisioning"* ]]
  [[ "$output" == *"Switching transport: SSM -> SSH; retrying app provisioning"* ]]
  [[ "$output" == *"SSH provisioning retry succeeded"* ]]
  [[ "$output" == *"[stub] deploy 1 mode=true"* ]]
  [[ "$output" == *"[stub] deploy 2 mode=false"* ]]
}

@test "k3s-aws uses SSH when the laptop Vault reverse bridge is required" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/lib/providers/k3s-aws.sh
    unset K3S_AWS_SSM_ENABLED
    export HUB_VAULT_USE_BRIDGE=1
    _provider_k3s_aws_autoselect_tunnel_mode
    printf "mode=%s\n" "${K3S_AWS_SSM_ENABLED}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"Vault reverse bridge required — using SSH"* ]]
  [[ "$output" == *"mode=false"* ]]
}

@test "k3s-aws overrides explicit SSM when the laptop Vault reverse bridge is required" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/lib/providers/k3s-aws.sh
    export K3S_AWS_SSM_ENABLED=true HUB_VAULT_USE_BRIDGE=1
    _provider_k3s_aws_autoselect_tunnel_mode
    printf "mode=%s\n" "${K3S_AWS_SSM_ENABLED}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"Vault reverse bridge requires SSH"* ]]
  [[ "$output" == *"mode=false"* ]]
}

@test "k3s-aws fails when SSM bootstrap and SSH retry both fail" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/lib/providers/k3s-aws.sh
    _provider_k3s_aws_autoselect_tunnel_mode() { export K3S_AWS_SSM_ENABLED=true; }
    _acg_extend_playwright() { return 0; }
    acg_provision() { return 0; }
    deploy_app_cluster() { return 1; }
    _provider_k3s_aws_start_tunnel() { return 0; }
    KUBECTL_SEEN="$(mktemp)"; rm -f "${KUBECTL_SEEN}"
    kubectl() {
      if [[ ! -e "${KUBECTL_SEEN}" ]]; then touch "${KUBECTL_SEEN}"; return 1; fi
      printf "n1 Ready\nn2 Ready\nn3 Ready\n"
    }
    _ACG_WATCH_PID_FILE="$(mktemp)"; rm -f "${_ACG_WATCH_PID_FILE}"
    _provider_k3s_aws_deploy_cluster
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"SSM bootstrap failed — falling back to SSH provisioning"* ]]
}

@test "_provider_k3s_aws_destroy_cluster --confirm runs acg_teardown" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/lib/providers/k3s-aws.sh
    # stubs after source — override real implementations from acg.sh
    _k3s_aws_deregister_cluster() { echo "[stub] deregister"; return 0; }
    acg_teardown() { echo "[stub] acg_teardown"; return 0; }
    tunnel_stop() { return 0; }
    _ACG_WATCH_PID_FILE="$(mktemp)"; rm -f "$_ACG_WATCH_PID_FILE"
    _provider_k3s_aws_destroy_cluster --confirm
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"[stub] deregister"* ]]
  [[ "$output" == *"[stub] acg_teardown"* ]]
  [ "$(printf "%s\n" "$output" | grep -n "\[stub\] deregister" | cut -d: -f1)" -lt \
    "$(printf "%s\n" "$output" | grep -n "\[stub\] acg_teardown" | cut -d: -f1)" ]
}

@test "_k3s_aws_deregister_cluster DRY_RUN describes the hub cleanup" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/lib/providers/k3s-aws.sh
    DRY_RUN=1 _k3s_aws_deregister_cluster
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY_RUN: delete hub ArgoCD secret cluster-ubuntu-k3s in cicd"* ]]
  [[ "$output" == *"generated Applications targeting ubuntu-k3s"* ]]
}

@test "_k3s_aws_deregister_cluster deletes only ubuntu-k3s hub objects" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/lib/providers/k3s-aws.sh
    LOG="$(mktemp)"
    _argocd_hub_kubectl_cmd() { echo kubectl; }
    kubectl() {
      printf "%s\n" "$*" >> "$LOG"
      case "$*" in
        *"get applications"*) printf "%s\n" "application/ubuntu-k3s-shopping-cart-payment" ;;
      esac
      return 0
    }
    _k3s_aws_deregister_cluster
    cat "$LOG"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"delete secret cluster-ubuntu-k3s"* ]]
  [[ "$output" == *"patch application/ubuntu-k3s-shopping-cart-payment"* ]]
  [[ "$output" == *"delete application/ubuntu-k3s-shopping-cart-payment"* ]]
  [[ "$output" != *"ubuntu-hostinger"* ]]
}

@test "_k3s_aws_deregister_cluster is idempotent when hub objects are absent" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/lib/providers/k3s-aws.sh
    _argocd_hub_kubectl_cmd() { echo kubectl; }
    kubectl() { return 1; }
    _k3s_aws_deregister_cluster
  '
  [ "$status" -eq 0 ]
}

@test "k3s-aws keeps SSM when registration and tunnel succeed" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/lib/providers/k3s-aws.sh
    _ssm_get_instance_id() { echo i-test; }
    _provider_k3s_aws_wait_ssm_registered() { return 0; }
    ssm_tunnel() { echo "[stub] ssm_tunnel $*"; return 0; }
    tunnel_start() { echo "[stub] tunnel_start"; return 0; }
    K3S_AWS_SSM_ENABLED=true _provider_k3s_aws_start_tunnel
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"[stub] ssm_tunnel i-test 6443 6443"* ]]
  [[ "$output" != *"[stub] tunnel_start"* ]]
}

@test "k3s-aws falls back to SSH when SSM registration fails" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/lib/providers/k3s-aws.sh
    _ssm_get_instance_id() { echo i-test; }
    _provider_k3s_aws_wait_ssm_registered() { return 1; }
    ssm_tunnel() { return 1; }
    tunnel_start() { echo "[stub] tunnel_start"; return 0; }
    K3S_AWS_SSM_ENABLED=true _provider_k3s_aws_start_tunnel
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"falling back to SSH tunnel"* ]]
  [[ "$output" == *"[stub] tunnel_start"* ]]
}

@test "k3s-aws fails when both SSM and SSH tunnels fail" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    source scripts/lib/providers/k3s-aws.sh
    _ssm_get_instance_id() { echo i-test; }
    _provider_k3s_aws_wait_ssm_registered() { return 1; }
    tunnel_start() { return 1; }
    K3S_AWS_SSM_ENABLED=true _provider_k3s_aws_start_tunnel
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"falling back to SSH tunnel"* ]]
}
