# shellcheck shell=bash
# Helpers for unprivileged LaunchAgents which back the root-owned socket relays.

function _acg_validate_browser_listener_config() {
  local state_dir="$1" expected_label="com.k3d-manager.argocd-browser-https"
  local expected_plist="/Library/LaunchDaemons/${expected_label}.plist"
  local expected_wrapper="${state_dir}/bin/argocd-browser-https.sh"
  local expected_log="${state_dir}/logs/argocd-browser-https.log"
  local expected_launchctl_log="${state_dir}/logs/argocd-browser-https-launchctl.log"
  local expected_keycloak_label="com.k3d-manager.keycloak-browser-http"
  local expected_keycloak_plist="/Library/LaunchDaemons/com.k3d-manager.keycloak-browser-http.plist"
  local expected_keycloak_wrapper="${state_dir}/bin/keycloak-browser-http.sh"
  local expected_keycloak_log="${state_dir}/logs/keycloak-browser-http.log"
  local expected_keycloak_launchctl_log="${state_dir}/logs/keycloak-browser-http-launchctl.log"
  local expected_frontend_plist="/Library/LaunchDaemons/com.k3d-manager.sandbox.frontend-browser-http.plist"
  local expected_startup_timeout=30
  local name value expected
  for name in ARGOCD_BROWSER_LISTENER_LABEL ARGOCD_BROWSER_LISTENER_PLIST \
      ARGOCD_BROWSER_LISTENER_WRAPPER ARGOCD_BROWSER_LISTENER_LOG \
      ARGOCD_BROWSER_LISTENER_LAUNCHCTL_LOG ARGOCD_BROWSER_LISTENER_STARTUP_TIMEOUT \
      KEYCLOAK_BROWSER_LISTENER_LABEL KEYCLOAK_BROWSER_LISTENER_PLIST \
      KEYCLOAK_BROWSER_LISTENER_WRAPPER KEYCLOAK_BROWSER_LISTENER_LOG \
      KEYCLOAK_BROWSER_LISTENER_LAUNCHCTL_LOG FRONTEND_BROWSER_LISTENER_PLIST; do
    case "${name}" in
      ARGOCD_BROWSER_LISTENER_LABEL) expected="${expected_label}" ;;
      ARGOCD_BROWSER_LISTENER_PLIST) expected="${expected_plist}" ;;
      ARGOCD_BROWSER_LISTENER_WRAPPER) expected="${expected_wrapper}" ;;
      ARGOCD_BROWSER_LISTENER_LOG) expected="${expected_log}" ;;
      ARGOCD_BROWSER_LISTENER_LAUNCHCTL_LOG) expected="${expected_launchctl_log}" ;;
      ARGOCD_BROWSER_LISTENER_STARTUP_TIMEOUT) expected="${expected_startup_timeout}" ;;
      KEYCLOAK_BROWSER_LISTENER_LABEL) expected="${expected_keycloak_label}" ;;
      KEYCLOAK_BROWSER_LISTENER_PLIST) expected="${expected_keycloak_plist}" ;;
      KEYCLOAK_BROWSER_LISTENER_WRAPPER) expected="${expected_keycloak_wrapper}" ;;
      KEYCLOAK_BROWSER_LISTENER_LOG) expected="${expected_keycloak_log}" ;;
      KEYCLOAK_BROWSER_LISTENER_LAUNCHCTL_LOG) expected="${expected_keycloak_launchctl_log}" ;;
      FRONTEND_BROWSER_LISTENER_PLIST) expected="${expected_frontend_plist}" ;;
    esac
    value="${!name:-${expected}}"
    if [[ "${value}" != "${expected}" ]]; then
      _warn "[acg-listener] ${name}=${value} is unsupported by the fixed privileged listener; unset it or restore ${expected} before retrying. The listener uses root-controlled LaunchDaemon paths and /dev/null logging."
      return 1
    fi
  done
  _info "[acg-listener] ARGOCD_BROWSER_LISTENER_STARTUP_TIMEOUT is obsolete for the fixed socket relay; health readiness is governed by ARGOCD_BROWSER_LISTENER_WAIT_TIMEOUT"
  _info "[acg-listener] fixed root listeners send output to /dev/null; readiness uses HTTPS health checks, and legacy listener log files are not produced"
  value="${ARGOCD_BROWSER_HOST:-argocd.shopping-cart.local}"
  if ((${#value} > 253)) || [[ ! "${value}" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
    _warn "[acg-listener] refusing unsafe ARGOCD_BROWSER_HOST value; use DNS labels of 1-63 letters, digits or interior hyphens"
    return 1
  fi
  local -a labels
  IFS='.' read -r -a labels <<< "${value}"
  local label
  for label in "${labels[@]}"; do
    if ((${#label} == 0 || ${#label} > 63)) || \
        [[ ! "${label}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]; then
      _warn "[acg-listener] refusing unsafe ARGOCD_BROWSER_HOST value; each DNS label must be 1-63 characters and cannot start or end with a hyphen"
      return 1
    fi
  done
  value="${ARGOCD_BROWSER_PORT:-443}"
  if [[ ! "${value}" =~ ^[1-9][0-9]{0,4}$ ]] || (( value > 65535 )); then
    _warn "[acg-listener] refusing invalid ARGOCD_BROWSER_PORT=${value}; use a decimal port from 1 through 65535"
    return 1
  fi
}

function _acg_install_loopback_frontend_listener() {
  local alias_service="$1" frontend_service="$2" alias_installer="$3" frontend_installer="$4"
  "${alias_installer}" "${alias_service}" && "${frontend_installer}" "${frontend_service}"
}

function _acg_write_user_listener_agent() {
  local label="$1" wrapper="$2" log_file="$3" plist="${HOME}/Library/LaunchAgents/${1}.plist"
  case "${label}" in
    com.k3d-manager.keycloak-browser-forward|com.k3d-manager.sandbox.frontend-browser-forward|com.k3d-manager.frontend-browser-forward) ;;
    *) _warn "[acg-listener] refusing unsupported user listener label: ${label}"; return 2 ;;
  esac
  [[ "${wrapper}" == "${_ACG_STATE_DIR}"/* && "${log_file}" == "${_ACG_STATE_DIR}"/* ]] || {
    _warn "[acg-listener] refusing user listener paths outside state directory"
    return 2
  }
  mkdir -p "$(dirname "${plist}")"
  python3 - "${plist}" "${label}" "${wrapper}" "${log_file}" "${_ACG_STATE_DIR}" <<'PY'
import os
import plistlib
import sys

path, label, wrapper, log_file, state_dir = sys.argv[1:]
home = os.path.realpath(os.environ["HOME"])
state_root = os.path.realpath(state_dir)
if os.path.commonpath((home, os.path.realpath(os.path.dirname(path)))) != home:
    raise SystemExit("LaunchAgent plist path escaped HOME")
if os.path.commonpath((state_root, os.path.realpath(wrapper))) != state_root:
    raise SystemExit("LaunchAgent wrapper escaped the configured state directory")
if os.path.commonpath((state_root, os.path.realpath(os.path.dirname(log_file)))) != state_root:
    raise SystemExit("LaunchAgent log escaped the configured state directory")
plist = {
    "Label": label,
    "ProgramArguments": ["/bin/bash", wrapper],
    "RunAtLoad": True,
    "KeepAlive": True,
    "StandardOutPath": log_file,
    "StandardErrorPath": log_file,
}
with open(path, "wb") as stream:
    plistlib.dump(plist, stream, fmt=plistlib.FMT_XML, sort_keys=True)
os.chmod(path, 0o600)
PY
}

function _acg_start_user_listener_agent() {
  local label="$1" plist="${HOME}/Library/LaunchAgents/${1}.plist" uid
  uid="$(id -u)"
  _run_command --quiet --soft -- launchctl bootout "gui/${uid}/${label}" >/dev/null 2>&1 || true
  _run_command --quiet --soft -- launchctl bootstrap "gui/${uid}" "${plist}"
}

function _acg_remove_user_listener_agent() {
  local label="$1" plist="${HOME}/Library/LaunchAgents/${1}.plist" uid
  if _dry_run_active; then
    _info "DRY_RUN: would unload and remove user listener LaunchAgent ${label}"
    return 0
  fi
  uid="$(id -u)"
  _run_command --quiet --soft -- launchctl bootout "gui/${uid}/${label}" >/dev/null 2>&1 || true
  rm -f -- "${plist}"
}
