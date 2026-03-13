#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  export ACME_EMAIL="user@example.com"
  source "${BATS_TEST_DIRNAME}/../../plugins/cert-manager.sh"
  : > "$KUBECTL_LOG"
  : > "$HELM_LOG"
}

@test "deploy_cert_manager fails when ACME_EMAIL is unset" {
  unset ACME_EMAIL
  run deploy_cert_manager
  [ "$status" -ne 0 ]
  [[ "$output" == *"ACME_EMAIL is required"* ]]
}

@test "deploy_cert_manager --help prints usage" {
  run deploy_cert_manager --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_cert_manager"* ]]
}

@test "_cert_manager_helm_install skips repo ops for local chart path" {
  CERT_MANAGER_HELM_CHART_REF="$BATS_TEST_TMPDIR/local-chart.tgz"
  CERT_MANAGER_HELM_REPO_URL=""
  touch "$CERT_MANAGER_HELM_CHART_REF"
  run _cert_manager_helm_install
  [ "$status" -eq 0 ]
  read_lines "$HELM_LOG" helm_calls
  [ "${#helm_calls[@]}" -eq 1 ]
  [[ "${helm_calls[0]}" == upgrade\ --install* ]]
}

@test "_cert_manager_apply_issuer renders staging ClusterIssuer" {
  local rendered="$BATS_TEST_TMPDIR/staging-rendered.yaml"
  ACME_EMAIL="staging@example.com"
  CERT_MANAGER_DEBUG_RENDER="$rendered" run _cert_manager_apply_issuer staging
  [ "$status" -eq 0 ]
  grep -q "$ACME_STAGING_SERVER" "$rendered"
  grep -q "$ACME_EMAIL" "$rendered"
}

@test "_cert_manager_apply_issuer renders production ClusterIssuer" {
  local rendered="$BATS_TEST_TMPDIR/prod-rendered.yaml"
  ACME_EMAIL="prod@example.com"
  CERT_MANAGER_DEBUG_RENDER="$rendered" run _cert_manager_apply_issuer production
  [ "$status" -eq 0 ]
  grep -q "$ACME_PRODUCTION_SERVER" "$rendered"
  grep -q "$ACME_EMAIL" "$rendered"
}

@test "_cert_manager_apply_issuer fails when ACME_EMAIL empty" {
  ACME_EMAIL=""
  run _cert_manager_apply_issuer staging
  [ "$status" -ne 0 ]
  [[ "$output" == *"ACME_EMAIL must be set"* ]]
}

@test "deploy_cert_manager warns for production on k3d" {
  CLUSTER_PROVIDER="k3d"
  run deploy_cert_manager --production
  [ "$status" -eq 0 ]
  [[ "$output" == *"Production issuers require"* ]]
}

@test "deploy_cert_manager warns for production on orbstack" {
  CLUSTER_PROVIDER="orbstack"
  run deploy_cert_manager --production
  [ "$status" -eq 0 ]
  [[ "$output" == *"Production issuers require"* ]]
}

@test "deploy_cert_manager --skip-issuer avoids ClusterIssuer apply" {
  run deploy_cert_manager --skip-issuer
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" calls
  local apply_count=0
  for cmd in "${calls[@]}"; do
    if [[ "$cmd" == *"apply"* ]]; then
      ((apply_count++))
    fi
  done
  [ "$apply_count" -eq 0 ]
}

@test "deploy_cert_manager --skip-issuer waits for webhook only" {
  run deploy_cert_manager --skip-issuer
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" calls
  [[ "${calls[*]}" == *"deployment/cert-manager-webhook"* ]]
}
