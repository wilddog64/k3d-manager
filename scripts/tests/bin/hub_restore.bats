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
  for command_name in security kubectl launchctl cloudflared id curl find sleep; do
    cat > "${STUB}/${command_name}" <<'EOF'
#!/usr/bin/env bash
name="$(basename "$0")"
printf '%s %s\n' "${name}" "$*" >> "${CALL_LOG}"
case "${name}" in
  security) [[ "${KEYCHAIN_FAIL:-0}" != "1" ]] || exit 1 ;;
  kubectl)
    if [[ "${1:-}" == "config" && "${2:-}" == "current-context" ]]; then
      printf '%s\n' "${KUBE_CONTEXT:-k3d-k3d-cluster}"
    elif [[ "${*}" == *"exec -i -n secrets --context k3d-k3d-cluster vault-0"* ]]; then
      if [[ "${*}" == *"kv put"* ]]; then
        cat > "${EMBEDDINGS_STDIN}"
      else
        cat >/dev/null
        if [[ -e "${EMBEDDINGS_STDIN}" ]]; then
          printf '40\n'
        else
          printf '%s\n' "${EMBEDDINGS_LENGTH:-0}"
        fi
      fi
    fi
    ;;
  launchctl)
    if [[ "${1:-}" == "list" ]]; then
      printf '101 0 com.k3d-manager.grafana-port-forward\n202 0 com.k3d-manager.cloudflare-tunnel\n'
    fi
    ;;
  curl)
    if [[ "${*}" == *"127.0.0.1:3001/api/health"* ]]; then
      printf 'grafana\n' >> "${GRAFANA_CALL_LOG}"
      grafana_calls="$(wc -l < "${GRAFANA_CALL_LOG}")"
      if [[ "${GRAFANA_MODE:-}" == "always-fail" || ( "${GRAFANA_MODE:-}" == "flaky" && "${grafana_calls}" -le 2 ) ]]; then
        printf '000\n'
      else
        printf '200\n'
      fi
    else
      printf '200\n'
    fi
    ;;
  sleep) : ;;
  id) [[ "${1:-}" == "-u" ]] && printf '501\n' || printf 'tester\n' ;;
  find)
    if [[ "${FIND_LOCK:-0}" == "1" && "${*}" != *"! -name *.lock"* ]]; then
      printf '%s\n' "${FAKE_HOME}/.local/share/k3d-manager/logs/keycloak-browser-http.log.lock"
    elif [[ "${FIND_ROOT:-0}" == "1" ]]; then
      printf '%s\n' "${FAKE_HOME}/.local/share/k3d-manager/root-owned"
    fi
    ;;
esac
exit 0
EOF
    chmod +x "${STUB}/${command_name}"
  done
  chmod +x "${STUB}/make-stub" "${STUB}/dispatcher"
  export EMBEDDINGS_STDIN="${WORK}/embeddings.stdin"
  export GRAFANA_CALL_LOG="${WORK}/grafana-calls.log"
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

@test "hub-restore happy path runs independent steps and prints nine-row summary" {
  export EMBEDDINGS_LENGTH=40
  run bin/hub-restore
  [ "${status}" -eq 0 ]
  restore_output="${output}"
  [ "$(grep -c '^\[hub-restore\] [1-9]/9 ' <<< "${restore_output}")" -eq 9 ]
  run cat "${CALL_LOG}"
  [[ "${output}" == *"make restore-google-app-password"* ]]
  [[ "${output}" == *"make observability"* ]]
  [[ "${output}" == *"make signing-restore"* ]]
  [[ "${output}" == *"make platform-ops"* ]]
  [[ "${output}" == *"make install-hub-pushgateway-port-forward"* ]]
  [[ "${output}" == *"dispatcher hub_recovery_reconcile --confirm"* ]]
}

@test "hub-restore retries Grafana health until the port-forward is ready" {
  export GRAFANA_MODE=flaky
  run bin/hub-restore
  [ "${status}" -eq 0 ]
  [ "$(wc -l < "${GRAFANA_CALL_LOG}")" -eq 3 ]
  [[ "${output}" == *"Grafana health: PASS"* ]]
}

@test "hub-restore fails Grafana health after fifteen retries" {
  export GRAFANA_MODE=always-fail
  run bin/hub-restore
  [ "${status}" -eq 1 ]
  [ "$(wc -l < "${GRAFANA_CALL_LOG}")" -eq 15 ]
  [[ "${output}" == *"Grafana health: FAIL"* ]]
}

@test "hub-restore keeps going and skips an unbacked signing key" {
  export FAIL_STEP=observability
  export SIGNING_SKIP=1
  run bin/hub-restore
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Step 3/9 FAIL"* ]]
  [[ "${output}" == *"Step 4/9 SKIP"* ]]
  run cat "${CALL_LOG}"
  [[ "${output}" == *"dispatcher hub_recovery_reconcile --confirm"* ]]
  [[ "${output}" != *"signing_init"* ]]
}

@test "hub-restore accepts an existing embeddings key without prompting or writing" {
  export EMBEDDINGS_LENGTH=40
  run bin/hub-restore
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"embeddings key present in Vault"* ]]
  [ ! -e "${EMBEDDINGS_STDIN}" ]
  [[ "${output}" != *"Gemini embeddings API key"* ]]
}

@test "hub-restore skips an empty embeddings-key prompt" {
  cat > "${WORK}/bash_env" <<'EOF'
_hub_restore_stdin_is_tty() { return 0; }
EOF
  export BASH_ENV="${WORK}/bash_env"
  run bash -c "printf '\\n' | bin/hub-restore"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"embeddings key missing from Vault"* ]]
  [ ! -e "${EMBEDDINGS_STDIN}" ]
}

@test "hub-restore writes a non-empty embeddings key only through stdin" {
  cat > "${WORK}/bash_env" <<'EOF'
_hub_restore_stdin_is_tty() { return 0; }
EOF
  export BASH_ENV="${WORK}/bash_env"
  export EMBEDDINGS_LENGTH=0
  run bash -c "printf 'test-key-123\\n' | bin/hub-restore"
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'kv put' "${CALL_LOG}")" -eq 1 ]
  grep -q 'test-key-123' "${EMBEDDINGS_STDIN}"
  ! grep -q 'test-key-123' "${CALL_LOG}"
  [[ "${output}" != *"test-key-123"* ]]
}

@test "hub-restore skips an absent embeddings key without a TTY" {
  run bin/hub-restore
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"embeddings key missing from Vault — run make hub-restore in a terminal"* ]]
  [ ! -e "${EMBEDDINGS_STDIN}" ]
}

@test "hub-restore reports root-owned state folders before any make step" {
  export FIND_ROOT=1
  run bin/hub-restore
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"sudo chown -R"* ]]
  [[ "${output}" == *"root-owned"* ]]
  ! grep -q '^make ' "${CALL_LOG}"
}

@test "hub-restore ignores root-owned LaunchDaemon lock folders" {
  export FIND_LOCK=1
  run bin/hub-restore
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"root-owned state folders found"* ]]
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
