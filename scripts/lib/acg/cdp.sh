#!/usr/bin/env bash
# scripts/lib/cdp.sh — Chrome CDP primitives
#
# Public functions:
#   _browser_launch          — ensure Chrome is running with --remote-debugging-port=9222
#   _cdp_ensure_acg_session  — verify Pluralsight session is active in CDP browser

# Resolve foundation helpers. When a host already loaded foundation (k3d-manager),
# the host copy wins via the declare -f guard. Standalone, pull ../system.sh —
# this module lives at scripts/lib/acg/, so ../ is scripts/lib/.
if ! declare -f _run_command >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/system.sh"
fi

if [[ -z "${_LIB_ACG_ROOT:-}" ]]; then
  _LIB_ACG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

_CDP_CHROME_CDP_LABEL="${CDP_CHROME_CDP_LABEL:-com.k3d-manager.chrome-cdp}"

function _cdp_profile_in_use() {
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/pw-profile}"
  local _profile_arg="--user-data-dir=${_cdp_profile_dir}"

  ps -ax -o command= | awk -v profile="${_profile_arg}" '
    index($0, profile) && $0 ~ /(Google Chrome|chromium|chrome)/ {
      found = 1
    }
    END { exit(found ? 0 : 1) }
  '
}

function _cdp_stop_chrome_cdp_agent() {
  if [[ "$(uname)" != "Darwin" ]]; then
    return 0
  fi

  if launchctl list "${_CDP_CHROME_CDP_LABEL}" >/dev/null 2>&1; then
    _info "[acg] Stopping Chrome CDP agent before taking over the browser profile..."
    launchctl bootout "gui/$(id -u)/${_CDP_CHROME_CDP_LABEL}" || _warn "[acg] launchctl bootout ${_CDP_CHROME_CDP_LABEL} failed — agent may still be running"
    local _wait_for_exit=0
    while _cdp_profile_in_use && [[ ${_wait_for_exit} -lt 5 ]]; do
      sleep 1
      _wait_for_exit=$((_wait_for_exit + 1))
    done
  fi
}

function _cdp_remove_stale_singleton_lock() {
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/pw-profile}"
  local _singleton_lock="${_cdp_profile_dir}/SingletonLock"

  if [[ ! -e "${_singleton_lock}" ]]; then
    return 0
  fi

  if _cdp_profile_in_use; then
    return 0
  fi

  _info "[acg] Removing stale Chrome profile lock: ${_singleton_lock}"
  rm -f "${_singleton_lock}"
}

function _cdp_connectable() {
  local _cdp_host="${PLAYWRIGHT_CDP_HOST:-127.0.0.1}"
  local _cdp_port="${PLAYWRIGHT_CDP_PORT:-9222}"
  if ! _command_exist node; then
    return 1
  fi
  if [[ ! -d "${_LIB_ACG_ROOT}/node_modules/playwright" ]]; then
    return 1
  fi
  # shellcheck disable=SC2016
  CDP_HOST="${_cdp_host}" CDP_PORT="${_cdp_port}" \
  NODE_PATH="${_LIB_ACG_ROOT}/node_modules" \
    node -e 'const{chromium}=require("playwright");chromium.connectOverCDP(`http://${process.env.CDP_HOST}:${process.env.CDP_PORT}`,{timeout:10000}).then(b=>b.close()).then(()=>process.exit(0)).catch(()=>process.exit(1));' >/dev/null 2>&1
}

function _cdp_kill_port_listener() {
  local _cdp_port="${PLAYWRIGHT_CDP_PORT:-9222}"
  if ! _command_exist lsof; then
    _warn "[acg] lsof unavailable — cannot reclaim :${_cdp_port} automatically; quit the browser holding it and re-run"
    return 0
  fi
  local _pids
  _pids="$(lsof -nP -iTCP:"${_cdp_port}" -sTCP:LISTEN -t 2>/dev/null || true)"
  if [[ -z "${_pids}" ]]; then
    return 0
  fi
  _info "[acg] Reclaiming :${_cdp_port} — terminating the CDP browser holding it (pid(s): ${_pids//$'\n'/ })"
  # shellcheck disable=SC2086
  kill ${_pids} 2>/dev/null || true
  local _w=0
  while lsof -nP -iTCP:"${_cdp_port}" -sTCP:LISTEN -t >/dev/null 2>&1 && [[ ${_w} -lt 8 ]]; do
    sleep 1
    _w=$((_w + 1))
  done
  if lsof -nP -iTCP:"${_cdp_port}" -sTCP:LISTEN -t >/dev/null 2>&1; then
    _pids="$(lsof -nP -iTCP:"${_cdp_port}" -sTCP:LISTEN -t 2>/dev/null || true)"
    if [[ -n "${_pids}" ]]; then
      # shellcheck disable=SC2086
      kill -9 ${_pids} 2>/dev/null || true
      sleep 1
    fi
  fi
}

