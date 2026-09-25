#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export TEST_SCAN_SCRIPT="${BATS_TEST_TMPDIR}/app-cve-scan-functions.sh"
  sed '/^# === MAIN ===/,$d' "${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan.sh" >"${TEST_SCAN_SCRIPT}"
  cat >>"${TEST_SCAN_SCRIPT}" <<'EOF'
_rc=0
_event_count=0
_hub_kubectl() {
  case "$*" in
    *" patch application "*)
      printf 'patch application\n' >>"${TEST_LOG}"
      [ "${TEST_PATCH_RESULT}" -eq 0 ]
      ;;
    *" annotate application "*)
      return 0
      ;;
  esac
}
_emit_remediation_event() {
  _event_count=$((_event_count + 1))
}
_app_target_branch() { printf '%s\n' main; }
_git_persist_promotion() { :; }
_notify() { :; }
_promote_image shopping-cart-frontend ghcr.io/wilddog64/shopping-cart-frontend sha-new sha256:testdigest old-image CVE-1
printf 'rc=%s events=%s\n' "${_rc}" "${_event_count}"
EOF
  chmod +x "${TEST_SCAN_SCRIPT}"
  export TEST_LOG="${BATS_TEST_TMPDIR}/promote.log"
  : >"${TEST_LOG}"
}

@test "missing Application logs a failed promotion and returns zero" {
  run env TEST_PATCH_RESULT=1 TEST_LOG="${TEST_LOG}" sh "${TEST_SCAN_SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROMOTION shopping-cart-frontend: FAILED"* ]]
  [[ "$output" == *"rc=1 events=0"* ]]
}

@test "missing Application emits no remediation event" {
  run env TEST_PATCH_RESULT=1 TEST_LOG="${TEST_LOG}" sh "${TEST_SCAN_SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"events=0"* ]]
}

@test "successful Application patch emits one remediation event" {
  run env TEST_PATCH_RESULT=0 TEST_LOG="${TEST_LOG}" sh "${TEST_SCAN_SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=0 events=1"* ]]
}
