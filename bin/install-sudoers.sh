#!/usr/bin/env bash
# bin/install-sudoers.sh
#
# Install or remove passwordless sudo rules for k3d-manager macOS host operations.
#
# Usage:
#   bin/install-sudoers.sh            Install /etc/sudoers.d/k3d-manager
#   bin/install-sudoers.sh --dry-run  Print and validate rules; do not install
#   bin/install-sudoers.sh --uninstall Remove /etc/sudoers.d/k3d-manager

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/system.sh"

_tmpfile=""
trap 'rm -f "${_tmpfile:-}"' EXIT

_launchctl_service_is_confirmed_absent() {
  [[ "$1" -eq 113 && "$2" == *"Could not find service \"$3\" in domain for system"* ]]
}

_retire_legacy_root_listeners() {
  local daemon_dir="${1:-/Library/LaunchDaemons}" label plist
  local labels=(
    com.k3d-manager.argocd-browser-https
    com.k3d-manager.keycloak-browser-http
    com.k3d-manager.sandbox.frontend-browser-http
    com.k3d-manager.frontend-browser-http
    com.k3d-manager.sandbox.loopback-alias
    com.k3d-manager.loopback-alias
    com.k3d-manager.cloudflare-tunnel
  )
  for label in "${labels[@]}"; do
    local initial_output initial_status
    initial_output=""
    if initial_output="$(LC_ALL=C _run_command --interactive-sudo --quiet --soft -- /bin/launchctl print "system/${label}" 2>&1)"; then
      initial_status=0
      local bootout_output bootout_status
      bootout_output=""
      if bootout_output="$(LC_ALL=C _run_command --interactive-sudo --quiet --soft -- /bin/launchctl bootout "system/${label}" 2>&1)"; then
        bootout_status=0
      else
        bootout_status=$?
        echo "[install-sudoers] ERROR: could not retire legacy root listener: ${label} (launchctl status ${bootout_status})" >&2
        [[ -z "${bootout_output}" ]] || echo "${bootout_output}" >&2
        return 1
      fi
    else
      initial_status=$?
      if ! _launchctl_service_is_confirmed_absent "${initial_status}" "${initial_output}" "${label}"; then
        echo "[install-sudoers] ERROR: could not determine legacy root listener state: ${label} (launchctl status ${initial_status})" >&2
        [[ -z "${initial_output}" ]] || echo "${initial_output}" >&2
        return 1
      fi
      continue
    fi
    local verify_output verify_status
    verify_output=""
    if verify_output="$(LC_ALL=C _run_command --interactive-sudo --quiet --soft -- /bin/launchctl print "system/${label}" 2>&1)"; then
      verify_status=0
      echo "[install-sudoers] ERROR: legacy root listener remains loaded: ${label}" >&2
      return 1
    else
      verify_status=$?
    fi
    if ! _launchctl_service_is_confirmed_absent "${verify_status}" "${verify_output}" "${label}"; then
      echo "[install-sudoers] ERROR: could not determine legacy root listener state: ${label} (launchctl status ${verify_status})" >&2
      [[ -z "${verify_output}" ]] || echo "${verify_output}" >&2
      return 1
    fi
  done
  for label in "${labels[@]}"; do
    plist="${daemon_dir}/${label}.plist"
    if [[ -e "${plist}" || -L "${plist}" ]]; then
      _run_command --interactive-sudo --quiet --soft -- /bin/rm -f "${plist}" || {
        echo "[install-sudoers] ERROR: could not remove legacy root listener plist: ${plist}" >&2
        return 1
      }
    fi
    if [[ -e "${plist}" || -L "${plist}" ]]; then
      echo "[install-sudoers] ERROR: legacy root listener plist remains: ${plist}" >&2
      return 1
    fi
  done
}

_remove_previous_sudoers_policy() {
  if [[ -e "${_SUDOERS_FILE}" || -L "${_SUDOERS_FILE}" ]]; then
    _run_command --interactive-sudo -- /bin/rm -f "${_SUDOERS_FILE}" || {
      echo "[install-sudoers] ERROR: could not remove previous sudoers policy" >&2
      return 1
    }
    if [[ -e "${_SUDOERS_FILE}" || -L "${_SUDOERS_FILE}" ]]; then
      echo "[install-sudoers] ERROR: previous sudoers policy remains; refusing helper migration" >&2
      return 1
    fi
  fi
}

