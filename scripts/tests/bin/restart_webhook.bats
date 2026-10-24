#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

MAKEFILE="${MAKEFILE:-${BATS_TEST_DIRNAME}/../../../Makefile}"

_restart_webhook_stubs() {
  STUB_HOME="${BATS_TEST_TMPDIR}/home"
  STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  STUB_CALLS="${BATS_TEST_TMPDIR}/launchctl.calls"
  mkdir -p "${STUB_HOME}/Library/LaunchAgents" "${STUB_BIN}"
  cat > "${STUB_BIN}/launchctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_CALLS"
if [ "${1:-}" = bootout ] && [ "${BOOTOUT_FAIL:-0}" = 1 ]; then
  exit 5
fi
if [ "${1:-}" = bootstrap ]; then
  count=$(grep -c '^bootstrap ' "$STUB_CALLS")
  if [ "$count" -le "${BOOTSTRAP_FAIL_COUNT:-0}" ]; then
    exit 5
  fi
fi
exit 0
SH
  cat > "${STUB_BIN}/sleep" <<'SH'
#!/bin/sh
exit 0
SH
  chmod +x "${STUB_BIN}/launchctl" "${STUB_BIN}/sleep"
}

_run_restart_webhook() {
  env HOME="${STUB_HOME}" PATH="${STUB_BIN}:${PATH}" STUB_CALLS="${STUB_CALLS}" \
    BOOTOUT_FAIL="${BOOTOUT_FAIL:-0}" BOOTSTRAP_FAIL_COUNT="${BOOTSTRAP_FAIL_COUNT:-0}" \
    make --no-print-directory -f "${MAKEFILE}" restart-webhook
}

@test "restart-webhook reloads the plist with bootout then bootstrap, never kickstarting the webhook" {
  _restart_webhook_stubs
  run _run_restart_webhook
  [ "${status}" -eq 0 ]
  [ "$(sed -n '1p' "${STUB_CALLS}")" = "bootout gui/$(id -u)/com.k3d-manager.webhook" ]
  [ "$(sed -n '2p' "${STUB_CALLS}")" = "bootstrap gui/$(id -u) ${STUB_HOME}/Library/LaunchAgents/com.k3d-manager.webhook.plist" ]
  if grep -q 'kickstart.*com.k3d-manager.webhook' "${STUB_CALLS}"; then
    return 1
  fi
  [[ "${output}" == *'[restart-webhook] reloaded LaunchAgent definition'* ]]
}

@test "restart-webhook continues to bootstrap when bootout reports the job is not loaded" {
  _restart_webhook_stubs
  BOOTOUT_FAIL=1
  run _run_restart_webhook
  [ "${status}" -eq 0 ]
  grep -q '^bootstrap gui/' "${STUB_CALLS}"
}

@test "restart-webhook still restarts the cloud bridge" {
  _restart_webhook_stubs
  touch "${STUB_HOME}/Library/LaunchAgents/com.k3d-manager.cloud-bridge.plist"
  run _run_restart_webhook
  [ "${status}" -eq 0 ]
  grep -q '^kickstart -k gui/.*/com.k3d-manager.cloud-bridge$' "${STUB_CALLS}"
}

@test "restart-webhook retries bootstrap twice then reports success" {
  _restart_webhook_stubs
  BOOTSTRAP_FAIL_COUNT=2
  run _run_restart_webhook
  [ "${status}" -eq 0 ]
  [ "$(grep -c '^bootstrap ' "${STUB_CALLS}")" -eq 3 ]
  [[ "${output}" == *'[restart-webhook] reloaded LaunchAgent definition'* ]]
}

@test "restart-webhook fails after five bootstrap attempts and skips cloud bridge" {
  _restart_webhook_stubs
  BOOTSTRAP_FAIL_COUNT=5
  run --separate-stderr _run_restart_webhook
  [ "${status}" -ne 0 ]
  [ "$(grep -c '^bootstrap ' "${STUB_CALLS}")" -eq 5 ]
  [[ "${stderr}" == *'[restart-webhook] ERROR: bootstrap failed after 5 attempts'* ]]
  if grep -q 'kickstart.*com.k3d-manager.cloud-bridge' "${STUB_CALLS}"; then
    return 1
  fi
}
