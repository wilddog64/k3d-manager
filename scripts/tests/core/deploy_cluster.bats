#!/usr/bin/env bats

load '../test_helpers.bash'

setup() {
  init_test_env
  export CLUSTER_PROVIDER=k3d

  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"

  source "${BATS_TEST_DIRNAME}/../../lib/providers/k3s.sh"

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
