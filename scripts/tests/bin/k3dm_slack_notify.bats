#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  STUB_BIN="${BATS_TEST_TMPDIR}/bin"; mkdir -p "${STUB_BIN}"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "http://127.0.0.1:9/never"' > "${STUB_BIN}/security"
  chmod +x "${STUB_BIN}/security"; export PATH="${STUB_BIN}:${PATH}"
}
@test "slack notify: empty stdin exits 2" {
  run bash -c "printf '' | '${REPO_ROOT}/bin/k3dm-slack-notify'"; [ "${status}" -eq 2 ]
}
@test "slack notify: failed relay exits 1 without exposing URL" {
  run bash -c "printf '%s' 'hello from test' | '${REPO_ROOT}/bin/k3dm-slack-notify'"; [ "${status}" -eq 1 ]
  [[ "${output}" != *'http://127.0.0.1:9/never'* ]]
}
