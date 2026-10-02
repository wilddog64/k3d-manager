#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${FAKE_BIN}"
  KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  export KUBECTL_LOG
  cat > "${FAKE_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -e
case "$*" in
  *'get secrets '*'-o json')
    printf '%s\n' '{"items":[{"metadata":{"name":"cluster-ubuntu-k3s"},"data":{"server":"aHR0cHM6Ly9ob3N0LmszZC5pbnRlcm5hbDo2NDQz"}}]}'
    ;;
  *'get applications '*'-o json')
    printf '%s\n' '{"items":[
      {"metadata":{"name":"ubuntu-k3s-data-layer"},"spec":{"destination":{"name":"ubuntu-k3s"}}},
      {"metadata":{"name":"ubuntu-k3s-eso"},"spec":{"destination":{"server":"https://host.k3d.internal:6443"}}},
      {"metadata":{"name":"ubuntu-hostinger-eso"},"spec":{"destination":{"name":"ubuntu-hostinger"}}}
    ]}'
    ;;
  *' delete '*|*' patch '*) printf '%s\n' "$*" >> "${KUBECTL_LOG}" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "${FAKE_BIN}/kubectl"
  export PATH="${FAKE_BIN}:${PATH}"
}

@test "cleanup-stale-registration dry-run reports only the named registration and matches" {
  run "${REPO_ROOT}/bin/cleanup-stale-registration" --cluster=ubuntu-k3s
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"cluster-ubuntu-k3s"* ]]
  [[ "${output}" == *"ubuntu-k3s-data-layer"* ]]
  [[ "${output}" == *"ubuntu-k3s-eso"* ]]
  [[ "${output}" != *"ubuntu-hostinger-eso"* ]]
  [[ "${output}" == *"DRY_RUN: no changes made"* ]]
  [ ! -s "${KUBECTL_LOG}" ]
}

@test "cleanup-stale-registration confirm deletes the Secret before matching Applications" {
  run "${REPO_ROOT}/bin/cleanup-stale-registration" --cluster=ubuntu-k3s --confirm
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Removed registration cluster-ubuntu-k3s and 2 matching Applications"* ]]
  secret_line="$(grep -n 'delete secret cluster-ubuntu-k3s' "${KUBECTL_LOG}" | cut -d: -f1)"
  app_line="$(grep -n 'delete application/' "${KUBECTL_LOG}" | head -1 | cut -d: -f1)"
  [ "${secret_line}" -lt "${app_line}" ]
  [[ "$(grep 'delete application/' "${KUBECTL_LOG}")" == *"--wait=false"* ]]
}

@test "cleanup-stale-registration requires an explicit cluster name" {
  run "${REPO_ROOT}/bin/cleanup-stale-registration" --confirm
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"--cluster must be a non-empty"* ]]
}
