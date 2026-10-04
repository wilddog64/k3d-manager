#!/usr/bin/env bash
# scripts/plugins/tunnel.sh
# autossh-backed SSH tunnel plugin for k3d-manager
set -euo pipefail

_TUNNEL_VARS="${SCRIPT_DIR}/etc/tunnel/vars.sh"
if [[ -r "$_TUNNEL_VARS" ]]; then
  # shellcheck disable=SC1090
  source "$_TUNNEL_VARS"
fi

: "${TUNNEL_SSH_HOST:=ubuntu}"
: "${TUNNEL_LOCAL_PORT:=6443}"
: "${TUNNEL_REMOTE_PORT:=6443}"
: "${TUNNEL_BIND_ADDR:=0.0.0.0}"
: "${TUNNEL_VAULT_REMOTE_PORT:=${TUNNEL_VAULT_PORT:-8200}}"
: "${TUNNEL_VAULT_LOCAL_PORT:=18200}"
: "${TUNNEL_LAUNCHD_LABEL:=com.k3d-manager.ssh-tunnel}"
: "${TUNNEL_PLIST_PATH:=${HOME}/Library/LaunchAgents/${TUNNEL_LAUNCHD_LABEL}.plist}"
: "${TUNNEL_VAULT_LAUNCHD_LABEL:=com.k3d-manager.ssh-tunnel-vault}"
: "${TUNNEL_VAULT_PLIST_PATH:=${HOME}/Library/LaunchAgents/${TUNNEL_VAULT_LAUNCHD_LABEL}.plist}"
: "${TUNNEL_VAULT_WRAPPER_PATH:=${HOME}/Library/LaunchAgents/${TUNNEL_VAULT_LAUNCHD_LABEL}.sh}"

_tunnel_is_running() {
  pgrep -f "autossh.*${TUNNEL_SSH_HOST}" >/dev/null 2>&1
}

_tunnel_launchd_loaded() {
  [[ "$(uname)" == "Darwin" ]] || return 1
  launchctl list "${TUNNEL_LAUNCHD_LABEL}" >/dev/null 2>&1
}

_tunnel_vault_is_running() {
  pgrep -f "ssh -N .*-R ${TUNNEL_VAULT_REMOTE_PORT}:127.0.0.1:${TUNNEL_VAULT_LOCAL_PORT}" >/dev/null 2>&1
}

_tunnel_vault_launchd_loaded() {
  [[ "$(uname)" == "Darwin" ]] || return 1
  launchctl list "${TUNNEL_VAULT_LAUNCHD_LABEL}" >/dev/null 2>&1
}

_tunnel_plist_has_reverse() {
  [[ -f "${TUNNEL_PLIST_PATH}" ]] && grep -q '<string>-R</string>' "${TUNNEL_PLIST_PATH}"
}

_tunnel_autossh_path() {
  command -v autossh 2>/dev/null
}

_tunnel_write_plist() {
  local autossh_bin
  autossh_bin="$(_tunnel_autossh_path)"
  mkdir -p "$(dirname "${TUNNEL_PLIST_PATH}")"
  cat > "${TUNNEL_PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${TUNNEL_LAUNCHD_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${autossh_bin}</string>
    <string>-M</string>
    <string>0</string>
    <string>-o</string>
    <string>ServerAliveInterval=30</string>
    <string>-o</string>
    <string>ServerAliveCountMax=3</string>
    <string>-o</string>
    <string>ExitOnForwardFailure=yes</string>
    <string>-L</string>
    <string>${TUNNEL_BIND_ADDR}:${TUNNEL_LOCAL_PORT}:localhost:${TUNNEL_REMOTE_PORT}</string>
    <string>-N</string>
    <string>${TUNNEL_SSH_HOST}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/k3d-manager-tunnel.out</string>
  <key>StandardErrorPath</key>
  <string>/tmp/k3d-manager-tunnel.err</string>
</dict>
</plist>
PLIST
}

_tunnel_write_vault_agent() {
  local ssh_bin
  ssh_bin="$(command -v ssh)"
  mkdir -p "$(dirname "${TUNNEL_VAULT_WRAPPER_PATH}")" "$(dirname "${TUNNEL_VAULT_PLIST_PATH}")"
  cat > "${TUNNEL_VAULT_WRAPPER_PATH}" <<WRAPPER
#!/bin/bash
"${ssh_bin}" -o BatchMode=yes -o ConnectTimeout=10 "${TUNNEL_SSH_HOST}" \
  "sudo fuser -k -n tcp ${TUNNEL_VAULT_REMOTE_PORT} >/dev/null 2>&1 || true" >/dev/null 2>&1 || true # agent-audit: remote-sudo
exec "${ssh_bin}" -N -o BatchMode=yes -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
  -R ${TUNNEL_VAULT_REMOTE_PORT}:127.0.0.1:${TUNNEL_VAULT_LOCAL_PORT} "${TUNNEL_SSH_HOST}"
WRAPPER
  chmod 0755 "${TUNNEL_VAULT_WRAPPER_PATH}"
  cat > "${TUNNEL_VAULT_PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${TUNNEL_VAULT_LAUNCHD_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${TUNNEL_VAULT_WRAPPER_PATH}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>/tmp/k3d-manager-tunnel-vault.out</string>
  <key>StandardErrorPath</key>
  <string>/tmp/k3d-manager-tunnel-vault.err</string>
</dict>
</plist>
PLIST
}

