#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "sandbox frontend label is used by up, refresh, and down" {
  run grep -nF '_acg_install_loopback_frontend_listener sandbox-loopback-alias frontend-http' bin/cluster-up
  [ "${status}" -eq 0 ]
  run grep -nF '_acg_install_loopback_frontend_listener sandbox-loopback-alias frontend-http' bin/cluster-refresh
  [ "${status}" -eq 0 ]
  run grep -nF '"frontend-http": ("com.k3d-manager.sandbox.frontend-browser-http"' bin/k3dm-browser-listener-supervisor
  [ "${status}" -eq 0 ]
  run grep -nF 'com.k3d-manager.sandbox.frontend-browser-http' bin/cluster-down
  [ "${status}" -eq 0 ]
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
  run grep -nF '_acg_install_loopback_frontend_listener sandbox-loopback-alias frontend-http' bin/cluster-up
  [ "${status}" -eq 0 ]
}

@test "cluster-up loopback alias failure is soft and can prompt for sudo" {
  local callback="${BATS_TEST_TMPDIR}/alias-callback.sh"
  sed -n '/^function _acg_install_supervised_listener()/,/^}/p' bin/cluster-up > "${callback}"
  [ -s "${callback}" ]
  run grep -nF -- '_run_command --interactive-sudo --quiet --soft --' "${callback}"
  [ "${status}" -eq 0 ]
  run grep -nF -- '_run_command --prefer-sudo' "${callback}"
  [ "${status}" -ne 0 ]
  run grep -nF -- '127.0.0.3' bin/k3dm-browser-listener-supervisor
  [ "${status}" -eq 0 ]
}

@test "cluster-refresh has only the sandbox frontend address and plist" {
  run grep -nF '127.0.0.2' bin/cluster-refresh
  [ "${status}" -ne 0 ]
  run grep -nF '_acg_install_loopback_frontend_listener sandbox-loopback-alias frontend-http' bin/cluster-refresh
  [ "${status}" -eq 0 ]
  run grep -nF 'hostinger-frontend-http' bin/cluster-refresh
  [ "${status}" -ne 0 ]
  run grep -nF 'com.k3d-manager.frontend-browser-http' bin/k3dm-browser-listener-supervisor
  [ "${status}" -eq 0 ]
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

@test "Hostinger frontend port-forward uses the unprivileged fixed user LaunchAgent" {
  local plist="${BATS_TEST_TMPDIR}/home/Library/LaunchAgents/com.k3d-manager.frontend-browser-forward.plist"
  local wrapper="${BATS_TEST_TMPDIR}/k3s-hostinger/bin/frontend-browser-http.sh"
  local log_file="${BATS_TEST_TMPDIR}/k3s-hostinger/frontend.log"
  mkdir -p "${BATS_TEST_TMPDIR}/home" "${BATS_TEST_TMPDIR}/k3s-hostinger/bin"
  printf '#!/bin/sh\nexit 0\n' > "${wrapper}"
  : > "${log_file}"
  run bash -c '
    export HOME="$1/home"
    export _ACG_STATE_DIR="$1/k3s-hostinger"
    source "$2/scripts/lib/acg_browser_listeners.sh"
    _info() { :; }
    _warn() { printf "%s\\n" "$*" >&2; }
    _acg_write_user_listener_agent com.k3d-manager.frontend-browser-forward "$3" "$4"
  ' bash "${BATS_TEST_TMPDIR}" "${REPO_ROOT}" "${wrapper}" "${log_file}"
  [ "${status}" -eq 0 ]
  run python3 - "${plist}" "${wrapper}" "${log_file}" <<'PY'
import plistlib
import sys

plist_path, wrapper_path, log_file = sys.argv[1:]
with open(plist_path, "rb") as handle:
    plist = plistlib.load(handle)
arguments = plist["ProgramArguments"]
expected = ["/bin/bash", wrapper_path]
if arguments != expected:
    raise SystemExit(f"ProgramArguments={arguments!r}; expected {expected!r}")
if plist["UserName"] if "UserName" in plist else False:
    raise SystemExit("user LaunchAgent must not request a privileged UserName")
if plist["StandardOutPath"] != log_file:
    raise SystemExit("unexpected log path")
print("ProgramArguments match")
PY
  [ "${status}" -eq 0 ]
  [ "${output}" = "ProgramArguments match" ]
}

@test "Hostinger refresh installs only fixed browser listeners through the supervisor" {
  local helper="${BATS_TEST_TMPDIR}/hostinger-listeners.sh"
  sed -n '/^function _hostinger_install_fixed_browser_listeners()/,/^}/p' \
    scripts/lib/providers/k3s-hostinger.sh > "${helper}"
  [ -s "${helper}" ]
  run env ARGOCD_BROWSER_PORT=8443 HOSTINGER_LISTENER_FIXTURE="${BATS_TEST_TMPDIR}" HOSTINGER_LISTENER_HELPER="${helper}" bash -c '
    _ACG_STATE_DIR="${HOSTINGER_LISTENER_FIXTURE}/state"
    CLUSTER_PROVIDER=k3s-hostinger
    mkdir -p "${HOSTINGER_LISTENER_FIXTURE}/state"
    calls="${HOSTINGER_LISTENER_FIXTURE}/listener-calls"
    _acg_provider_state_dir() { [[ "$1" == k3s-hostinger ]]; printf "%s\n" "${HOSTINGER_LISTENER_FIXTURE}/state"; }
    _run_command() { printf "%s\n" "$*" >> "$calls"; }
    _warn() { printf "WARN:%s\n" "$*"; }
    source "${HOSTINGER_LISTENER_HELPER}"
    _hostinger_install_fixed_browser_listeners
    [[ $(wc -l < "$calls") -eq 4 ]]
    grep -q "write argocd-https" "$calls"
    grep -q "write argocd-https .* 8443" "$calls"
    grep -q "write keycloak-http" "$calls"
    grep -q "write hostinger-frontend-http" "$calls"
    grep -q "write hostinger-loopback-alias" "$calls"
    if grep -q "launchctl bootstrap system" "$calls"; then exit 1; fi
  '
  [ "${status}" -eq 0 ]
}
