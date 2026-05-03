#!/usr/bin/env bash
# scripts/lib/cdp.sh — Chrome CDP primitives
#
# Public functions:
#   _browser_launch          — ensure Chrome is running with --remote-debugging-port=9222
#   _cdp_ensure_acg_session  — verify Pluralsight session is active in CDP browser

# Ensure _antigravity_browser_ready is available (provided by lib-foundation/system.sh)
if ! declare -f _antigravity_browser_ready >/dev/null 2>&1; then
  _CDP_FOUNDATION="$(cd "$(dirname "${BASH_SOURCE[0]}")/foundation/scripts/lib" && pwd)"
  # shellcheck source=/dev/null
  [[ -f "${_CDP_FOUNDATION}/system.sh" ]] && source "${_CDP_FOUNDATION}/system.sh"
fi

_CDP_CHROME_CDP_LABEL="${CDP_CHROME_CDP_LABEL:-com.k3d-manager.chrome-cdp}"
_CDP_CHROME_CDP_PLIST="${CDP_CHROME_CDP_PLIST:-${HOME}/Library/LaunchAgents/${_CDP_CHROME_CDP_LABEL}.plist}"

function _cdp_profile_in_use() {
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/profile}"
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

  if [[ -f "${_CDP_CHROME_CDP_PLIST}" ]] && launchctl list "${_CDP_CHROME_CDP_LABEL}" >/dev/null 2>&1; then
    _info "[acg] Stopping Chrome CDP agent before taking over the browser profile..."
    launchctl unload "${_CDP_CHROME_CDP_PLIST}" 2>/dev/null || true
    local _wait_for_exit=0
    while _cdp_profile_in_use && [[ ${_wait_for_exit} -lt 5 ]]; do
      sleep 1
      _wait_for_exit=$((_wait_for_exit + 1))
    done
  fi
}

function _cdp_remove_stale_singleton_lock() {
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/profile}"
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

function _browser_launch() {
  if ! _command_exist curl; then
    _err "curl is required for Gemini browser probe — install curl and retry"
  fi
  if _run_command --soft -- curl -sf http://localhost:9222/json >/dev/null 2>&1; then
    return 0
  fi
  _cdp_stop_chrome_cdp_agent
  _cdp_remove_stale_singleton_lock
  _info "Chrome not running — launching with --remote-debugging-port=9222..."
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/profile}"
  if [[ "$(uname)" == "Darwin" ]]; then
    local _chrome_app_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if [[ -x "${_chrome_app_bin}" ]]; then
      local _chrome_cdp_log="${HOME}/.local/share/k3d-manager/chrome-cdp.log"
      mkdir -p "$(dirname "${_chrome_cdp_log}")"
      "${_chrome_app_bin}" \
        --remote-debugging-port=9222 \
        --password-store=basic \
        --user-data-dir="${_cdp_profile_dir}" \
        --no-first-run \
        --no-default-browser-check \
        >>"${_chrome_cdp_log}" 2>&1 &
    else
      open -a "Google Chrome" --args \
        --remote-debugging-port=9222 \
        --password-store=basic \
        --user-data-dir="${_cdp_profile_dir}"
    fi
  else
    local _chrome_bin
    _chrome_bin=$(command -v google-chrome 2>/dev/null || command -v google-chrome-stable 2>/dev/null || command -v chromium-browser 2>/dev/null || command -v chromium 2>/dev/null || true)
    if [[ -z "${_chrome_bin}" ]]; then
      _err "[gemini] Chrome/Chromium not found — install google-chrome, google-chrome-stable, chromium-browser, or chromium"
    fi
    local _extra_flags=()
    if [[ $EUID -eq 0 || "${ANTIGRAVITY_CHROME_NO_SANDBOX:-0}" == "1" ]]; then
      _extra_flags+=(--no-sandbox)
    fi
    "${_chrome_bin}" \
      --headless=new \
      "${_extra_flags[@]}" \
      --disable-dev-shm-usage \
      --remote-debugging-port=9222 \
      --password-store=basic \
      --user-data-dir="${_cdp_profile_dir}" &
  fi
  _antigravity_browser_ready 30
}

function _cdp_ensure_acg_session() {
  if [[ "${K3DM_ACG_SKIP_SESSION_CHECK:-0}" == "1" ]]; then
    _info "K3DM_ACG_SKIP_SESSION_CHECK=1 — skipping ACG/Pluralsight session check"
    return 0
  fi
  _info "Checking Pluralsight (ACG) session in Gemini browser..."

  local gemini_prompt
  gemini_prompt="You are a browser automation agent. Use Playwright (Node.js) to do the following:

1. Connect to the running Gemini browser via CDP: const browser = await chromium.connectOverCDP('http://localhost:9222');
2. Use the first browser context and page (do NOT launch a new browser).
3. Navigate to https://app.pluralsight.com/hands-on/playground/cloud-sandboxes and wait for the page to load.
4. Check if the user is logged in by looking for user avatar, account menu, or sandbox list elements (e.g. [data-testid='user-menu'], [aria-label='User menu'], or a heading containing 'Cloud Sandboxes').
5. If logged in: print ACG_SESSION_OK and exit with code 0.
6. If NOT logged in:
   a. Navigate to https://app.pluralsight.com/id/signin
   b. Print: ACTION REQUIRED: Please log into Pluralsight in the Gemini browser window, then press Enter to continue.
   c. Wait for the page URL to no longer contain '/signin' — poll every 5 seconds, timeout after 300 seconds.
   d. Once URL is no longer '/signin', print ACG_SESSION_OK and exit with code 0.
   e. If 300 seconds pass without login, print ERROR: Pluralsight login timeout and exit with code 1.

Write the Playwright script to ${HOME}/.gemini/tmp/k3d-manager/ag_acg_session.js, execute with node, print the result.
Exit code 1 if session cannot be confirmed."

  _gemini_prompt "$gemini_prompt" --yolo
}