function tunnel_start() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<EOF
Usage: tunnel_start

Start the SSH tunnel:
  Forward: ${TUNNEL_BIND_ADDR}:${TUNNEL_LOCAL_PORT} -> ${TUNNEL_SSH_HOST}:${TUNNEL_REMOTE_PORT} (k3s API)
  Reverse: ${TUNNEL_SSH_HOST}:${TUNNEL_VAULT_REMOTE_PORT} -> 127.0.0.1:${TUNNEL_VAULT_LOCAL_PORT} (Vault)
Installs a launchd plist for boot persistence (macOS only).

Config (override via env or scripts/etc/tunnel/vars.sh):
  TUNNEL_SSH_HOST    SSH host alias    (default: ubuntu)
  TUNNEL_LOCAL_PORT  Local port        (default: 6443)
  TUNNEL_REMOTE_PORT Remote port       (default: 6443)
  TUNNEL_BIND_ADDR   Bind address      (default: 0.0.0.0)
  TUNNEL_VAULT_REMOTE_PORT  Remote Vault reverse port (default: 8200)
  TUNNEL_VAULT_LOCAL_PORT   Local Vault port-forward port (default: 18200)
EOF
    return 0
  fi

  if [[ -z "$(_tunnel_autossh_path)" ]]; then
    echo "[tunnel] autossh not found — install with: brew install autossh" >&2
    return 1
  fi

  if _tunnel_is_running && ! _tunnel_plist_has_reverse && _tunnel_vault_launchd_loaded; then
    echo "[tunnel] already running"
    return 0
  fi

  _tunnel_write_plist
  _tunnel_write_vault_agent
  if [[ "$(uname)" == "Darwin" ]]; then
    launchctl unload -w "${TUNNEL_PLIST_PATH}" 2>/dev/null || true
    launchctl load -w "${TUNNEL_PLIST_PATH}"
    launchctl unload -w "${TUNNEL_VAULT_PLIST_PATH}" 2>/dev/null || true
    launchctl load -w "${TUNNEL_VAULT_PLIST_PATH}"
  fi
  echo "[tunnel] started — ${TUNNEL_BIND_ADDR}:${TUNNEL_LOCAL_PORT} -> ${TUNNEL_SSH_HOST}:${TUNNEL_REMOTE_PORT}"
}

function tunnel_stop() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: tunnel_stop"
    echo "Stop the SSH tunnel and unload the launchd plist."
    return 0
  fi

  if _tunnel_launchd_loaded; then
    if [[ "$(uname)" == "Darwin" ]]; then
      launchctl unload -w "${TUNNEL_PLIST_PATH}"
    fi
  fi

  if _tunnel_is_running; then
    pkill -f "autossh.*${TUNNEL_SSH_HOST}" || true
  fi

  if _tunnel_vault_launchd_loaded; then
    launchctl unload -w "${TUNNEL_VAULT_PLIST_PATH}"
  fi
  if _tunnel_vault_is_running; then
    pkill -f "ssh -N .*-R ${TUNNEL_VAULT_REMOTE_PORT}:127.0.0.1:${TUNNEL_VAULT_LOCAL_PORT}" || true
  fi

  echo "[tunnel] stopped"
}

function tunnel_status() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: tunnel_status"
    echo "Show whether the SSH tunnel is running and the launchd plist is loaded."
    return 0
  fi

  local launchd_state process_state vault_state
  if _tunnel_launchd_loaded; then
    launchd_state="loaded"
  else
    launchd_state="not loaded"
  fi

  if _tunnel_is_running; then
    process_state="running"
  else
    process_state="not running"
  fi

  if _tunnel_vault_is_running; then
    vault_state="running"
  else
    vault_state="not running"
  fi

  echo "[tunnel] launchd: ${launchd_state} | process: ${process_state}"
  echo "[tunnel] forward: ${TUNNEL_BIND_ADDR}:${TUNNEL_LOCAL_PORT} -> ${TUNNEL_SSH_HOST}:${TUNNEL_REMOTE_PORT} (k3s API)"
  echo "[tunnel] reverse: ${TUNNEL_SSH_HOST}:${TUNNEL_VAULT_REMOTE_PORT} -> 127.0.0.1:${TUNNEL_VAULT_LOCAL_PORT} (Vault, agent ${TUNNEL_VAULT_LAUNCHD_LABEL}: ${vault_state})"

  if [[ "$process_state" == "not running" ]]; then
    return 1
  fi
  return 0
}
