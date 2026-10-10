#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  K3D_MANAGER_BRANCH=k3d-manager-v1.43.0
  export K3D_MANAGER_BRANCH
  K3DM_APPSETS_STAGE=hub
  export K3DM_APPSETS_STAGE
  CALLS="${BATS_TEST_TMPDIR}/confirmation-calls"
  : > "${CALLS}"
}

@test "appsets reapply confirmation: retries until the values branch passes" {
  _argocd_deploy_applicationsets() { return 0; }
  argocd_check_values_branch() {
    local confirm_calls
    printf x >> "${CALLS}"
    confirm_calls="$(wc -c < "${CALLS}")"
    (( confirm_calls < 3 )) && return 1
    return 0
  }
  sleep() { :; }

  run deploy_argocd_applicationsets
  [ "${status}" -eq 0 ]
  [ "$(wc -c < "${CALLS}")" -eq 3 ]
  [[ "${output}" == *"waiting for ApplicationSet controller"* ]]
}

@test "appsets reapply confirmation: final stale output is shown after timeout" {
  _argocd_deploy_applicationsets() { return 0; }
  argocd_check_values_branch() {
    local confirm_calls
    printf x >> "${CALLS}"
    confirm_calls="$(wc -c < "${CALLS}")"
    printf 'STALE-CHECK-%s\n' "${confirm_calls}"
    return 1
  }
  sleep() { :; }

  K3DM_APPSET_CONFIRM_TIMEOUT=10 K3DM_APPSET_CONFIRM_INTERVAL=5 \
    run deploy_argocd_applicationsets
  [ "${status}" -eq 1 ]
  [ "$(wc -c < "${CALLS}")" -eq 3 ]
  [[ "${output}" == *"STALE-CHECK-3"* ]]
  [[ "${output}" != *"STALE-CHECK-1"* ]]
  [[ "${output}" != *"STALE-CHECK-2"* ]]
}

@test "appsets reapply confirmation: invalid timing values fall back to the defaults" {
  _argocd_deploy_applicationsets() { return 0; }
  argocd_check_values_branch() { printf x >> "${CALLS}"; return 1; }
  sleep() { :; }

  K3DM_APPSET_CONFIRM_TIMEOUT='a[$(touch "${BATS_TEST_TMPDIR}/pwned")]' K3DM_APPSET_CONFIRM_INTERVAL=0 \
    run deploy_argocd_applicationsets
  [ "${status}" -eq 1 ]
  [ "$(wc -c < "${CALLS}")" -eq 19 ]
  [ ! -e "${BATS_TEST_TMPDIR}/pwned" ]
}

@test "appsets reapply confirmation: does not wait when the first check passes" {
  _argocd_deploy_applicationsets() { return 0; }
  argocd_check_values_branch() {
    printf x >> "${CALLS}"
    return 0
  }
  sleep() { printf 'SLEEP-SHOULD-NOT-RUN\n'; }

  run deploy_argocd_applicationsets
  [ "${status}" -eq 0 ]
  [ "$(wc -c < "${CALLS}")" -eq 1 ]
  [[ "${output}" != *"waiting for ApplicationSet controller"* ]]
  [[ "${output}" != *"SLEEP-SHOULD-NOT-RUN"* ]]
}

@test "appsets reapply confirmation: --no-verify skips the check" {
  _argocd_deploy_applicationsets() { return 0; }
  argocd_check_values_branch() { printf 'VERIFY-SHOULD-NOT-RUN\n'; return 1; }

  run deploy_argocd_applicationsets --no-verify
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"VERIFY-SHOULD-NOT-RUN"* ]]
}

@test "appsets reapply confirmation: dry-run skips the check" {
  _argocd_deploy_applicationsets() { return 0; }
  argocd_check_values_branch() { printf 'VERIFY-SHOULD-NOT-RUN\n'; return 1; }

  DRY_RUN=1 run deploy_argocd_applicationsets
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"DRY_RUN: skipping the values-branch confirmation"* ]]
  [[ "${output}" != *"VERIFY-SHOULD-NOT-RUN"* ]]
}
