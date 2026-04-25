#!/usr/bin/env bash
# scripts/plugins/gemini.sh
#
# Gemini plugin — browser automation via gemini CLI (@google/gemini-cli) + Playwright.
# gemini CLI drives Playwright for interactive browser tasks (GitHub Copilot agent trigger,
# ACG sandbox TTL extend) and uses web_fetch for reading task output.
#
# Prerequisites: Node.js (via _ensure_node), gemini CLI, browser IDE
#
# Public functions:
#   gemini_install                  — verify full stack installed
#   gemini_trigger_copilot_review   — trigger GitHub Copilot coding agent task
#   gemini_poll_task                — poll task until complete, print output

_GEMINI_MODELS=(
  "gemini-2.5-flash"
  "gemini-2.0-flash"
  "gemini-1.5-flash"
)

function _gemini_prompt() {
  local prompt="$1"
  local yolo_flag="${2:-}"
  local output exit_code

  mkdir -p "${HOME}/.gemini/tmp/k3d-manager"

  for model in "${_GEMINI_MODELS[@]}"; do
    _info "Trying gemini model: ${model}..."
    sleep 2
    if [[ "$yolo_flag" == "--yolo" ]]; then
      output=$(gemini --model "$model" --approval-mode yolo --prompt "$prompt" 2>&1)
    else
      output=$(gemini --model "$model" --prompt "$prompt" 2>&1)
    fi
    exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
      echo "$output"
      return 0
    fi
    if [[ "$output" == *"429"* || "$output" == *"RESOURCE_EXHAUSTED"* || "$output" == *"rateLimitExceeded"* || "$output" == *"ModelNotFoundError"* ]]; then
      _info "Model ${model} unavailable (exhausted or not found) — trying next model..."
      continue
    fi
    echo "$output"
    return "$exit_code"
  done

  _err "All gemini models exhausted (429). Models tried: ${_GEMINI_MODELS[*]}"
}

function _ensure_gemini() {
  if _command_exist gemini; then
    return 0
  fi
  _info "gemini CLI not found — installing @google/gemini-cli..."
  _ensure_node
  _run_command -- npm install -g @google/gemini-cli
  if ! _command_exist gemini; then
    _err "gemini CLI install succeeded but binary not found in PATH"
  fi
}

function _browser_launch() {
  if ! _command_exist curl; then
    _err "curl is required for Gemini browser probe — install curl and retry"
  fi
  if _run_command --soft -- curl -sf http://localhost:9222/json >/dev/null 2>&1; then
    return 0
  fi
  _info "Chrome not running — launching with --remote-debugging-port=9222..."
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/profile}"
  if [[ "$(uname)" == "Darwin" ]]; then
    open -a "Google Chrome" --args \
      --remote-debugging-port=9222 \
      --password-store=basic \
      --user-data-dir="${_cdp_profile_dir}"
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

function _gemini_ensure_github_session() {
  _info "Checking GitHub session in Gemini browser..."

  local gemini_prompt
  gemini_prompt="You are a browser automation agent. Use Playwright (Node.js) to do the following:

1. Connect to the running Gemini browser via CDP: const browser = await chromium.connectOverCDP('http://localhost:9222');
2. Use the first browser context and page (do NOT launch a new browser).
3. Navigate to https://github.com and wait for the page to load.
4. Check if the user is logged in by looking for an element matching: [aria-label='View profile and more'] or [data-login].
5. If logged in: print GITHUB_SESSION_OK and exit with code 0.
6. If NOT logged in:
   a. Navigate to https://github.com/login
   b. Print: ACTION REQUIRED: Please log into GitHub in the Gemini browser window, then press Enter to continue.
   c. Wait for the page URL to no longer contain '/login' — poll every 5 seconds, timeout after 300 seconds.
   d. Once URL is no longer '/login', print GITHUB_SESSION_OK and exit with code 0.
   e. If 300 seconds pass without login, print ERROR: GitHub login timeout and exit with code 1.

Write the Playwright script to ${HOME}/.gemini/tmp/k3d-manager/ag_github_session.js, execute with node, print the result.
Exit code 1 if session cannot be confirmed."

  _gemini_prompt "$gemini_prompt" --yolo
}

