#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="${INSTALL_SUDOERS_FILE:-${REPO_ROOT}/bin/install-sudoers.sh}"
}

@test "install-sudoers.sh is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "install-sudoers.sh --help exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "install-sudoers.sh --dry-run validates sudoers syntax" {
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Syntax OK"* ]]
}

@test "sudoers content includes launchctl NOPASSWD rule" {
  run grep -F 'NOPASSWD: /bin/launchctl bootstrap system /Library/LaunchDaemons/com.k3d-manager.*.plist' bin/install-sudoers.sh
  [ "$status" -eq 0 ]
}

@test "sudoers grants the noninteractive true readiness probe" {
  run grep -F '%admin  ALL=(root) NOPASSWD: /usr/bin/true' bin/install-sudoers.sh
  [ "$status" -eq 0 ]
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Syntax OK"* ]]
  [[ "$output" == *"%admin  ALL=(root) NOPASSWD: /usr/bin/true"* ]]
}

@test "sudoers content includes k3d-manager-update-hosts NOPASSWD rule" {
  run grep -F 'NOPASSWD: /usr/local/bin/k3d-manager-update-hosts' bin/install-sudoers.sh
  [ "$status" -eq 0 ]
}

@test "install-sudoers N2 never grants passwordless System Keychain trust" {
  local stub_log="${BATS_TEST_TMPDIR}/sudoers-check.log"
  : > "${stub_log}"
  [[ "${stub_log}" == "${BATS_TEST_TMPDIR}"/* ]]
  run grep -E 'NOPASSWD:.*(/usr/bin/security|security add-trusted-cert)' "${SCRIPT}"
  [ "${status}" -ne 0 ]
  run "${SCRIPT}" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Syntax OK"* ]]
  [[ "${output}" != *"/usr/bin/security"* ]]
  [[ "${output}" != *"security add-trusted-cert"* ]]
}

@test "install-sudoers.sh rejects unknown arguments" {
  run "$SCRIPT" --bogus-flag
  [ "$status" -ne 0 ]
}
