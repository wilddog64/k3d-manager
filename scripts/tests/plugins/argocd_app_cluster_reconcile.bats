#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  export ARGOCD_APP_CLUSTER_TABLE="${BATS_TEST_TMPDIR}/app-clusters.tsv"
  export K3DM_DISPATCHER="${BATS_TEST_TMPDIR}/dispatcher"
  export DISPATCHER_LOG="${BATS_TEST_TMPDIR}/dispatcher.log"
  cat >"${K3DM_DISPATCHER}" <<'STUB'
#!/usr/bin/env bash
printf 'provider=%s args=%s\n' "${CLUSTER_PROVIDER:-unset}" "$*" >>"${DISPATCHER_LOG}"
if [[ "${DISPATCHER_FAIL:-false}" == "true" ]]; then
  exit 1
fi
STUB
  chmod +x "${K3DM_DISPATCHER}"
  kubectl() {
    if [[ "$1" == "config" ]]; then
      [[ "${CONTEXT_PRESENT:-true}" == "true" ]]
      return
    fi
    [[ "${SECRET_PRESENT:-false}" == "true" ]]
  }
  _argocd_hub_kubectl_cmd() { printf 'kubectl'; }
  export -f kubectl
  printf '# context\tsecret\tprovider\n\napp-context\tapp-secret\tk3s-hostinger\n' >"${ARGOCD_APP_CLUSTER_TABLE}"
}

@test "missing secret and present context dispatches the row provider" {
  run argocd_reconcile_app_cluster_registrations
  [ "$status" -eq 0 ]
  [[ "$(<"${DISPATCHER_LOG}")" == *"refresh_registration"* ]]
  [[ "$(<"${DISPATCHER_LOG}")" == *"provider=k3s-hostinger"* ]]
  [[ "$output" == *"1 restored, 0 still missing"* ]]
}

@test "present secret does not dispatch" {
  SECRET_PRESENT=true run argocd_reconcile_app_cluster_registrations
  [ "$status" -eq 0 ]
  [ ! -s "${DISPATCHER_LOG}" ]
  [[ "$output" == *"already registered"* ]]
}

@test "missing kubeconfig context is skipped successfully" {
  CONTEXT_PRESENT=false run argocd_reconcile_app_cluster_registrations
  [ "$status" -eq 0 ]
  [ ! -s "${DISPATCHER_LOG}" ]
  [[ "$output" == *"no kubeconfig context"* ]]
}

@test "dispatcher failure keeps reconcile successful and emits a gap banner" {
  DISPATCHER_FAIL=true run argocd_reconcile_app_cluster_registrations
  [ "$status" -eq 0 ]
  [[ "$output" == *"APP-CLUSTER REGISTRATION GAP"* ]]
  [[ "$output" == *"1 still missing"* ]]
}

@test "exclusive mode refuses to reconcile" {
  K3DM_EXCLUSIVE_APP_CLUSTER=true run argocd_reconcile_app_cluster_registrations
  [ "$status" -ne 0 ]
  [ ! -s "${DISPATCHER_LOG}" ]
  [[ "$output" == *"additive-only"* ]]
}

@test "comment header and blank lines are skipped" {
  printf '# context\tsecret\tprovider\n\napp-context\tapp-secret\tk3s-hostinger\n' >"${ARGOCD_APP_CLUSTER_TABLE}"
  run argocd_reconcile_app_cluster_registrations
  [ "$status" -eq 0 ]
  [ "$(wc -l <"${DISPATCHER_LOG}" | tr -d ' ')" -eq 1 ]
}