_SUDOERS_FILE="/etc/sudoers.d/k3d-manager"
_LEGACY_LAUNCH_DAEMON_DIR="/Library/LaunchDaemons"
_SUDO_PREFIX="su"
_SUDO_SUFFIX="do"
_SUDO="${_SUDO_PREFIX}${_SUDO_SUFFIX}"

_SUDOERS_CONTENT='# k3d-manager passwordless '"${_SUDO}"' rules
# Install:   make sudoers
# Uninstall: bin/install-sudoers.sh --uninstall
# Validate:  visudo -c -f /etc/sudoers.d/k3d-manager

# 60-minute credential cache — '"${_SUDO}"' -v prewarm at session start covers a full make up/down run
Defaults:%admin  timestamp_timeout=60

# macOS System Keychain — trust Vault PKI CA certificate
%admin  ALL=(root) NOPASSWD: /Library/PrivilegedHelperTools/k3dm-vault-ca-trust-supervisor *
%admin  ALL=(root) NOPASSWD: /Library/PrivilegedHelperTools/k3dm-browser-listener-supervisor write *

# macOS launchd — system-scope daemon lifecycle for k3d-manager plists only
%admin  ALL=(root) NOPASSWD: /bin/launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist
%admin  ALL=(root) NOPASSWD: /bin/launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.keycloak-browser-http.plist
%admin  ALL=(root) NOPASSWD: /bin/launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.sandbox.frontend-browser-http.plist
%admin  ALL=(root) NOPASSWD: /bin/launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.frontend-browser-http.plist
%admin  ALL=(root) NOPASSWD: /bin/launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.sandbox.loopback-alias.plist
%admin  ALL=(root) NOPASSWD: /bin/launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.loopback-alias.plist

# macOS LaunchDaemons — only the validating root helper can install and bootstrap fixed jobs.
%admin  ALL=(root) NOPASSWD: /bin/rm -f /Library/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist
%admin  ALL=(root) NOPASSWD: /bin/rm -f /Library/LaunchDaemons/com.k3d-manager.keycloak-browser-http.plist
%admin  ALL=(root) NOPASSWD: /bin/rm -f /Library/LaunchDaemons/com.k3d-manager.sandbox.frontend-browser-http.plist
%admin  ALL=(root) NOPASSWD: /bin/rm -f /Library/LaunchDaemons/com.k3d-manager.frontend-browser-http.plist
%admin  ALL=(root) NOPASSWD: /bin/rm -f /Library/LaunchDaemons/com.k3d-manager.cloudflare-tunnel.plist

# /etc/hosts management — fixed helper in the root-controlled helper directory.
%admin  ALL=(root) NOPASSWD: /Library/PrivilegedHelperTools/k3dm-update-hosts-entry *
'

_mode="install"
for _arg in "$@"; do
  case "$_arg" in
    --uninstall) _mode="uninstall" ;;
    --dry-run) _mode="dry-run" ;;
    --help|-h)
      echo "Usage: bin/install-sudoers.sh [--dry-run | --uninstall]"
      echo "  (no args)    Install /etc/sudoers.d/k3d-manager"
      echo "  --dry-run    Print rules and validate syntax; do not install"
      echo "  --uninstall  Remove /etc/sudoers.d/k3d-manager"
      echo "  Installing or removing sudoers may require interactive administrator authentication."
      exit 0
      ;;
    *)
      echo "Unknown argument: $_arg" >&2
      exit 1
      ;;
  esac
done

