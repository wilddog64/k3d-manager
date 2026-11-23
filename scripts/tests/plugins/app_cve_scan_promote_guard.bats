#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  export TEST_LOG="$BATS_TEST_TMPDIR/events" TEST_SCAN_SCRIPT="$BATS_TEST_TMPDIR/promote"
  : >"$TEST_LOG"
  sed '/^# === MAIN ===/,$d' "$BATS_TEST_DIRNAME/../../etc/argocd/platform-ops/app-cve-scan.sh" >"$TEST_SCAN_SCRIPT"
  cat >>"$TEST_SCAN_SCRIPT" <<'SH'
_rc=0
_hub_kubectl() { echo "$*" >>"$TEST_LOG"; }
_git_persist_promotion() { echo persist >>"$TEST_LOG"; [ "$RESULT" = 0 ] && echo abc; }
_emit_remediation_event() { echo event >>"$TEST_LOG"; }
_notify() { echo "$*" >>"$TEST_LOG"; }
_promote_image shopping-cart-frontend ghcr.io/wilddog64/shopping-cart-frontend sha-new sha256:d old CVE-1
exit "$_rc"
SH
  [[ "$TEST_LOG" == "$BATS_TEST_TMPDIR/events" ]]
}

@test "no token reports NOT APPLIED" {
  run env GIT_WRITE_TOKEN='' RESULT=0 sh "$TEST_SCAN_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT APPLIED — no GIT_WRITE_TOKEN"* ]]
  grep -F 'App CVE Promotion NOT applied: shopping-cart-frontend' "$TEST_LOG"
  run ! grep -E '^(event|persist)$|application ' "$TEST_LOG"
}

@test "persist failure emits no event and no application patch" {
  run env GIT_WRITE_TOKEN=fixture RESULT=1 sh "$TEST_SCAN_SCRIPT"
  [ "$status" -eq 1 ]
  grep -qx persist "$TEST_LOG"
  run ! grep -E '^event$|application ' "$TEST_LOG"
}

@test "success orders persistence refresh and one event" {
  run env GIT_WRITE_TOKEN=fixture RESULT=0 sh "$TEST_SCAN_SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$TEST_LOG")" = persist ]
  [[ "$(sed -n '2p' "$TEST_LOG")" == *"annotate application ubuntu-hostinger-shopping-cart-frontend argocd.argoproj.io/refresh=hard"* ]]
  [ "$(sed -n '3p' "$TEST_LOG")" = event ]
  [ "$(grep -cx event "$TEST_LOG")" = 1 ]
}

@test "successful pin never patches or clears application images" {
  run env GIT_WRITE_TOKEN=fixture RESULT=0 sh "$TEST_SCAN_SCRIPT"
  [ "$status" -eq 0 ]
  grep -F 'annotate application' "$TEST_LOG"
  run ! grep -F 'patch application' "$TEST_LOG"
}

@test "success reports pin branch and sha" {
  run env GIT_WRITE_TOKEN=fixture RESULT=0 sh "$TEST_SCAN_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pinned ghcr.io/wilddog64/shopping-cart-frontend@sha256:d on cve-pins/hub@abc"* ]]
  grep -F 'git=cve-pins/hub@abc' "$TEST_LOG"
}
