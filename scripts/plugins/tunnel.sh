#!/usr/bin/env bash
# scripts/plugins/tunnel.sh
# autossh-backed SSH tunnel plugin for k3d-manager
set -euo pipefail

_TUNNEL_VARS="${SCRIPT_DIR}/etc/tunnel/vars.sh"
_TUNNEL_SSH_HOST_EXPLICIT="${TUNNEL_SSH_HOST+x}"
if [[ -r "$_TUNNEL_VARS" ]]; then
  # shellcheck disable=SC1090
  source "$_TUNNEL_VARS"
fi

: "${TUNNEL_SSH_HOST:=ubuntu}"
: "${TUNNEL_REMOTE_PORT:=6443}"
: "${TUNNEL_BIND_ADDR:=0.0.0.0}"
: "${TUNNEL_VAULT_REMOTE_PORT:=${TUNNEL_VAULT_PORT:-8200}}"
: "${TUNNEL_VAULT_LOCAL_PORT:=18200}"

_tunnel_resolve_scope() {
  local prefix="com.k3d-manager" log_base="/tmp/k3d-manager-tunnel" port="6443"
  if [[ "${TUNNEL_SCOPE:-}" == "sandbox" ]]; then
    prefix="com.k3d-manager.sandbox"
    log_base="/tmp/k3d-manager-sandbox-tunnel"
    port="${TUNNEL_SANDBOX_LOCAL_PORT:-16443}"
  fi
  _TUNNEL_LAUNCHD_LABEL="${TUNNEL_LAUNCHD_LABEL:-${prefix}.ssh-tunnel}"
  _TUNNEL_PLIST_PATH="${TUNNEL_PLIST_PATH:-${HOME}/Library/LaunchAgents/${_TUNNEL_LAUNCHD_LABEL}.plist}"
  _TUNNEL_VAULT_LAUNCHD_LABEL="${TUNNEL_VAULT_LAUNCHD_LABEL:-${prefix}.ssh-tunnel-vault}"
  _TUNNEL_VAULT_PLIST_PATH="${TUNNEL_VAULT_PLIST_PATH:-${HOME}/Library/LaunchAgents/${_TUNNEL_VAULT_LAUNCHD_LABEL}.plist}"
  _TUNNEL_VAULT_WRAPPER_PATH="${TUNNEL_VAULT_WRAPPER_PATH:-${HOME}/Library/LaunchAgents/${_TUNNEL_VAULT_LAUNCHD_LABEL}.sh}"
  _TUNNEL_FORWARD_WRAPPER_PATH="${TUNNEL_FORWARD_WRAPPER_PATH:-${HOME}/Library/LaunchAgents/${_TUNNEL_LAUNCHD_LABEL}.sh}"
  _TUNNEL_LOCAL_PORT="${TUNNEL_LOCAL_PORT:-${port}}"
  _TUNNEL_LOG_BASE="${log_base}"
}

_tunnel_regex_escape() {
  printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'
}

_tunnel_forward_pattern() {
  printf 'autossh .* -N %s$' "$(_tunnel_regex_escape "${TUNNEL_SSH_HOST}")"
}

_tunnel_vault_pattern() {
  printf 'ssh -N .*-R %s:127\\.0\\.0\\.1:%s %s$' "${TUNNEL_VAULT_REMOTE_PORT}" "${TUNNEL_VAULT_LOCAL_PORT}" \
    "$(_tunnel_regex_escape "${TUNNEL_SSH_HOST}")"
}

_tunnel_is_running() {
  pgrep -f "$(_tunnel_forward_pattern)" >/dev/null 2>&1
}

_tunnel_launchd_loaded() {
  _tunnel_resolve_scope
  [[ "$(uname)" == "Darwin" ]] || return 1
  launchctl list "${_TUNNEL_LAUNCHD_LABEL}" >/dev/null 2>&1
}

_tunnel_vault_is_running() {
  pgrep -f "$(_tunnel_vault_pattern)" >/dev/null 2>&1
}

_tunnel_vault_launchd_loaded() {
  _tunnel_resolve_scope
  [[ "$(uname)" == "Darwin" ]] || return 1
  launchctl list "${_TUNNEL_VAULT_LAUNCHD_LABEL}" >/dev/null 2>&1
}

_tunnel_plist_has_reverse() {
  _tunnel_resolve_scope
  [[ -f "${_TUNNEL_PLIST_PATH}" ]] && grep -q '<string>-R</string>' "${_TUNNEL_PLIST_PATH}"
}