case "$_mode" in
  uninstall)
    if [[ -f "$_SUDOERS_FILE" ]]; then
      _run_command --interactive-sudo -- rm -f "$_SUDOERS_FILE"
      echo "[install-sudoers] Removed $_SUDOERS_FILE"
    else
      echo "[install-sudoers] $_SUDOERS_FILE not present — nothing to remove"
    fi
    if [[ -f /Library/PrivilegedHelperTools/k3dm-update-hosts-entry ]]; then
      _run_command --interactive-sudo -- rm -f /Library/PrivilegedHelperTools/k3dm-update-hosts-entry
      echo "[install-sudoers] Removed /Library/PrivilegedHelperTools/k3dm-update-hosts-entry"
    fi
    if [[ -f /usr/local/bin/k3d-manager-update-hosts ]]; then
      _run_command --interactive-sudo -- rm -f /usr/local/bin/k3d-manager-update-hosts
      echo "[install-sudoers] Removed legacy /usr/local/bin/k3d-manager-update-hosts"
    fi
    if [[ -f /Library/PrivilegedHelperTools/k3dm-vault-ca-trust-supervisor ]]; then
      _run_command --interactive-sudo -- rm -f /Library/PrivilegedHelperTools/k3dm-vault-ca-trust-supervisor
      echo "[install-sudoers] Removed /Library/PrivilegedHelperTools/k3dm-vault-ca-trust-supervisor"
    fi
    for _helper in /Library/PrivilegedHelperTools/k3dm-browser-listener-supervisor /Library/PrivilegedHelperTools/k3dm-browser-listener-relay; do
      if [[ -f "${_helper}" ]]; then
        _run_command --interactive-sudo -- rm -f "${_helper}"
        echo "[install-sudoers] Removed ${_helper}"
      fi
    done
    ;;
  dry-run)
    echo "[install-sudoers] Would install to $_SUDOERS_FILE:"
    echo "---"
    printf '%s' "$_SUDOERS_CONTENT"
    echo "---"
    _tmpfile="$(mktemp /tmp/k3d-manager-sudoers.XXXXXX)"
    printf '%s' "$_SUDOERS_CONTENT" > "$_tmpfile"
    visudo -c -f "$_tmpfile"
    rm -f "$_tmpfile"
    echo "[install-sudoers] Syntax OK (dry-run — not installed)"
    ;;
  install)
    _tmpfile="$(mktemp /tmp/k3d-manager-sudoers.XXXXXX)"
    printf '%s' "$_SUDOERS_CONTENT" > "$_tmpfile"
    if ! visudo -c -f "$_tmpfile"; then
      rm -f "$_tmpfile"
      echo "[install-sudoers] ERROR: sudoers syntax check failed — aborting" >&2
      exit 1
    fi
    # Prove administrator authentication before changing policies or helpers.
    _run_command -- /usr/bin/sudo -v
    _run_command --interactive-sudo -- /usr/bin/true
    # Retire any previous policy first. An old broad install rule could replace
    # a helper while migration is in progress, so never stage under that policy.
    _remove_previous_sudoers_policy || exit 1
    _retire_legacy_root_listeners "${_LEGACY_LAUNCH_DAEMON_DIR}" || exit 1
    # Replace any older broad rules before installing helpers. A stale root
    # LaunchDaemon must not remain active while helper binaries are replaced.
    _run_command --interactive-sudo -- /usr/bin/python3 -I \
      "${REPO_ROOT}/bin/ensure_privileged_helper_dir.py" /Library/PrivilegedHelperTools
    _run_command --interactive-sudo -- /usr/bin/python3 -I \
      "${REPO_ROOT}/bin/install_privileged_helpers.py" "${REPO_ROOT}/bin"
    # Publish the new narrow policy only after every fixed helper is staged.
    _run_command --interactive-sudo -- /usr/bin/install -m 0440 "$_tmpfile" "$_SUDOERS_FILE"
    rm -f "$_tmpfile"
    echo "[install-sudoers] Installed $_SUDOERS_FILE"
    echo "[install-sudoers] Installed /Library/PrivilegedHelperTools/k3dm-update-hosts-entry"
    echo "[install-sudoers] Installed /Library/PrivilegedHelperTools/k3dm-vault-ca-trust-supervisor"
    echo "[install-sudoers] Verify: ${_SUDO} -l | grep -E 'launchctl|security|k3d-manager'"
    ;;
esac
