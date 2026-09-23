#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  platform_ops_dir="${SCRIPT_DIR}/etc/argocd/platform-ops"
}

@test "platform-ops rotators use BusyBox-compatible base64 -d" {
  run grep -rn -- 'base64 --decode' "${platform_ops_dir}"
  [ "$status" -ne 0 ]
}

@test "platform-ops rotators decode Kubernetes Secret data" {
  for manifest in \
    "${platform_ops_dir}/keycloak-credential-rotator.yaml" \
    "${platform_ops_dir}/argocd-credential-rotator.yaml" \
    "${platform_ops_dir}/grafana-credential-rotator.yaml"; do
    run grep -F -- 'base64 -d' "${manifest}"
    [ "$status" -eq 0 ]
  done
}
