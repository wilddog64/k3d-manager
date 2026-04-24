#!/usr/bin/env bats

setup() {
  export PATH="${BATS_TEST_TMPDIR}/bin:$PATH"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/lsof"
#!/usr/bin/env bash
set -euo pipefail
exit "${LSOF_EXIT_CODE:-1}"
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/lsof"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/kubectl"
#!/usr/bin/env bash
set -euo pipefail
echo "kubectl $*" >> "${BATS_TEST_TMPDIR}/kubectl.log"
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

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/nc"
#!/usr/bin/env bash
set -euo pipefail
exit 1
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/nc"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/argocd"
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/argocd"
}

@test "acg-sync-apps rejects occupied local port 8080" {
  export LSOF_EXIT_CODE=0
  run "${BATS_TEST_DIRNAME}/../../../bin/acg-sync-apps"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Local port 8080 is already in use"* ]]
  [ ! -s "${BATS_TEST_TMPDIR}/kubectl.log" ]
}

@test "acg-sync-apps reports early port-forward failure details" {
  export LSOF_EXIT_CODE=1
  run "${BATS_TEST_DIRNAME}/../../../bin/acg-sync-apps"
  [ "$status" -eq 1 ]
  [[ "$output" == *"port-forward exited early"* ]]
  [[ "$output" == *"boom from port-forward"* ]]
}
