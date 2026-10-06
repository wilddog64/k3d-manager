#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "sandbox frontend label is used by up, refresh, and down" {
  for script in bin/cluster-up bin/cluster-refresh bin/cluster-down; do
    run grep -nF 'com.k3d-manager.sandbox.frontend-browser-http' "${script}"
    [ "${status}" -eq 0 ]
  done
}

@test "cluster-up has no Hostinger frontend label or address" {
  run grep -nF '_frontend_browser_label="com.k3d-manager.frontend-browser-http"' bin/cluster-up
  [ "${status}" -ne 0 ]
  run grep -nF '_pgw_pf_label="com.k3d-manager.pushgateway-port-forward"' bin/cluster-up
  [ "${status}" -ne 0 ]
  run grep -c '127\.0\.0\.2' bin/cluster-up
  [ "${status}" -eq 1 ]
  [ "${output}" -eq 0 ]
}

@test "cluster-up scopes the loopback alias and Pushgateway port" {
  run grep -nF '9092:9091' bin/cluster-up
  [ "${status}" -eq 0 ]
  run grep -nF 'com.k3d-manager.sandbox.loopback-alias' bin/cluster-up
  [ "${status}" -eq 0 ]
}

@test "cluster-up loopback alias failure is soft and can prompt for sudo" {
  run grep -nF -- '--interactive-sudo --quiet --soft -- /sbin/ifconfig lo0 alias 127.0.0.3' bin/cluster-up
  [ "${status}" -eq 0 ]
  run grep -nF -- '--prefer-sudo --quiet -- /sbin/ifconfig lo0 alias' bin/cluster-up
  [ "${status}" -eq 1 ]
}

@test "cluster-refresh has only the sandbox frontend address and plist" {
  run grep -nF '127.0.0.2' bin/cluster-refresh
  [ "${status}" -ne 0 ]
  run grep -nF '/Library/LaunchDaemons/com.k3d-manager.frontend-browser-http.plist' bin/cluster-refresh
  [ "${status}" -ne 0 ]
}

@test "cluster-down removes legacy sandbox-owned plists but preserves Hostinger plists" {
  local block="${BATS_TEST_TMPDIR}/legacy-cleanup.sh"
  local frontend="${BATS_TEST_TMPDIR}/frontend.plist"
  local pushgateway="${BATS_TEST_TMPDIR}/pushgateway.plist"
  local rm_log="${BATS_TEST_TMPDIR}/rm.log"
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_bin}"
  sed -n '/# legacy-unscoped-cleanup:begin/,/# legacy-unscoped-cleanup:end/p' \
    bin/cluster-down > "${block}"
  for command in launchctl sudo rm; do
    cat > "${stub_bin}/${command}" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "${RM_LOG}"
STUB
    chmod +x "${stub_bin}/${command}"
  done

  printf '%s\n' "${BATS_TEST_TMPDIR}/state/bin/frontend-browser-http.sh" > "${frontend}"
  printf '%s\n' 'ubuntu-k3s' > "${pushgateway}"
  run env PATH="${stub_bin}:${PATH}" RM_LOG="${rm_log}" \
    LEGACY_FRONTEND_BROWSER_PLIST="${frontend}" LEGACY_PUSHGATEWAY_PLIST="${pushgateway}" \
    bash -c '
      _ACG_STATE_DIR="$1"
      _run_command() { printf "run_command %s\n" "$*" >> "${RM_LOG}"; return 0; }
      _dry_guard() { shift; "$@"; }
      _dry_run_active() { return 1; }
      _info() { printf "%s\n" "$*"; }
      source "$2"
    ' bash "${BATS_TEST_TMPDIR}/state" "${block}"
  [ "${status}" -eq 0 ]
  run grep -F "rm -f ${frontend}" "${rm_log}"
  [ "${status}" -eq 0 ]
  run grep -F "rm -f ${pushgateway}" "${rm_log}"
  [ "${status}" -eq 0 ]

  printf '%s\n' 'k3s-hostinger' > "${frontend}"
  printf '%s\n' 'ubuntu-hostinger' > "${pushgateway}"
  : > "${rm_log}"
  run env PATH="${stub_bin}:${PATH}" RM_LOG="${rm_log}" \
    LEGACY_FRONTEND_BROWSER_PLIST="${frontend}" LEGACY_PUSHGATEWAY_PLIST="${pushgateway}" \
    bash -c '
      _ACG_STATE_DIR="$1"
      _run_command() { printf "run_command %s\n" "$*" >> "${RM_LOG}"; return 0; }
      _dry_guard() { shift; "$@"; }
      _dry_run_active() { return 1; }
      _info() { printf "%s\n" "$*"; }
      source "$2"
    ' bash "${BATS_TEST_TMPDIR}/state" "${block}"
  [ "${status}" -eq 0 ]
  run grep -F 'belongs to another provider' <<<"${output}"
  [ "${status}" -eq 0 ]
  run grep -F 'rm -f' "${rm_log}"
  [ "${status}" -ne 0 ]
}

