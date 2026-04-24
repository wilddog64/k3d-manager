#!/usr/bin/env bats

setup() {
  export PATH="${BATS_TEST_TMPDIR}/bin:$PATH"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/kubectl"
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "port-forward" ]]; then
  echo "boom from port-forward" >&2
  exit 1
fi
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/kubectl"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/curl"
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/argocd"
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/argocd"
}

@test "acg-sync-apps reports early port-forward failure details" {
  run "${BATS_TEST_DIRNAME}/../../../bin/acg-sync-apps"
  [ "$status" -eq 1 ]
  [[ "$output" == *"port-forward exited early"* ]]
  [[ "$output" == *"boom from port-forward"* ]]
}