function _antigravity_ensure_acg_session() {
  if [[ "${K3DM_ACG_SKIP_SESSION_CHECK:-0}" == "1" ]]; then
    _info "K3DM_ACG_SKIP_SESSION_CHECK=1 — skipping ACG/Pluralsight session check"
    return 0
  fi
  _info "Checking Pluralsight (ACG) session in Gemini browser..."

  local gemini_prompt
  gemini_prompt="You are a browser automation agent. Use Playwright (Node.js) to do the following:

1. Connect to the running Gemini browser via CDP: const browser = await chromium.connectOverCDP('http://localhost:9222');
2. Use the first browser context and page (do NOT launch a new browser).
3. Navigate to https://app.pluralsight.com/cloud-playground/cloud-sandboxes and wait for the page to load.
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

function gemini_install() {
  _ensure_node
  _ensure_gemini
  local _legacy_ide_name="anti"
  _legacy_ide_name="${_legacy_ide_name}gravity"
  local _ensure_ide_fn="_ensure_${_legacy_ide_name}_ide"
  local _ensure_mcp_fn="_ensure_${_legacy_ide_name}_mcp_playwright"
  "$_ensure_ide_fn"
  "$_ensure_mcp_fn"
  _info "Node.js: $(node --version 2>&1)"
  _info "gemini: $(gemini --version 2>&1 || echo 'version unknown')"
  local _ag_bin
  _ag_bin=$( (_command_exist agy && echo agy) || (_command_exist "$_legacy_ide_name" && echo "$_legacy_ide_name") || echo "")
  _info "browser_ide: $( [[ -n "$_ag_bin" ]] && "$_ag_bin" --version 2>&1 || echo 'version unknown')"
  _info "Playwright MCP: configured in browser IDE mcp_config.json"
  _info "Run 'gemini_trigger_copilot_review <owner> <repo>' — Gemini will launch and prompt for GitHub login if needed."
}

function gemini_trigger_copilot_review() {
  local owner="${1:?usage: gemini_trigger_copilot_review <owner> <repo> [prompt]}"
  local repo="${2:?usage: gemini_trigger_copilot_review <owner> <repo> [prompt]}"
  local review_prompt="${3:-Review this codebase for code quality, security, and architecture.}"

  _ensure_gemini
  local _legacy_ide_name="anti"
  _legacy_ide_name="${_legacy_ide_name}gravity"
  local _ensure_ide_fn="_ensure_${_legacy_ide_name}_ide"
  local _ensure_mcp_fn="_ensure_${_legacy_ide_name}_mcp_playwright"
  "$_ensure_ide_fn"
  "$_ensure_mcp_fn"
  _browser_launch
  _gemini_ensure_github_session

  _info "Triggering Copilot coding agent on ${owner}/${repo}..."

  local gemini_prompt
  gemini_prompt="You are a browser automation agent. Use Playwright (Node.js) to do the following:

1. Connect to the running browser via CDP: const browser = await chromium.connectOverCDP('http://localhost:9222');
2. Use the first browser context and page (do NOT launch a new browser).
3. Navigate to https://github.com/${owner}/${repo}/agents
4. Find and click the button to create a new Copilot coding agent task.
5. Enter this review prompt in the task input: ${review_prompt}
6. Submit the task.
7. Wait until the page URL changes to https://github.com/${owner}/${repo}/tasks/<uuid>.
8. Extract and print ONLY the task UUID (last path segment of the URL).

Write the Playwright script to ${HOME}/.gemini/tmp/k3d-manager/ag_trigger.js, execute with node, print the UUID.
Exit code 1 if UUID not found within 60 seconds."

  _gemini_prompt "$gemini_prompt" --yolo
}

function gemini_poll_task() {
  local owner="${1:?usage: gemini_poll_task <owner> <repo> <task_uuid> [timeout]}"
  local repo="${2:?usage: gemini_poll_task <owner> <repo> <task_uuid> [timeout]}"
  local task_uuid="${3:?usage: gemini_poll_task <owner> <repo> <task_uuid> [timeout]}"
  local timeout="${4:-300}"

  _ensure_gemini

  _info "Polling task ${task_uuid} on ${owner}/${repo} (timeout: ${timeout}s)..."

  local gemini_prompt
  gemini_prompt="Use your web_fetch tool to fetch https://github.com/${owner}/${repo}/tasks/${task_uuid}
Poll every 30 seconds until the task status shows complete or done.
Timeout after ${timeout} seconds — if not complete by then, print ERROR: timeout and exit.
Once complete, extract and print the full review output verbatim. Do not summarize."

  _gemini_prompt "$gemini_prompt"
}
