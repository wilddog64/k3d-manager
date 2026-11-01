#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  platform_ops_dir="${SCRIPT_DIR}/etc/argocd/platform-ops"
}

scan_legacy_base64() {
  grep -rn -- 'base64 --decode' "$1"
}

@test "container templates use BusyBox-compatible base64 -d" {
  run scan_legacy_base64 "${SCRIPT_DIR}/etc"
  [ "$status" -eq 1 ]
}

@test "base64 guard detects a planted invocation in a scratch tree" {
  scratch_etc="${BATS_TEST_TMPDIR}/etc"
  mkdir -p "${scratch_etc}/ldap"
  printf '%s\n' 'base64 --decode' > "${scratch_etc}/ldap/planted.yaml.tmpl"
  run scan_legacy_base64 "$scratch_etc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"${scratch_etc}/ldap/planted.yaml.tmpl"* ]]
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
