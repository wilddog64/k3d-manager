#!/usr/bin/env bats
setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.kube"
  [[ "$HOME" == "$BATS_TEST_TMPDIR/home" ]]
  SCRIPT_DIR="$REPO/scripts"

  source "$REPO/scripts/lib/providers/k3s-hostinger.sh"
  _HOSTINGER_KUBE_CONTEXT=ubuntu-hostinger
  _HOSTINGER_KUBECONFIG="$HOME/.kube/hostinger.config"
  _hostinger_require_host() { :; }
  _info() { :; }
  kubectl() { return "${CONTEXT_MISSING:-0}"; }
  _hostinger_merge_kubeconfig() { echo merged; }
  _hostinger_register_cluster() { echo registered; }
}
@test "refresh registration merges a saved config when context is absent" {
  : > "$_HOSTINGER_KUBECONFIG"
  export CONTEXT_MISSING=1
  run _provider_k3s_hostinger_refresh_registration
  [ "$status" -eq 0 ]
  [[ "$output" == *merged*registered* ]]
}
@test "refresh registration reports missing config" {
  export CONTEXT_MISSING=1
  run _provider_k3s_hostinger_refresh_registration
  [ "$status" -ne 0 ]
  [[ "$output" == *'copy it from the old hub first'* ]]
  [[ "$output" != *registered* ]]
}
@test "refresh registration retains an existing context" {
  run _provider_k3s_hostinger_refresh_registration
  [ "$status" -eq 0 ]
  [[ "$output" == *registered* && "$output" != *merged* ]]
}
