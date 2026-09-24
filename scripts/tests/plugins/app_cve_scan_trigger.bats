#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/observability.sh"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  : >"${CALLS}"
  export CALLS
  _kubectl() {
    printf 'kubectl %s\n' "$*" >>"${CALLS}"
    if [[ "${1:-}" == "-n" && "${3:-}" == get && "${4:-}" == cronjob/* && "${CRONJOB_ABSENT:-0}" -eq 1 ]]; then
      return 1
    fi
    if [[ "${1:-}" == "-n" && "${3:-}" == wait && "${WAIT_FAIL:-0}" -eq 1 ]]; then
      return 1
    fi
    return 0
  }
  _info() { printf 'info %s\n' "$*" >>"${CALLS}"; }
  _err() { printf 'err %s\n' "$*" >>"${CALLS}"; }
}

@test "app_cve_scan_trigger rejects an unsupported cronjob name" {
  run app_cve_scan_trigger evil-job
  [ "${status}" -ne 0 ]
  [ "$(grep -cE '(^| )create( |$)' "${CALLS}" || true)" -eq 0 ]
}

@test "app_cve_scan_trigger fails when the cronjob is absent" {
  CRONJOB_ABSENT=1 run app_cve_scan_trigger app-cve-scan
  [ "${status}" -ne 0 ]
  [ "$(grep -cE '(^| )create( |$)' "${CALLS}" || true)" -eq 0 ]
}

@test "app_cve_scan_trigger creates a job from the cronjob" {
  run app_cve_scan_trigger app-cve-scan
  [ "${status}" -eq 0 ]
  grep -Eq '(^| )--from=cronjob/app-cve-scan( |$)' "${CALLS}"
  grep -Eq '(^| )app-cve-scan-manual-[0-9]{10,}( |$)' "${CALLS}"
}

@test "app_cve_scan_trigger defaults to app-cve-scan with no argument" {
  run app_cve_scan_trigger
  [ "${status}" -eq 0 ]
  grep -Eq '(^| )--from=cronjob/app-cve-scan( |$)' "${CALLS}"
}

@test "app_cve_scan_trigger returns non-zero when the wait times out" {
  WAIT_FAIL=1 run app_cve_scan_trigger app-cve-scan
  [ "${status}" -ne 0 ]
  grep -Eq '(^| )get job/app-cve-scan-manual-[0-9]{10,}( |$)' "${CALLS}"
}

@test "app_cve_scan_trigger honours K3DM_CVE_SCAN_WAIT" {
  K3DM_CVE_SCAN_WAIT=42 run app_cve_scan_trigger app-cve-scan
  [ "${status}" -eq 0 ]
  grep -Eq '(^| )--timeout=42s( |$)' "${CALLS}"
}