_tunnel_remove_agent_files() {
  _tunnel_resolve_scope
  rm -f -- "${_TUNNEL_PLIST_PATH}" "${_TUNNEL_VAULT_PLIST_PATH}" "${_TUNNEL_VAULT_WRAPPER_PATH}" "${_TUNNEL_FORWARD_WRAPPER_PATH}"
}

_tunnel_rotate_logs() {
  _tunnel_resolve_scope
  local log
  for log in "${_TUNNEL_LOG_BASE}.err" "${_TUNNEL_LOG_BASE}-vault.err"; do
    if [[ -f "$log" && "$(wc -c < "$log")" -gt 5242880 ]]; then
      mv -f -- "$log" "${log}.1"
    fi
  done
}

_tunnel_write_forward_agent() {
  _tunnel_resolve_scope
  local autossh_bin
  autossh_bin="$(_tunnel_autossh_path)"
  mkdir -p "$(dirname "${_TUNNEL_FORWARD_WRAPPER_PATH}")"
  cat > "${_TUNNEL_FORWARD_WRAPPER_PATH}" <<WRAPPER
#!/bin/bash
exec 2> >(while IFS= read -r line; do printf '[%s] %s\n' "\$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "\$line" >&2; done)
exec "${autossh_bin}" -M 0 -o ConnectTimeout=10 -o ServerAliveInterval=30 \\
  -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes \\
  -L ${TUNNEL_BIND_ADDR}:${_TUNNEL_LOCAL_PORT}:localhost:${TUNNEL_REMOTE_PORT} -N "${TUNNEL_SSH_HOST}"
WRAPPER
  chmod 0755 "${_TUNNEL_FORWARD_WRAPPER_PATH}"
}

_tunnel_autossh_path() {
  command -v autossh 2>/dev/null
}

_tunnel_write_plist() {
  _tunnel_resolve_scope
  mkdir -p "$(dirname "${_TUNNEL_PLIST_PATH}")"
  _tunnel_write_forward_agent
  cat > "${_TUNNEL_PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${_TUNNEL_LAUNCHD_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${_TUNNEL_FORWARD_WRAPPER_PATH}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${_TUNNEL_LOG_BASE}.out</string>
  <key>StandardErrorPath</key>
  <string>${_TUNNEL_LOG_BASE}.err</string>
</dict>
</plist>
PLIST
}

_tunnel_write_vault_agent() {
  _tunnel_resolve_scope
  local ssh_bin
  ssh_bin="$(command -v ssh)"
  mkdir -p "$(dirname "${_TUNNEL_VAULT_WRAPPER_PATH}")" "$(dirname "${_TUNNEL_VAULT_PLIST_PATH}")"
  cat > "${_TUNNEL_VAULT_WRAPPER_PATH}" <<WRAPPER
#!/bin/bash
exec 2> >(while IFS= read -r line; do printf '[%s] %s\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "\$line" >&2; done)
"${ssh_bin}" -o BatchMode=yes -o ConnectTimeout=10 "${TUNNEL_SSH_HOST}" \
  "sudo fuser -k -n tcp ${TUNNEL_VAULT_REMOTE_PORT} >/dev/null 2>&1 || true" >/dev/null 2>&1 || true # agent-audit: remote-sudo
exec "${ssh_bin}" -N -o BatchMode=yes -o ExitOnForwardFailure=yes \
  -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
  -R ${TUNNEL_VAULT_REMOTE_PORT}:127.0.0.1:${TUNNEL_VAULT_LOCAL_PORT} "${TUNNEL_SSH_HOST}"
WRAPPER
  chmod 0755 "${_TUNNEL_VAULT_WRAPPER_PATH}"
  cat > "${_TUNNEL_VAULT_PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${_TUNNEL_VAULT_LAUNCHD_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${_TUNNEL_VAULT_WRAPPER_PATH}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>${_TUNNEL_LOG_BASE}-vault.out</string>
  <key>StandardErrorPath</key>
  <string>${_TUNNEL_LOG_BASE}-vault.err</string>
</dict>
</plist>
PLIST
}

function tunnel_start() {
  _tunnel_resolve_scope
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<EOF
Usage: tunnel_start

Start the SSH tunnel:
  Forward: ${TUNNEL_BIND_ADDR}:${_TUNNEL_LOCAL_PORT} -> ${TUNNEL_SSH_HOST}:${TUNNEL_REMOTE_PORT} (k3s API)
  Reverse: ${TUNNEL_SSH_HOST}:${TUNNEL_VAULT_REMOTE_PORT} -> 127.0.0.1:${TUNNEL_VAULT_LOCAL_PORT} (Vault)
Installs a launchd plist for boot persistence (macOS only).

Config (override via env or scripts/etc/tunnel/vars.sh):
  TUNNEL_SSH_HOST    SSH host alias    (default: ubuntu)
  TUNNEL_LOCAL_PORT  Local port        (default: 6443; 16443 with TUNNEL_SCOPE=sandbox)
  TUNNEL_SCOPE       sandbox → com.k3d-manager.sandbox.* agents (default: unscoped)
  TUNNEL_REMOTE_PORT Remote port       (default: 6443)
  TUNNEL_BIND_ADDR   Bind address      (default: 0.0.0.0)
  TUNNEL_VAULT_REMOTE_PORT  Remote Vault reverse port (default: 8200)
  TUNNEL_VAULT_LOCAL_PORT   Local Vault port-forward port (default: 18200)
EOF
    return 0
  fi

  if [[ "${TUNNEL_SCOPE:-}" != "sandbox" ]]; then
    if [[ -z "${_TUNNEL_SSH_HOST_EXPLICIT}" && "${TUNNEL_SSH_HOST}" == "ubuntu" ]]; then
      echo "[tunnel] TUNNEL_SSH_HOST must be set explicitly for unscoped agents; use make refresh CLUSTER_PROVIDER=k3s-hostinger to restart the Hostinger tunnels" >&2
      return 1
    fi
    local existing_host
    for existing_host in "${_TUNNEL_FORWARD_WRAPPER_PATH}" "${_TUNNEL_VAULT_WRAPPER_PATH}"; do
      if [[ -f "${existing_host}" ]]; then
        existing_host="$(sed -nE 's/.* -N "([^"]+)".*/\1/p' "${existing_host}" | tail -n 1)"
        if [[ -n "${existing_host}" && "${existing_host}" != "${TUNNEL_SSH_HOST}" && "${TUNNEL_FORCE_HOST:-}" != "1" ]]; then
          echo "[tunnel] refusing to repoint unscoped agents from ${existing_host} to ${TUNNEL_SSH_HOST}; set TUNNEL_FORCE_HOST=1 to override" >&2
          return 1
        fi
      fi
    done
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
  _tunnel_rotate_logs
  if [[ "$(uname)" == "Darwin" ]]; then
    launchctl unload -w "${_TUNNEL_PLIST_PATH}" 2>/dev/null || true
    launchctl load -w "${_TUNNEL_PLIST_PATH}"
    launchctl unload -w "${_TUNNEL_VAULT_PLIST_PATH}" 2>/dev/null || true
    launchctl load -w "${_TUNNEL_VAULT_PLIST_PATH}"
  fi
  echo "[tunnel] started — ${TUNNEL_BIND_ADDR}:${_TUNNEL_LOCAL_PORT} -> ${TUNNEL_SSH_HOST}:${TUNNEL_REMOTE_PORT}"
}

function tunnel_stop() {
  _tunnel_resolve_scope
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: tunnel_stop"
    echo "Stop the SSH tunnel and unload the launchd plist."
    return 0
  fi

  if _tunnel_launchd_loaded; then
    if [[ "$(uname)" == "Darwin" ]]; then
      launchctl unload -w "${_TUNNEL_PLIST_PATH}"
    fi
  fi

  if _tunnel_is_running; then
    pkill -f "$(_tunnel_forward_pattern)" || true
  fi

  if _tunnel_vault_launchd_loaded; then
    launchctl unload -w "${_TUNNEL_VAULT_PLIST_PATH}"
  fi
  if _tunnel_vault_is_running; then
    pkill -f "$(_tunnel_vault_pattern)" || true
  fi

  echo "[tunnel] stopped"
}

function tunnel_status() {
  _tunnel_resolve_scope
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
  echo "[tunnel] forward: ${TUNNEL_BIND_ADDR}:${_TUNNEL_LOCAL_PORT} -> ${TUNNEL_SSH_HOST}:${TUNNEL_REMOTE_PORT} (k3s API)"
  echo "[tunnel] reverse: ${TUNNEL_SSH_HOST}:${TUNNEL_VAULT_REMOTE_PORT} -> 127.0.0.1:${TUNNEL_VAULT_LOCAL_PORT} (Vault, agent ${_TUNNEL_VAULT_LAUNCHD_LABEL}: ${vault_state})"

  if [[ "$process_state" == "not running" ]]; then
    return 1
  fi
  return 0
}
