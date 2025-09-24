#!/usr/bin/env bats

load '../test_helpers.bash'

setup() {
  init_test_env
  export CLUSTER_PROVIDER=k3d

  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  export -f deploy_cluster

  source "${BATS_TEST_DIRNAME}/../../lib/providers/k3s.sh"
  eval "$(declare -f _provider_k3s_deploy_cluster | sed '1s/_provider_k3s_deploy_cluster/orig_provider_k3s_deploy_cluster/')"

  stub_kubectl
  stub_run_command

  _is_mac() { return 1; }
  _is_wsl() { return 1; }
  _is_debian_family() { return 1; }
  _is_redhat_family() { return 1; }
  _is_linux() { return 0; }
  export -f _is_mac _is_wsl _is_debian_family _is_redhat_family _is_linux

  _provider_k3s_deploy_cluster() {
    printf '%s\n' "$@" > "$BATS_TMPDIR/provider_args"
    printf '%s\n' "${CLUSTER_PROVIDER:-}" > "$BATS_TMPDIR/provider_env"
    return 0
  }
  export -f _provider_k3s_deploy_cluster

  _cluster_provider_mark_loaded k3s
}

@test "deploy_cluster with explicit provider passes cluster name" {
  run deploy_cluster --provider k3s foo

  [ "$status" -eq 0 ]
  [[ -f "$BATS_TMPDIR/provider_args" ]]
  [[ -f "$BATS_TMPDIR/provider_env" ]]

  mapfile -t args < "$BATS_TMPDIR/provider_args"
  [ "${#args[@]}" -eq 1 ]
  [ "${args[0]}" = "foo" ]

  read -r provider_env < "$BATS_TMPDIR/provider_env"
  [ "$provider_env" = "k3s" ]
}

@test "k3s deploy cluster configures istio" {
  export CLUSTER_PROVIDER=k3s

  local istio_log="$BATS_TMPDIR/istio.log"
  : > "$istio_log"

  _install_k3s() { :; }
  _deploy_k3s_cluster() { :; }
  _install_istioctl() { echo "install_istioctl" >> "$istio_log"; }
  _istioctl() { echo "istioctl $*" >> "$istio_log"; }
  export -f _install_k3s _deploy_k3s_cluster _install_istioctl _istioctl

  orig_provider_k3s_deploy_cluster foo

  read_lines "$istio_log" istio_lines
  [ "${#istio_lines[@]}" -ge 3 ]
  [ "${istio_lines[0]}" = "install_istioctl" ]
  [[ "${istio_lines[1]}" = "istioctl x precheck" ]]
  [[ "${istio_lines[2]}" =~ ^istioctl\ install\ -y\ -f\  ]]

  read_lines "$KUBECTL_LOG" kubectl_lines
  [ "${#kubectl_lines[@]}" -ge 1 ]
  local last_index=$(( ${#kubectl_lines[@]} - 1 ))
  [ "${kubectl_lines[$last_index]}" = "label ns default istio-injection=enabled --overwrite" ]
}
