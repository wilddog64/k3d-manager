#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  mkdir -p "${HOME}/.kube" "${HOME}/Library/LaunchAgents" "${BATS_TEST_TMPDIR}/bin"
  : > "${BATS_TEST_TMPDIR}/launchctl.log"
  : > "${BATS_TEST_TMPDIR}/kubectl.log"
  cat > "${BATS_TEST_TMPDIR}/bin/launchctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/launchctl.log"
if [[ "${1:-}" == list ]]; then
  exit "${LAUNCHCTL_LIST_STATUS:-1}"
fi
exit 0
EOF
  cat > "${BATS_TEST_TMPDIR}/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/kubectl.log"
if [[ "$*" == *"port-forward"* ]]; then
  exit 99
fi
exit 0
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/launchctl" "${BATS_TEST_TMPDIR}/bin/kubectl"
}

extract_prometheus_else() {
  local source="${1:-${CLUSTER_UP_SOURCE:-bin/cluster-up}}"
  awk '
    /_acg_prom_svc_ready/ { seen=1; next }
    seen && /^else$/ { active=1; depth=1; print "if [[ 1 -eq 1 ]]; then"; next }
    active {
      print
      if ($0 ~ /^  if /) depth++
      if ($0 ~ /^fi$/ || $0 ~ /^  fi$/) depth--
      if (depth == 0) exit
    }
  ' "${source}"
}

@test "sandbox Prometheus Step 14b installs a self-healing launchd plist" {
  local branch="${BATS_TEST_TMPDIR}/branch.sh"
  extract_prometheus_else > "${branch}"
  run env _ACG_STATE_DIR="${BATS_TEST_TMPDIR}/state" \
    _acg_prom_pf_pid_file="${BATS_TEST_TMPDIR}/state/run/acg-prom-pf.pid" \
    _acg_prom_local_port=19191 _acg_observability_context=ubuntu-k3s \
    bash -c 'mkdir -p "${_ACG_STATE_DIR}" 2>/dev/null || true; _info() { :; }; source "$1"' bash "${branch}"
  [ "${status}" -eq 0 ]
  local plist="${HOME}/Library/LaunchAgents/com.k3d-manager.sandbox.prometheus-port-forward.plist"
  [ -f "${plist}" ]
  grep -Fq '<key>KeepAlive</key>' "${plist}"
  grep -Fq '<true/>' "${plist}"
  grep -Fq '<string>19191:9090</string>' "${plist}"
  grep -Fq '<string>ubuntu-k3s</string>' "${plist}"
  grep -Fq '<string>0.0.0.0</string>' "${plist}"
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "${plist}"
  fi
  grep -Fq "load ${plist}" "${BATS_TEST_TMPDIR}/launchctl.log"
  ! grep -Fq 'port-forward' "${BATS_TEST_TMPDIR}/kubectl.log"
  [ ! -f "${BATS_TEST_TMPDIR}/state/run/acg-prom-pf.pid" ]
}

@test "sandbox Prometheus Step 14b removes a legacy pidfile" {
  local branch="${BATS_TEST_TMPDIR}/branch.sh"
  mkdir -p "${BATS_TEST_TMPDIR}/state/run"
  printf '%s\n' 12345 > "${BATS_TEST_TMPDIR}/state/run/acg-prom-pf.pid"
  extract_prometheus_else > "${branch}"
  run env _ACG_STATE_DIR="${BATS_TEST_TMPDIR}/state" \
    _acg_prom_pf_pid_file="${BATS_TEST_TMPDIR}/state/run/acg-prom-pf.pid" \
    _acg_prom_local_port=19191 _acg_observability_context=ubuntu-k3s \
    bash -c 'kill() { :; }; _info() { :; }; source "$1"' bash "${branch}"
  [ "${status}" -eq 0 ]
  [ ! -e "${BATS_TEST_TMPDIR}/state/run/acg-prom-pf.pid" ]
}

@test "cluster-down and cleanup target only the sandbox Prometheus agent" {
  run grep -nF 'com.k3d-manager.sandbox.prometheus-port-forward' bin/cluster-down
  [ "${status}" -eq 0 ]
  run grep -nF 'com.k3d-manager.sandbox.prometheus-port-forward' bin/cleanup-stale-sandbox
  [ "${status}" -eq 0 ]
  run grep -nF 'com.k3d-manager.prometheus-port-forward' bin/cluster-down bin/cleanup-stale-sandbox
  [ "${status}" -ne 0 ]
}

@test "cluster-refresh uses launchd when the sandbox Prometheus plist exists" {
  run grep -nF '_launchd_ensure "${_acg_prom_pf_label}" "${_acg_prom_pf_plist}" user' bin/cluster-refresh
  [ "${status}" -eq 0 ]
  run grep -nF '_pf_ensure "ACG Prometheus port-forward"' bin/cluster-refresh
  [ "${status}" -eq 0 ]
}
