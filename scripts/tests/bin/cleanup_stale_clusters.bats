#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${FAKE_BIN}"
  cat > "${FAKE_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -e
case "$*" in
  *'get secrets '*'-o json') cat "${FIXTURE_JSON}" ;;
  *'get applications '*'-o json') printf '%s\n' '{"items":[{"metadata":{"name":"shopping-cart-app","labels":{"k3d-manager/managed":"true","k3d-manager/cluster":"ubuntu-k3s"}},"spec":{"destination":{"name":"ubuntu-k3s"}}}]}' ;;
  *' delete '*|*' patch '*) printf '%s\n' "$*" >> "${KUBECTL_LOG}" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "${FAKE_BIN}/kubectl"
  FIXTURE_JSON="${BATS_TEST_TMPDIR}/secrets.json"
  KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  cat > "${FIXTURE_JSON}" <<'EOF'
{"items":[
 {"metadata":{"name":"cluster-expired","labels":{"argocd.argoproj.io/cluster-name":"ubuntu-k3s","k3d-manager/managed":"true","k3d-manager/provider":"k3s-aws"},"annotations":{"k3d-manager/expires-at":"2020-01-01T00:00:00Z","k3d-manager/sandbox-id":"sandbox-old"}}},
 {"metadata":{"name":"cluster-hostinger","labels":{"argocd.argoproj.io/cluster-name":"ubuntu-hostinger","k3d-manager/managed":"true","k3d-manager/provider":"k3s-hostinger"},"annotations":{"k3d-manager/expires-at":"2020-01-01T00:00:00Z"}}}
]}
EOF
  export PATH="${FAKE_BIN}:${PATH}" FIXTURE_JSON KUBECTL_LOG
}

@test "cleanup-stale-clusters dry-run only reports expired k3s-aws registrations" {
  run env K3DM_CLEANUP_NOW=2000000000 K3DM_CLEANUP_GRACE_SECONDS=0 \
    K3DM_CLEANUP_STATE_DIR="${BATS_TEST_TMPDIR}/state" \
    K3DM_CLEANUP_AUDIT_FILE="${BATS_TEST_TMPDIR}/audit.jsonl" \
    "${REPO_ROOT}/bin/cleanup-stale-clusters"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"cluster-expired"* ]]
  [[ "${output}" == *"DRY_RUN: would delete"* ]]
  [[ "${output}" == *"skip cluster-hostinger: provider=k3s-hostinger"* ]]
  [ ! -s "${KUBECTL_LOG}" ]
}

@test "cleanup-stale-clusters confirm deletes managed apps and secret" {
  run env K3DM_CLEANUP_NOW=2000000000 K3DM_CLEANUP_GRACE_SECONDS=0 \
    K3DM_CLEANUP_STATE_DIR="${BATS_TEST_TMPDIR}/state-confirm" \
    K3DM_CLEANUP_AUDIT_FILE="${BATS_TEST_TMPDIR}/audit-confirm.jsonl" \
    "${REPO_ROOT}/bin/cleanup-stale-clusters" --confirm
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"removed cluster-expired"* ]]
  [[ "$(cat "${KUBECTL_LOG}")" == *"delete application/shopping-cart-app"* ]]
  [[ "$(cat "${KUBECTL_LOG}")" == *"delete secret cluster-expired"* ]]
}
