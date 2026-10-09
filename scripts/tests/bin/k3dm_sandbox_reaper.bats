#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"; STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  STATE_DIR="${BATS_TEST_TMPDIR}/state"; LOG_FILE="${BATS_TEST_TMPDIR}/reaper.log"
  CALL_LOG="${BATS_TEST_TMPDIR}/calls.log"; NOTIFY_LOG="${BATS_TEST_TMPDIR}/notify.log"
  mkdir -p "${STUB_BIN}" "${STATE_DIR}"; : > "${CALL_LOG}"; : > "${NOTIFY_LOG}"
  printf '%s\n' '#!/usr/bin/env bash' '[[ "${PGREP_RUNNING:-0}" == 1 ]] && exit 0; exit 1' > "${STUB_BIN}/pgrep"
  cat > "${STUB_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
printf 'kubectl %s\n' "$*" >> "${CALL_LOG}"
if [[ "$*" == *"get secrets"* ]]; then
  printf '%s\n' '{"items":[{"metadata":{"uid":"u1","labels":{"argocd.argoproj.io/cluster-name":"ubuntu-k3s"}},"data":{"server":"aHR0cHM6Ly9ob3N0LmszZC5pbnRlcm5hbDo2NDQz"}}]}'
elif [[ "$*" == *"get applications"* ]]; then
  if [[ -n "${APPS_JSON:-}" ]]; then printf '%s\n' "${APPS_JSON}"; else
    printf '%s\n' '{"items":[{"metadata":{"name":"ubuntu-k3s-order"},"spec":{"destination":{"name":"ubuntu-k3s"}},"status":{"sync":{"status":"Unknown"}}},{"metadata":{"name":"ubuntu-k3s-eso"},"spec":{"destination":{"server":"https://host.k3d.internal:6443"}},"status":{"sync":{"status":"Unknown"}}},{"metadata":{"name":"ubuntu-hostinger"},"spec":{"destination":{"name":"ubuntu-hostinger"}},"status":{"sync":{"status":"Unknown"}}}]}'
  fi
fi
EOF
  cat > "${STUB_BIN}/aws" <<'EOF'
#!/usr/bin/env bash
printf 'aws %s\n' "$*" >> "${CALL_LOG}"
case "${AWS_MODE:-gone}" in
  exists) exit 0 ;; gone) echo 'stack does not exist' >&2; exit 255 ;;
  dead) echo 'InvalidClientTokenId' >&2; exit 255 ;; network) echo 'Could not connect to the endpoint URL' >&2; exit 255 ;;