function _browser_launch() {
  local _cdp_host="${PLAYWRIGHT_CDP_HOST:-127.0.0.1}"
  local _cdp_port="${PLAYWRIGHT_CDP_PORT:-9222}"
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/pw-profile}"
  if ! _command_exist curl; then
    _err "curl is required for Antigravity browser probe — install curl and retry"
  fi
  if _run_command --soft -- curl -sf "http://${_cdp_host}:${_cdp_port}/json" >/dev/null 2>&1; then
    if _cdp_connectable; then
      _info "[acg] Reusing existing CDP browser on :${_cdp_port}"
      _cdp_ensure_acg_session
      return $?
    fi
    _info "[acg] A browser is on :${_cdp_port} but Playwright cannot drive it (stale/zombie or version-mismatched) — reclaiming the port and relaunching the managed Chromium."
    _cdp_kill_port_listener
  fi
  _cdp_stop_chrome_cdp_agent
  _cdp_remove_stale_singleton_lock
  _info "Chrome not running — launching with --remote-debugging-port=${_cdp_port}..."
  if [[ "$(uname)" == "Darwin" ]]; then
    local _pw_chrome_bin
    _pw_chrome_bin="$(NODE_PATH="${_LIB_ACG_ROOT}/node_modules" node -e 'process.stdout.write(require("playwright").chromium.executablePath())' 2>/dev/null || true)"
    if [[ -z "${_pw_chrome_bin}" || ! -x "${_pw_chrome_bin}" ]]; then
      _err "[acg] Playwright-managed Chromium not found — run 'npm install' (or 'npx playwright install chromium') in ${_LIB_ACG_ROOT}"
    fi
    local _chrome_cdp_log="${HOME}/.local/share/k3d-manager/chrome-cdp.log"
    mkdir -p "$(dirname "${_chrome_cdp_log}")"
    "${_pw_chrome_bin}" \
      --remote-debugging-port="${_cdp_port}" \
      --password-store=basic \
      --user-data-dir="${_cdp_profile_dir}" \
      --no-first-run \
      --no-default-browser-check \
      >>"${_chrome_cdp_log}" 2>&1 &
  else
    _err "[acg] _browser_launch is macOS-only — $(uname) is not supported"
  fi
  _antigravity_browser_ready 30
  _cdp_ensure_acg_session
}

function _cdp_ensure_acg_session() {
  if [[ "${K3DM_ACG_SKIP_SESSION_CHECK:-0}" == "1" ]]; then
    _info "K3DM_ACG_SKIP_SESSION_CHECK=1 — skipping ACG/Pluralsight session check"
    return 0
  fi
  local _acg_session_check_script="${_LIB_ACG_ROOT}/acg_session_check.js"
  if [[ ! -r "${_acg_session_check_script}" ]]; then
    _err "Missing ACG session check script: ${_acg_session_check_script}"
  fi
  if ! _command_exist node; then
    _err "node is required for the ACG session check — install Node.js and retry"
  fi
  if [[ ! -d "${_LIB_ACG_ROOT}/node_modules/playwright" ]]; then
    _err "playwright module not found under ${_LIB_ACG_ROOT}/node_modules — run 'npm install' in ${_LIB_ACG_ROOT}"
  fi

  _info "Checking Pluralsight (ACG) session in Antigravity browser..."
  local _acg_user _acg_pass
  _acg_user="$(_secret_load_data k3dm-acg-pluralsight username 2>/dev/null || true)"
  _acg_pass="$(_secret_load_data k3dm-acg-pluralsight password 2>/dev/null || true)"
  NODE_PATH="${_LIB_ACG_ROOT}/node_modules" \
  ACG_USERNAME="${_acg_user}" \
  ACG_PASSWORD="${_acg_pass}" \
  K3DM_NONINTERACTIVE="${K3DM_NONINTERACTIVE:-0}" \
    node "${_acg_session_check_script}"
}
