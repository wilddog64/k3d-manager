#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/observability.sh"
  _err() { printf 'ERROR: %s\n' "$*" >&2; }
  _info() { printf 'INFO: %s\n' "$*"; }
}

configure_guard_stub() {
  TEST_CR="${1:-}"
  TEST_SECRET_STATE="${2:-absent}"
  _kubectl() {
    [[ "${1:-}" == "--no-exit" ]] && shift
    if [[ "${1:-}" == "get" && "${2:-}" == "alertmanager" && "${3:-}" == "-n" ]]; then
      [[ -n "${TEST_CR}" ]] && printf '%s\n' "${TEST_CR}"
      return 0
    fi
    if [[ "${1:-}" == "get" && "${2:-}" == "alertmanager" ]]; then
      [[ "${3:-}" == "${TEST_CR}" ]] && printf '%s\n' "${secret_name:-}"
      return 0
    fi
    if [[ "${1:-}" == "get" && "${2:-}" == "secret" ]]; then
      [[ "${TEST_SECRET_STATE}" == "present" ]]
      return
    fi
    return 1
  }
  export -f _kubectl
}

@test "no Alertmanager CR returns zero" {
  configure_guard_stub ""
  _observability_assert_alertmanager_delivery k3d-k3d-cluster >"${BATS_TEST_TMPDIR}/guard.out" 2>&1; status=$?
  output="$(<"${BATS_TEST_TMPDIR}/guard.out")"
  [ "${status}" -eq 0 ]
}

@test "empty configSecret returns zero" {
  secret_name=""
  configure_guard_stub acme absent
  run _observability_assert_alertmanager_delivery k3d-k3d-cluster
  [ "${status}" -eq 0 ]
}

@test "present config secret returns zero and logs info" {
  secret_name=alertmanager-smtp-secret
  configure_guard_stub acme present
  _observability_assert_alertmanager_delivery k3d-k3d-cluster >"${BATS_TEST_TMPDIR}/guard.out" 2>&1; status=$?
  output="$(<"${BATS_TEST_TMPDIR}/guard.out")"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"config secret alertmanager-smtp-secret present"* ]]
}

@test "absent config secret returns one and warns every alert is discarded" {
  secret_name=alertmanager-smtp-secret
  configure_guard_stub acme absent
  run _observability_assert_alertmanager_delivery k3d-k3d-cluster
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"DISCARDS EVERY ALERT"* ]]
}

@test "failure names the Alertmanager and secret" {
  secret_name=alertmanager-smtp-secret
  configure_guard_stub acme absent
  run _observability_assert_alertmanager_delivery k3d-k3d-cluster
  [[ "${output}" == *"Alertmanager acme"* ]]
  [[ "${output}" == *"alertmanager-smtp-secret"* ]]
}