esac
EOF
  printf '%s\n' '#!/usr/bin/env bash' 'printf "cleanup %s\n" "$*" >> "${CALL_LOG}"' 'exit "${CLEANUP_RC:-0}"' > "${STUB_BIN}/cleanup"
  printf '%s\n' '#!/usr/bin/env bash' 'cat >> "${NOTIFY_LOG}"' 'exit "${NOTIFY_RC:-0}"' > "${STUB_BIN}/notify"
  chmod +x "${STUB_BIN}"/*
  export CALL_LOG NOTIFY_LOG
  export K3DM_SANDBOX_REAPER_STATE_DIR="${STATE_DIR}" K3DM_SANDBOX_REAPER_LOG="${LOG_FILE}"
  export K3DM_SANDBOX_REAPER_CLEANUP_BIN="${STUB_BIN}/cleanup" K3DM_SANDBOX_REAPER_NOTIFY_BIN="${STUB_BIN}/notify"
  export K3DM_SANDBOX_REAPER_KUBECTL_BIN="${STUB_BIN}/kubectl" K3DM_SANDBOX_REAPER_PGREP_BIN="${STUB_BIN}/pgrep" K3DM_SANDBOX_REAPER_AWS_BIN="${STUB_BIN}/aws"
  export K3DM_SANDBOX_REAPER_NOW=10000 K3DM_SANDBOX_REAPER_GRACE=1800 K3DM_SANDBOX_REAPER_DRYRUN=0 AWS_MODE=gone PGREP_RUNNING=0 CLEANUP_RC=0 NOTIFY_RC=0
}
run_reaper() { run "${REPO_ROOT}/bin/k3dm-sandbox-reaper"; }
seed_clock() { printf '%s\n' "$1" > "${STATE_DIR}/u1"; }

@test "reaper: Unknown apps create first-seen clock without AWS or cleanup" { run_reaper; [ "$status" -eq 0 ]; [ -f "$STATE_DIR/u1" ]; ! grep -q '^aws ' "$CALL_LOG" || false; ! grep -q '^cleanup ' "$CALL_LOG" || false; }
@test "reaper: clock younger than grace does not act" { seed_clock 8201; run_reaper; [ "$status" -eq 0 ]; ! grep -q '^aws ' "$CALL_LOG" || false; ! grep -q '^cleanup ' "$CALL_LOG" || false; }
@test "reaper: deleted stack cleans up and notifies" { seed_clock 7000; run_reaper; [ "$status" -eq 0 ]; grep -q '^cleanup --cluster=ubuntu-k3s --confirm$' "$CALL_LOG"; grep -q 'removed hub registration ubuntu-k3s' "$NOTIFY_LOG"; grep -q '(stack-deleted)' "$NOTIFY_LOG"; [ ! -e "$STATE_DIR/u1" ]; }
@test "reaper: dead credentials clean up and include reason" { seed_clock 7000; AWS_MODE=dead run_reaper; [ "$status" -eq 0 ]; grep -q '^cleanup --cluster=ubuntu-k3s --confirm$' "$CALL_LOG"; grep -q 'credentials-dead' "$NOTIFY_LOG"; }
@test "reaper: existing stack does not clean up" { seed_clock 7000; AWS_MODE=exists run_reaper; [ "$status" -eq 0 ]; ! grep -q '^cleanup ' "$CALL_LOG" || false; [ ! -s "$NOTIFY_LOG" ]; }
@test "reaper: inconclusive AWS result does not clean up" { seed_clock 7000; AWS_MODE=network run_reaper; [ "$status" -eq 0 ]; ! grep -q '^cleanup ' "$CALL_LOG" || false; [ ! -s "$NOTIFY_LOG" ]; }
@test "reaper: Synced app removes existing clock" { seed_clock 7000; APPS_JSON='{"items":[{"metadata":{"name":"ubuntu-k3s-order"},"spec":{"destination":{"name":"ubuntu-k3s"}},"status":{"sync":{"status":"Synced"}}}]}' run_reaper; [ "$status" -eq 0 ]; [ ! -e "$STATE_DIR/u1" ]; ! grep -q '^cleanup ' "$CALL_LOG" || false; }
@test "reaper: zero matching apps does not act" { APPS_JSON='{"items":[{"metadata":{"name":"ubuntu-hostinger"},"spec":{"destination":{"name":"ubuntu-hostinger"}},"status":{"sync":{"status":"Unknown"}}}]}' run_reaper; [ "$status" -eq 0 ]; [ ! -e "$STATE_DIR/u1" ]; ! grep -q '^aws ' "$CALL_LOG" || false; }
@test "reaper: dry-run logs would-deregister without cleanup or notify" { seed_clock 7000; K3DM_SANDBOX_REAPER_DRYRUN=1 run_reaper; [ "$status" -eq 0 ]; grep -q would-deregister "$LOG_FILE"; ! grep -q '^cleanup ' "$CALL_LOG" || false; [ ! -s "$NOTIFY_LOG" ]; }
@test "reaper: cleanup failure notifies once and keeps state" { seed_clock 7000; CLEANUP_RC=1 run_reaper; CLEANUP_RC=1 run_reaper; [ "$status" -eq 0 ]; [ "$(wc -l < "$NOTIFY_LOG")" -eq 1 ]; [ -e "$STATE_DIR/u1" ]; }
@test "reaper: notify failure does not change successful cleanup" { seed_clock 7000; NOTIFY_RC=1 run_reaper; [ "$status" -eq 0 ]; grep -q 'deregistered ubuntu-k3s' "$LOG_FILE"; grep -q 'notify failed' "$LOG_FILE"; }
@test "reaper: lifecycle process skips kubectl" { PGREP_RUNNING=1 run_reaper; [ "$status" -eq 0 ]; ! grep -q '^kubectl ' "$CALL_LOG" || false; }
@test "reaper: Secret selector includes k3s-aws provider" { run_reaper; [ "$status" -eq 0 ]; grep -q 'k3d-manager/provider=k3s-aws' "$CALL_LOG"; }
@test "reaper: stale unknown UID state is removed" { printf '%s\n' 1 > "$STATE_DIR/stale-uid"; run_reaper; [ "$status" -eq 0 ]; [ ! -e "$STATE_DIR/stale-uid" ]; }
