#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2329,SC2030,SC2031

setup() {
  SYSTEM_LIB="${BATS_TEST_DIRNAME}/../../lib/system.sh"
  # shellcheck source=/dev/null
  source "$SYSTEM_LIB"

  export HOME="${BATS_TEST_TMPDIR}/home"
  export REPO="${BATS_TEST_TMPDIR}/repo"
  export STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  export LAUNCHCTL_LOG="${BATS_TEST_TMPDIR}/launchctl.log"
  mkdir -p "${HOME}" "${STUB_BIN}" \
    "${REPO}/bin" "${REPO}/scripts/etc/launchd"

  cat > "${REPO}/bin/k3dm-hermes" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod 0755 "${REPO}/bin/k3dm-hermes"

  cat > "${REPO}/scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl" <<'EOF'
<plist>
  <string>{{HERMES_BIN}}</string>
  <string>{{K3DM_REPO_ROOT}}</string>
  <string>{{HERMES_LOG}}</string>
</plist>
EOF

  # uname stub — mac by default; UNAME_S overrides for the non-mac guard test.
  cat > "${STUB_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-s" ]]; then printf '%s\n' "${UNAME_S:-Darwin}"; else printf '%s\n' "arm64"; fi
EOF

  # security stub — every service present unless listed in SECURITY_MISSING.
  cat > "${STUB_BIN}/security" <<'EOF'
#!/usr/bin/env bash
svc=""
prev=""
for arg in "$@"; do
  [[ "${prev}" == "-s" ]] && svc="${arg}"
  prev="${arg}"
done
for miss in ${SECURITY_MISSING:-}; do
  [[ "${svc}" == "${miss}" ]] && exit 44
done
exit 0
EOF

  # launchctl stub — log invocations; fail the subcommand named in LAUNCHCTL_FAIL.
  cat > "${STUB_BIN}/launchctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${LAUNCHCTL_LOG}"
if [[ -n "${LAUNCHCTL_FAIL:-}" && "${1:-}" == "${LAUNCHCTL_FAIL}" ]]; then
  exit 1
fi
exit 0
EOF

  chmod 0755 "${STUB_BIN}/uname" "${STUB_BIN}/security" "${STUB_BIN}/launchctl"
  PATH="${STUB_BIN}:${PATH}"
  export PATH
}

@test "install: happy path renders plist and bootstraps the agent" {
  run _install_hermes_agent "${REPO}"
  [ "$status" -eq 0 ]

  plist="${HOME}/Library/LaunchAgents/com.k3d-manager.hermes.plist"
  [ -f "${plist}" ]
  # placeholders fully substituted
  run grep -c '{{' "${plist}"
  [ "$output" -eq 0 ]
  grep -q "${REPO}/bin/k3dm-hermes" "${plist}"
  grep -q "${HOME}/Library/Logs/k3dm-hermes.log" "${plist}"
  # bootout precedes bootstrap
  grep -q "bootout gui/.*/com.k3d-manager.hermes" "${LAUNCHCTL_LOG}"
  grep -q "bootstrap gui/.* ${HOME}/Library/LaunchAgents/com.k3d-manager.hermes.plist" "${LAUNCHCTL_LOG}"
}

@test "install: renders paths containing sed-special characters without corruption" {
  local special="${BATS_TEST_TMPDIR}/re&po|dir"
  mkdir -p "${special}/bin" "${special}/scripts/etc/launchd"
  cp "${REPO}/bin/k3dm-hermes" "${special}/bin/k3dm-hermes"
  cp "${REPO}/scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl" \
    "${special}/scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl"

  run _install_hermes_agent "${special}"
  [ "$status" -eq 0 ]

  plist="${HOME}/Library/LaunchAgents/com.k3d-manager.hermes.plist"
  # the literal special path survives substitution intact
  grep -qF "${special}/bin/k3dm-hermes" "${plist}"
  run grep -c '{{' "${plist}"
  [ "$output" -eq 0 ]
}

@test "install: returns non-zero when launchctl bootstrap fails" {
  export LAUNCHCTL_FAIL="bootstrap"
  run _install_hermes_agent "${REPO}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bootstrap failed"* ]]
}

@test "install: preflight fails and installs nothing when a credential is missing" {
  export SECURITY_MISSING="k3dm-hermes-gh-token"
  run _install_hermes_agent "${REPO}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"k3dm-hermes-gh-token"* ]]
  [[ "$output" == *"does not mint credentials"* ]]
  # no plist written, no bootstrap attempted
  [ ! -f "${HOME}/Library/LaunchAgents/com.k3d-manager.hermes.plist" ]
  [ ! -f "${LAUNCHCTL_LOG}" ]
}

@test "install: refuses on non-macOS hosts (off-hub laptop only)" {
  export UNAME_S="Linux"
  run _install_hermes_agent "${REPO}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"macOS-launchd only"* ]]
}

@test "install: fails when the launchd template is absent" {
  rm -f "${REPO}/scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl"
  run _install_hermes_agent "${REPO}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"template not found"* ]]
}

@test "uninstall: refuses on non-macOS hosts" {
  export UNAME_S="Linux"
  run _uninstall_hermes_agent
  [ "$status" -ne 0 ]
  [[ "$output" == *"macOS-launchd only"* ]]
}

@test "uninstall: boots out the agent and removes the plist" {
  mkdir -p "${HOME}/Library/LaunchAgents"
  plist="${HOME}/Library/LaunchAgents/com.k3d-manager.hermes.plist"
  printf '<plist/>\n' > "${plist}"

  run _uninstall_hermes_agent
  [ "$status" -eq 0 ]
  [ ! -f "${plist}" ]
  grep -q "bootout gui/.*/com.k3d-manager.hermes" "${LAUNCHCTL_LOG}"
}
