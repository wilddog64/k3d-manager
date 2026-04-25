#!/usr/bin/env bats

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  export PATH="${BATS_TEST_TMPDIR}/bin:$PATH"
  export SYNC_APPS_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  export SYNC_APPS_LOG_DIR="${BATS_TEST_TMPDIR}/logs"
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${SYNC_APPS_STATE_DIR}" "${SYNC_APPS_LOG_DIR}"
  : > "${BATS_TEST_TMPDIR}/kubectl.log"
  : > "${BATS_TEST_TMPDIR}/argocd.log"
  rm -f "${BATS_TEST_TMPDIR}/pf_ready"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/lsof"
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"-t"* ]]; then
  if [[ -n "${LSOF_PIDS:-}" ]]; then
    printf '%s\n' "${LSOF_PIDS}"
  fi
  exit "${LSOF_EXIT_CODE:-0}"
fi
exit "${LSOF_EXIT_CODE:-0}"
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/lsof"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/kubectl"
#!/usr/bin/env bash
set -euo pipefail
echo "kubectl $*" >> "${BATS_TEST_TMPDIR}/kubectl.log"
if [[ "${1:-}" == "port-forward" ]]; then
  if [[ "${PF_SHOULD_FAIL:-0}" == "1" ]]; then
    echo "boom from port-forward" >&2
    exit 1
  fi
  : > "${BATS_TEST_TMPDIR}/pf_ready"
  exit 0
fi
if [[ "$*" == *"get secret argocd-initial-admin-secret"* ]]; then
  printf '%s\n' "ZmFrZS1wYXNz"
  exit 0
fi
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/kubectl"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/curl"
#!/usr/bin/env bash
if [[ -f "${BATS_TEST_TMPDIR}/pf_ready" ]]; then
  exit 0
fi
exit 1
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/nc"
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/nc"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/argocd"
#!/usr/bin/env bash
set -euo pipefail
echo "argocd $*" >> "${BATS_TEST_TMPDIR}/argocd.log"
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/argocd"
}

@test "acg-sync-apps reuses a managed port-forward" {
  export LSOF_EXIT_CODE=0
  export LSOF_PIDS="$$"
  cat > "${SYNC_APPS_STATE_DIR}/acg-sync-apps-argocd-pf.env" <<EOF
SYNC_APPS_PF_PID=$$
SYNC_APPS_PF_CONTEXT=k3d-k3d-cluster
SYNC_APPS_PF_NS=cicd
SYNC_APPS_PF_PORT=8080
SYNC_APPS_PF_SERVICE=svc/argocd-server
SYNC_APPS_PF_LOG=${BATS_TEST_TMPDIR}/logs/managed.log
EOF
  : > "${BATS_TEST_TMPDIR}/pf_ready"

  run "${BATS_TEST_DIRNAME}/../../../bin/acg-sync-apps"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Reusing existing argocd-server port-forward on 8080"* ]]
  ! grep -q "port-forward svc/argocd-server" "${BATS_TEST_TMPDIR}/kubectl.log"
}

@test "acg-sync-apps replaces an unmanaged listener on 8080" {
  export LSOF_EXIT_CODE=0
  sleep 60 &
  local old_listener_pid=$!
  export LSOF_PIDS="${old_listener_pid}"

  run "${BATS_TEST_DIRNAME}/../../../bin/acg-sync-apps"
  local rc=$?
  kill "${old_listener_pid}" 2>/dev/null || true
  wait "${old_listener_pid}" 2>/dev/null || true

  [ "$rc" -eq 0 ]
  [[ "$output" == *"already in use by an unmanaged listener"* ]]
  [[ "$output" == *"Starting argocd-server port-forward"* ]]
  grep -q "port-forward svc/argocd-server -n cicd 8080:443 --context k3d-k3d-cluster" "${BATS_TEST_TMPDIR}/kubectl.log"
}

@test "acg-sync-apps preserves the port-forward log on failure" {
  export LSOF_EXIT_CODE=1
  export PF_SHOULD_FAIL=1

  run "${BATS_TEST_DIRNAME}/../../../bin/acg-sync-apps"
  [ "$status" -eq 1 ]
  [[ "$output" == *"port-forward exited early"* ]]
  [[ "$output" == *"boom from port-forward"* ]]
  [ ! -e "${SYNC_APPS_STATE_DIR}/acg-sync-apps-argocd-pf.env" ]

  local log_file
  log_file="$(find "${SYNC_APPS_LOG_DIR}" -maxdepth 1 -name 'acg-sync-apps-argocd-pf.*.log' | head -1)"
  [ -n "$log_file" ]
  grep -q "boom from port-forward" "$log_file"
}

@test "acg-sync-apps uses non-interactive ArgoCD login flags" {
  export LSOF_EXIT_CODE=0
  sleep 60 &
  local managed_listener_pid=$!
  export LSOF_PIDS="${managed_listener_pid}"
  cat > "${SYNC_APPS_STATE_DIR}/acg-sync-apps-argocd-pf.env" <<EOF
SYNC_APPS_PF_PID=${managed_listener_pid}
SYNC_APPS_PF_CONTEXT=k3d-k3d-cluster
SYNC_APPS_PF_NS=cicd
SYNC_APPS_PF_PORT=8080
SYNC_APPS_PF_SERVICE=svc/argocd-server
SYNC_APPS_PF_LOG=${SYNC_APPS_LOG_DIR}/managed.log
EOF
  : > "${BATS_TEST_TMPDIR}/pf_ready"

  run "${BATS_TEST_DIRNAME}/../../../bin/acg-sync-apps"
  local rc=$?
  kill "${managed_listener_pid}" 2>/dev/null || true
  wait "${managed_listener_pid}" 2>/dev/null || true

  [ "$rc" -eq 0 ]
  [ "$status" -eq 0 ]

  grep -q "argocd login localhost:8080 --username admin --password fake-pass --plaintext --skip-test-tls --insecure --grpc-web" "${BATS_TEST_TMPDIR}/argocd.log"
}
