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

@test "install-sudoers.sh refuses bash 3.2 before reaching mktemp" {
  if /bin/bash -c '[[ ${BASH_VERSINFO[0]} -ge 4 ]]'; then
    skip "host /bin/bash is bash 4 or newer; regression requires bash 3.2"
  fi

  local stub_bin="${BATS_TEST_TMPDIR}/stub-bin"
  local mktemp_log="${BATS_TEST_TMPDIR}/mktemp.log"
  [ "${BATS_TEST_TMPDIR}" != "/tmp" ]
  mkdir -p "${stub_bin}"
  [[ "${stub_bin}" == "${BATS_TEST_TMPDIR}"/* ]]
  cat > "${stub_bin}/mktemp" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/mktemp.log"
exec /usr/bin/mktemp "$@"
STUB
  chmod +x "${stub_bin}/mktemp"
  cat > "${stub_bin}/visudo" <<'STUB'
#!/bin/sh
exit 0
STUB
  chmod +x "${stub_bin}/visudo"

  run env PATH="${stub_bin}:${PATH}" BATS_TEST_TMPDIR="${BATS_TEST_TMPDIR}" \
    /bin/bash "${SCRIPT}"
  [ "$status" -ne 0 ]
  local failed=0
  if [[ "$output" != *"bash 4.0 or newer is required"* ]]; then
    echo "M2 failed: bash 4 requirement was not reported"
    failed=1
  fi
  if [[ "$output" == *"unbound variable"* ]]; then
    echo "N1 failed: script reached the empty-array unbound-variable error"
    failed=1
  fi
  if [[ -e "${mktemp_log}" ]]; then
    echo "N2 failed: script reached mktemp"
    failed=1
  fi
  [ "$failed" -eq 0 ]
}

@test "install-sudoers.sh reaches mktemp under bash 4 or newer (positive control)" {
  local bash4
  bash4="$(command -v bash)"
  "$bash4" -c '[[ ${BASH_VERSINFO[0]} -ge 4 ]]' || skip "no bash 4 or newer on PATH"
  local stub_bin="${BATS_TEST_TMPDIR}/stub-bin"
  local mktemp_log="${BATS_TEST_TMPDIR}/mktemp.log"
  mkdir -p "${stub_bin}"
  [[ "${stub_bin}" == "${BATS_TEST_TMPDIR}"/* ]]
  cat > "${stub_bin}/mktemp" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/mktemp.log"
exec /usr/bin/mktemp "$@"
STUB
  chmod +x "${stub_bin}/mktemp"

  run env PATH="${stub_bin}:${PATH}" BATS_TEST_TMPDIR="${BATS_TEST_TMPDIR}" \
    "$bash4" "${SCRIPT}" --dry-run
  [ "$status" -eq 0 ]
  [ -s "${mktemp_log}" ]
}

@test "install-sudoers.sh --dry-run validates sudoers syntax" {
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Syntax OK"* ]]
}

@test "install mode installs both files through interactive sudo" {
  [ "$(grep -Fc '_run_command --interactive-sudo -- /usr/bin/install' "$SCRIPT")" -eq 2 ]
}

@test "sudoers dry-run removes browser LaunchDaemon and alias rules" {
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"/Library/LaunchDaemons"* ]]
  [[ "$output" != *"ifconfig lo0"* ]]
  [[ "$output" != *"launchctl bootstrap system"* ]]
  [[ "$output" != *"launchctl bootout system"* ]]
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
%admin  ALL=(root) NOPASSWD: /usr/local/bin/k3d-manager-update-hosts *
%admin  ALL=(root) NOPASSWD: /usr/local/bin/k3s *
%admin  ALL=(root) NOPASSWD: /usr/local/bin/k3s-uninstall.sh
%admin  ALL=(root) NOPASSWD: /usr/local/bin/k3s-killall.sh
RULES
)
  if [[ "$(uname -s)" == Linux ]]; then
    expected+=$'\n%admin  ALL=(root) NOPASSWD: /usr/bin/systemctl *\n%admin  ALL=(root) NOPASSWD: /usr/bin/apt-get *\n%admin  ALL=(root) NOPASSWD: /usr/bin/dnf *\n%admin  ALL=(root) NOPASSWD: /usr/bin/yum *\n%admin  ALL=(root) NOPASSWD: /usr/bin/microdnf *'
  fi
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  actual=$(printf '%s\n' "$output" | grep -E '^(Defaults:|%admin  ALL=)')
  [ "$actual" = "$expected" ]
}

@test "dry-run scopes Linux package rules to Linux uname" {
  local stub_bin="${BATS_TEST_TMPDIR}/uname-bin"
  mkdir -p "${stub_bin}"
  cat > "${stub_bin}/uname" <<'STUB'
#!/bin/sh
printf '%s\n' "${FAKE_UNAME:-Darwin}"
STUB
  chmod +x "${stub_bin}/uname"
  run env PATH="${stub_bin}:${PATH}" FAKE_UNAME=Darwin "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"/usr/bin/systemctl"* ]]
  run env PATH="${stub_bin}:${PATH}" FAKE_UNAME=Linux "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"/usr/bin/systemctl *"* ]]
  [[ "$output" == *"/usr/bin/apt-get *"* ]]
  [[ "$output" == *"/usr/bin/microdnf *"* ]]
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
