#!/usr/bin/env bats

setup() {
  export WORK="$(mktemp -d "${BATS_TEST_TMPDIR}/hub-restore.XXXXXX")"
  export STUB="${WORK}/stub"
  export FAKE_HOME="${WORK}/home"
  export CALL_LOG="${WORK}/calls.log"
  mkdir -p "${STUB}" "${FAKE_HOME}/.cloudflared"
  : > "${CALL_LOG}"
  printf 'placeholder-config\n' > "${FAKE_HOME}/.cloudflared/config.yml"

  cat > "${STUB}/make-stub" <<'EOF'
#!/usr/bin/env bash
printf 'make %s\n' "$*" >> "${CALL_LOG}"
if [[ "${FAIL_STEP:-}" == "${1:-}" ]]; then exit 1; fi
if [[ "${1:-}" == "signing-restore" && "${SIGNING_SKIP:-0}" == "1" ]]; then
  printf 'no Vault key and no Keychain backup\n'
  exit 1
fi
exit 0
EOF
  cat > "${STUB}/dispatcher" <<'EOF'
#!/usr/bin/env bash
printf 'dispatcher %s\n' "$*" >> "${CALL_LOG}"
EOF
  for command_name in security kubectl launchctl cloudflared id curl find; do
    cat > "${STUB}/${command_name}" <<'EOF'
#!/usr/bin/env bash
name="$(basename "$0")"
printf '%s %s\n' "${name}" "$*" >> "${CALL_LOG}"
case "${name}" in
  security) [[ "${KEYCHAIN_FAIL:-0}" != "1" ]] || exit 1 ;;
  kubectl)
    if [[ "${1:-}" == "config" && "${2:-}" == "current-context" ]]; then
      printf '%s\n' "${KUBE_CONTEXT:-k3d-k3d-cluster}"
    fi
    ;;
  launchctl)
    if [[ "${1:-}" == "list" ]]; then
      printf '101 0 com.k3d-manager.grafana-port-forward\n202 0 com.k3d-manager.cloudflare-tunnel\n'
    fi
    ;;
  curl) printf '200\n' ;;
  id) [[ "${1:-}" == "-u" ]] && printf '501\n' || printf 'tester\n' ;;
  find) [[ "${FIND_ROOT:-0}" == "1" ]] && printf '%s\n' "${FAKE_HOME}/.local/share/k3d-manager/root-owned" ;;
esac
exit 0
EOF
    chmod +x "${STUB}/${command_name}"
  done
  chmod +x "${STUB}/make-stub" "${STUB}/dispatcher"
  export PATH="${STUB}:/usr/bin:/bin"
  export HOME="${FAKE_HOME}"
  export K3DM_MAKE="${STUB}/make-stub"
  export K3DM_DISPATCHER="${STUB}/dispatcher"
  export HUB_RESTORE_SKIP_PREFLIGHT=1
}

teardown() { rm -rf "${WORK}"; }

@test "hub-restore rejects a non-TTY before any make step" {
  unset HUB_RESTORE_SKIP_PREFLIGHT
  run bash -c "bin/hub-restore </dev/null"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Terminal.app"* ]]
  [ ! -s "${CALL_LOG}" ]
}

@test "hub-restore rejects an unreadable Keychain before any make step" {
  unset HUB_RESTORE_SKIP_PREFLIGHT
  export KEYCHAIN_FAIL=1
  run script -q /dev/null bin/hub-restore
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"security unlock-keychain"* ]]
  ! grep -q '^make ' "${CALL_LOG}"
}

@test "hub-restore rejects the wrong Kubernetes context before any make step" {
  unset HUB_RESTORE_SKIP_PREFLIGHT
  export KUBE_CONTEXT=ubuntu-hostinger
  run script -q /dev/null bin/hub-restore
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"ubuntu-hostinger"* ]]
  [[ "${output}" == *"k3d-k3d-cluster"* ]]
  ! grep -q '^make ' "${CALL_LOG}"
}

@test "hub-restore happy path runs independent steps and prints eight-row summary" {
  run bin/hub-restore
  [ "${status}" -eq 0 ]
  restore_output="${output}"
  [ "$(grep -c '^\[hub-restore\] [1-8]/8 ' <<< "${restore_output}")" -eq 8 ]
  run cat "${CALL_LOG}"
  [[ "${output}" == *"make restore-google-app-password"* ]]
  [[ "${output}" == *"make observability"* ]]
  [[ "${output}" == *"make signing-restore"* ]]
  [[ "${output}" == *"make platform-ops"* ]]
  [[ "${output}" == *"make install-hub-pushgateway-port-forward"* ]]
  [[ "${output}" == *"dispatcher hub_recovery_reconcile --confirm"* ]]
}

@test "hub-restore keeps going and skips an unbacked signing key" {
  export FAIL_STEP=observability
  export SIGNING_SKIP=1
  run bin/hub-restore
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Step 3/8 FAIL"* ]]
  [[ "${output}" == *"Step 4/8 SKIP"* ]]
  run cat "${CALL_LOG}"
  [[ "${output}" == *"dispatcher hub_recovery_reconcile --confirm"* ]]
  [[ "${output}" != *"signing_init"* ]]
}

@test "hub-restore reports root-owned state folders before any make step" {
  export FIND_ROOT=1
  run bin/hub-restore
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"sudo chown -R"* ]]
  [[ "${output}" == *"root-owned"* ]]
  ! grep -q '^make ' "${CALL_LOG}"
}

@test "Makefile documents and orders hub recovery targets" {
  run make help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make hub-restore   Restore Keychain-backed hub credentials + local agents (run in Terminal.app)"* ]]
  [[ "${output}" == *"make hub-recover   Full hub DR: hub-up + hub-restore (run in Terminal.app)"* ]]
  run grep -A4 '^hub-recover:' Makefile
  [[ "${output}" == *"--preflight-only"* ]]
  [[ "${output}" == *"hub-up"* ]]
  [[ "${output}" == *"bin/hub-restore"* ]]
}
