#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${FAKE_BIN}" "${BATS_TEST_TMPDIR}/home/Library/LaunchAgents"
  cat > "${FAKE_BIN}/launchctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${FAIL_AGENT:-0}" == 1 ]]; then exit 1; fi
exit 0
EOF
  cat > "${FAKE_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
if [[ "${FAIL_KUBECTL:-0}" == 1 ]]; then exit 1; fi
if [[ "$*" == "config get-contexts -o name" ]]; then
  printf '%s\n' "${ACG_KUBE_CONTEXT:-ubuntu-k3s}"
  exit 0
fi
if [[ "$*" == "config delete-context "* ]]; then
  printf 'deleted %s\n' "${ACG_KUBE_CONTEXT:-ubuntu-k3s}"
  exit 0
fi
exit 1
EOF
  chmod +x "${FAKE_BIN}/launchctl" "${FAKE_BIN}/kubectl"
  export HOME="${BATS_TEST_TMPDIR}/home" PATH="${FAKE_BIN}:${PATH}" CLUSTER_PROVIDER=k3s-aws ACG_KUBE_CONTEXT=ubuntu-k3s
}

@test "cleanup-stale-sandbox preview makes no changes" {
  run "${REPO_ROOT}/bin/cleanup-stale-sandbox" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"DRY RUN: no changes made"* ]]
  [ ! -e "${HOME}/Library/LaunchAgents/com.k3d-manager.frontend-port-forward.plist" ]
}

@test "cleanup-stale-sandbox reports successful removals" {
  touch "${HOME}/Library/LaunchAgents/com.k3d-manager.frontend-port-forward.plist"
  run "${REPO_ROOT}/bin/cleanup-stale-sandbox" --apply
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"stopped launchd agent: com.k3d-manager.frontend-port-forward"* ]]
  [[ "${output}" == *"removed kube context: ubuntu-k3s"* ]]
  [[ "${output}" == *"Cleanup complete"* ]]
  [ ! -e "${HOME}/Library/LaunchAgents/com.k3d-manager.frontend-port-forward.plist" ]
}

@test "cleanup-stale-sandbox returns failure for an agent operation" {
  touch "${HOME}/Library/LaunchAgents/com.k3d-manager.frontend-port-forward.plist"
  run env FAIL_AGENT=1 "${REPO_ROOT}/bin/cleanup-stale-sandbox" --confirm
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAILED: could not stop launchd agent"* ]]
  [[ "${output}" == *"Cleanup incomplete"* ]]
}

@test "cleanup-stale-sandbox returns failure when kubeconfig cannot be inspected" {
  run env FAIL_KUBECTL=1 "${REPO_ROOT}/bin/cleanup-stale-sandbox" --confirm
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAILED: could not inspect kube contexts"* ]]
  [[ "${output}" == *"Cleanup incomplete"* ]]
}
