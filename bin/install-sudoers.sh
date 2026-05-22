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

_SUDOERS_FILE="/etc/sudoers.d/k3d-manager"

_SUDOERS_CONTENT='# k3d-manager passwordless host-ops rules
# Install:   make sudoers
# Uninstall: bin/install-sudoers.sh --uninstall
# Validate:  visudo -c -f /etc/sudoers.d/k3d-manager

# 60-minute credential cache — prewarm at session start covers a full make up/down run
Defaults:%admin  timestamp_timeout=60

# macOS System Keychain — trust Vault PKI CA certificate
%admin  ALL=(root) NOPASSWD: /usr/bin/security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain *

# macOS launchd — system-scope daemon lifecycle for k3d-manager plists only
%admin  ALL=(root) NOPASSWD: /bin/launchctl bootstrap system /Library/LaunchDaemons/com.k3d-manager.*.plist
%admin  ALL=(root) NOPASSWD: /bin/launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.*.plist

# macOS LaunchDaemons — install and remove k3d-manager plists only
%admin  ALL=(root) NOPASSWD: /usr/bin/install -m 644 * /Library/LaunchDaemons/com.k3d-manager.*.plist
%admin  ALL=(root) NOPASSWD: /bin/rm -f /Library/LaunchDaemons/com.k3d-manager.*.plist *

# Binary install to /usr/local/bin (k3s, kubectl, istioctl, vcluster, etc.)
%admin  ALL=(root) NOPASSWD: /usr/bin/install -m [0-9][0-9][0-9] * /usr/local/bin/*
%admin  ALL=(root) NOPASSWD: /bin/cp * /usr/local/bin/*
%admin  ALL=(root) NOPASSWD: /bin/chmod [0-9][0-9][0-9] /usr/local/bin/*

# k3s lifecycle (local k3s node)
%admin  ALL=(root) NOPASSWD: /usr/local/bin/k3s *
%admin  ALL=(root) NOPASSWD: /usr/local/bin/k3s-uninstall.sh
%admin  ALL=(root) NOPASSWD: /usr/local/bin/k3s-killall.sh

# systemd service management (Linux / Ubuntu EC2 — harmless on macOS where paths do not exist)
%admin  ALL=(root) NOPASSWD: /usr/bin/systemctl *

# Package managers (Linux only — paths do not resolve on macOS)
%admin  ALL=(root) NOPASSWD: /usr/bin/apt-get *
%admin  ALL=(root) NOPASSWD: /usr/bin/dnf *
%admin  ALL=(root) NOPASSWD: /usr/bin/yum *
%admin  ALL=(root) NOPASSWD: /usr/bin/microdnf *
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
    _run_command --interactive-sudo -- install -m 0440 "$_tmpfile" "$_SUDOERS_FILE"
    rm -f "$_tmpfile"
    echo "[install-sudoers] Installed $_SUDOERS_FILE"
    echo "[install-sudoers] Verify: admin rule listing should show launchctl, security, and k3d-manager"
    ;;
esac
