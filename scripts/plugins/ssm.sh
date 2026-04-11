#!/usr/bin/env bash
# shellcheck shell=bash
# scripts/plugins/ssm.sh — AWS SSM helpers for k3s-aws provider
#
# Public functions:
#   ssm_wait    <instance-id>                    — poll until SSM Online
#   ssm_exec    <instance-id> <command>          — run shell command via send-command
#   ssm_tunnel  <instance-id> <remote> <local>   — background port-forwarding session
#
# Private:
#   _ensure_session_manager_plugin               — auto-install session-manager-plugin
#   _ssm_get_instance_id <alias>                 — map ubuntu/ubuntu-1/ubuntu-2 → instance ID

_SSM_TUNNEL_FWD_PID_FILE="${HOME}/.local/share/k3d-manager/ssm-tunnel-fwd.pid"

function _ensure_session_manager_plugin() {
  if command -v session-manager-plugin >/dev/null 2>&1; then
    return 0
  fi
  _info "[ssm] session-manager-plugin not found — installing..."
  if _is_mac && _command_exist brew; then
    _run_command --soft -- brew install --cask session-manager-plugin
    if command -v session-manager-plugin >/dev/null 2>&1; then
      return 0
    fi
  fi
  _err "[ssm] session-manager-plugin not found — install manually: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
}

function _ssm_get_instance_id() {
  local node_alias="$1"
  local tag_value
  case "${node_alias}" in
    ubuntu)   tag_value="k3d-manager-ubuntu" ;;
    ubuntu-1) tag_value="k3d-manager-ubuntu-1" ;;
    ubuntu-2) tag_value="k3d-manager-ubuntu-2" ;;
    *)
      _err "[ssm] Unknown node alias: ${node_alias}"
      return 1
      ;;
  esac
  aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${tag_value}" \
               "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text
}

function ssm_wait() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: ssm_wait <instance-id>"
    echo "Poll until the instance appears Online in SSM Fleet Manager (max 300s)."
    return 0
  fi
  local instance_id="$1"
  local attempts=0 status
  _info "[ssm] Waiting for ${instance_id} to appear Online in SSM..."
  while true; do
    status=$(aws ssm describe-instance-information \
      --filters "Key=InstanceIds,Values=${instance_id}" \
      --query "InstanceInformationList[0].PingStatus" \
      --output text 2>/dev/null || echo "Unknown")
    [[ "${status}" == "Online" ]] && break
    (( attempts++ ))
    if (( attempts >= 60 )); then
      _err "[ssm] Instance ${instance_id} did not become Online after 300s"
      return 1
    fi
    sleep 5
  done
  _info "[ssm] Instance ${instance_id} is Online"
}

function ssm_exec() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: ssm_exec <instance-id> <command>"
    echo "Run a shell command on an EC2 instance via SSM send-command (AWS-RunShellScript)."
    echo "Polls get-command-invocation until Success/Failed, then prints stdout."
    return 0
  fi
  local instance_id="$1"
  shift
  local command="$*"

  if ! _command_exist jq; then
    _err "[ssm] jq is required for ssm_exec"
    return 1
  fi

  local params command_id
  params=$(jq -cn --arg cmd "${command}" '{"commands": [$cmd]}')
  command_id=$(aws ssm send-command \
    --instance-ids "${instance_id}" \
    --document-name "AWS-RunShellScript" \
    --parameters "${params}" \
    --query "Command.CommandId" \
    --output text) || return 1

  local attempts=0 status
  while true; do
    status=$(aws ssm get-command-invocation \
      --command-id "${command_id}" \
      --instance-id "${instance_id}" \
      --query "Status" \
      --output text 2>/dev/null || echo "InProgress")
    case "${status}" in
      Success) break ;;
      Failed|Cancelled|TimedOut)
        local stderr_out
        stderr_out=$(aws ssm get-command-invocation \
          --command-id "${command_id}" \
          --instance-id "${instance_id}" \
          --query "StandardErrorContent" \
          --output text 2>/dev/null || true)
        _err "[ssm] Command failed (${status}): ${stderr_out}"
        return 1
        ;;
    esac
    (( attempts++ ))
    if (( attempts >= 60 )); then
      _err "[ssm] Command ${command_id} did not complete after 120s"
      return 1
    fi
    sleep 2
  done

  aws ssm get-command-invocation \
    --command-id "${command_id}" \
    --instance-id "${instance_id}" \
    --query "StandardOutputContent" \
    --output text
}

function ssm_tunnel() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: ssm_tunnel <instance-id> <remote-port> <local-port>

Start a background SSM port-forwarding session (AWS-StartPortForwardingSession).
PID stored in ~/.local/share/k3d-manager/ssm-tunnel-fwd.pid.

Note: SSM only supports local→remote forwarding. Vault reverse bridge
(EC2→Mac) requires the SSH tunnel and is not available in SSM mode.
HELP
    return 0
  fi
  local instance_id="$1"
  local remote_port="$2"
  local local_port="$3"

  _ensure_session_manager_plugin || return 1

  if [[ -f "${_SSM_TUNNEL_FWD_PID_FILE}" ]]; then
    local existing_pid
    existing_pid=$(cat "${_SSM_TUNNEL_FWD_PID_FILE}")
    if kill -0 "${existing_pid}" 2>/dev/null; then
      _info "[ssm] SSM tunnel already running (PID ${existing_pid}) — skipping"
      return 0
    fi
    rm -f "${_SSM_TUNNEL_FWD_PID_FILE}"
  fi

  aws ssm start-session \
    --target "${instance_id}" \
    --document-name AWS-StartPortForwardingSession \
    --parameters "{\"portNumber\":[\"${remote_port}\"],\"localPortNumber\":[\"${local_port}\"]}" &
  local _tunnel_pid=$!
  mkdir -p "$(dirname "${_SSM_TUNNEL_FWD_PID_FILE}")"
  printf '%s\n' "${_tunnel_pid}" > "${_SSM_TUNNEL_FWD_PID_FILE}"
  _info "[ssm] SSM tunnel started (PID ${_tunnel_pid}): localhost:${local_port} → ${instance_id}:${remote_port}"
}