@test "cluster-down legacy cleanup changes nothing under dry-run" {
  local block="${BATS_TEST_TMPDIR}/legacy-cleanup-dry-run.sh"
  local frontend="${BATS_TEST_TMPDIR}/frontend-dry-run.plist"
  local pushgateway="${BATS_TEST_TMPDIR}/pushgateway-dry-run.plist"
  local rm_log="${BATS_TEST_TMPDIR}/dry-run.log"
  local stub_bin="${BATS_TEST_TMPDIR}/dry-run-bin"
  mkdir -p "${stub_bin}"
  sed -n '/# legacy-unscoped-cleanup:begin/,/# legacy-unscoped-cleanup:end/p' \
    bin/cluster-down > "${block}"
  for command in launchctl sudo rm; do
    cat >"${stub_bin}/${command}" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "${RM_LOG}"
STUB
    chmod +x "${stub_bin}/${command}"
  done
  printf '%s\n' "${BATS_TEST_TMPDIR}/state/bin/frontend-browser-http.sh" > "${frontend}"
  printf '%s\n' 'ubuntu-k3s' > "${pushgateway}"
  run env PATH="${stub_bin}:${PATH}" RM_LOG="${rm_log}" \
    LEGACY_FRONTEND_BROWSER_PLIST="${frontend}" LEGACY_PUSHGATEWAY_PLIST="${pushgateway}" \
    bash -c '
      _ACG_STATE_DIR="$1"
      _run_command() { printf "run_command %s\n" "$*" >> "${RM_LOG}"; return 0; }
      _dry_guard() { local _desc="${1:-}"; shift || true; if _dry_run_active; then _info "DRY_RUN: would ${_desc}"; return 0; fi; "$@"; }
      _dry_run_active() { return 0; }
      _info() { printf "%s\n" "$*"; }
      source "$2"
    ' bash "${BATS_TEST_TMPDIR}/state" "${block}"
  [ "${status}" -eq 0 ]
  [ ! -s "${rm_log}" ]
  grep -Fq 'DRY_RUN: would unload legacy sandbox frontend browser HTTP daemon' <<<"${output}"
  grep -Fq 'DRY_RUN: would unload legacy sandbox Pushgateway port-forward LaunchAgent' <<<"${output}"
}

@test "Hostinger frontend plist has exactly two ProgramArguments" {
  local plist="${BATS_TEST_TMPDIR}/frontend-browser-http.plist"
  local wrapper="${BATS_TEST_TMPDIR}/k3s-hostinger/bin/frontend-browser-http.sh"
  local log_file="${BATS_TEST_TMPDIR}/frontend.log"
  run bash -c '
    SCRIPT_DIR="$1/scripts"
    _ACG_STATE_DIR="$1/state"
    source "$1/scripts/lib/providers/k3s-hostinger.sh"
    _hostinger_write_frontend_browser_plist "$2" "$3" "$4"
  ' bash "${REPO_ROOT}" "${plist}" "${wrapper}" "${log_file}"
  [ "${status}" -eq 0 ]
  run plutil -extract ProgramArguments json -o - "${plist}"
  [ "${status}" -eq 0 ]
  local escaped_wrapper="${wrapper//\//\\/}"
  [ "${output}" = "[\"\\/bin\\/bash\",\"${escaped_wrapper}\"]" ]
  [ "$(printf '%s' "${output}" | tr -cd ',' | wc -c | tr -d ' ')" -eq 1 ]
}
