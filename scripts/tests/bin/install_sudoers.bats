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

@test "install mode installs both files through interactive sudo" {
  [ "$(grep -Fc '_run_command --interactive-sudo -- /usr/bin/install' "$SCRIPT")" -eq 2 ]
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

@test "dry-run has no passwordless sudoers rewrite rule" {
  local dry_output
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  dry_output="$output"
  if grep -E '^%admin.*NOPASSWD:.* /etc/sudoers\.d/' <<< "$dry_output"; then
    return 1
  fi
}

@test "dry-run removes passwordless self-update and usr-local-bin write rules" {
  local dry_output
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  dry_output="$output"
  [[ "$dry_output" != *"NOPASSWD: /usr/bin/install -m 0755"* ]]
  [[ "$dry_output" != *"NOPASSWD: /usr/bin/install -m 0440"* ]]
  [[ "$dry_output" != *"NOPASSWD: /bin/rm -f /usr/local/bin/k3d-manager-update-hosts"* ]]
  [[ "$dry_output" != *"NOPASSWD: /usr/bin/install -m [0-9][0-9][0-9]"* ]]
  [[ "$dry_output" != *"NOPASSWD: /bin/cp * /usr/local/bin/"* ]]
  [[ "$dry_output" != *"NOPASSWD: /bin/chmod [0-9][0-9][0-9] /usr/local/bin/"* ]]
  [[ "$dry_output" == *"NOPASSWD: /usr/local/bin/k3d-manager-update-hosts"* ]]
}

@test "dry-run preserves the remaining sudoers rules exactly" {
  local expected actual
  expected=$(cat <<'RULES'
Defaults:%admin  timestamp_timeout=60
%admin  ALL=(root) NOPASSWD: /usr/bin/true
%admin  ALL=(root) NOPASSWD: /sbin/ifconfig lo0 alias *
%admin  ALL=(root) NOPASSWD: /sbin/ifconfig lo0 -alias *
%admin  ALL=(root) NOPASSWD: /bin/launchctl bootstrap system /Library/LaunchDaemons/com.k3d-manager.*.plist
%admin  ALL=(root) NOPASSWD: /bin/launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.*.plist
%admin  ALL=(root) NOPASSWD: /usr/bin/install -m 644 * /Library/LaunchDaemons/com.k3d-manager.*.plist
%admin  ALL=(root) NOPASSWD: /bin/rm -f /Library/LaunchDaemons/com.k3d-manager.*.plist *
%admin  ALL=(root) NOPASSWD: /usr/local/bin/k3d-manager-update-hosts *
%admin  ALL=(root) NOPASSWD: /usr/local/bin/k3s *
%admin  ALL=(root) NOPASSWD: /usr/local/bin/k3s-uninstall.sh
%admin  ALL=(root) NOPASSWD: /usr/local/bin/k3s-killall.sh
%admin  ALL=(root) NOPASSWD: /usr/bin/systemctl *
%admin  ALL=(root) NOPASSWD: /usr/bin/apt-get *
%admin  ALL=(root) NOPASSWD: /usr/bin/dnf *
%admin  ALL=(root) NOPASSWD: /usr/bin/yum *
%admin  ALL=(root) NOPASSWD: /usr/bin/microdnf *
RULES
)
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  actual=$(printf '%s\n' "$output" | grep -E '^(Defaults:|%admin  ALL=)')
  [ "$actual" = "$expected" ]
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
