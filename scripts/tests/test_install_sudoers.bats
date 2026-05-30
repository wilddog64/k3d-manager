#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/bin/install-sudoers.sh"
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

@test "install-sudoers.sh rejects unknown arguments" {
  run "$SCRIPT" --bogus-flag
  [ "$status" -ne 0 ]
}
