#!/usr/bin/env bash
# scripts/plugins/antigravity.sh
#
# Antigravity plugin — browser automation via gemini CLI (@google/gemini-cli) + Playwright.
# gemini CLI drives Playwright for interactive browser tasks (GitHub Copilot agent trigger,
# ACG sandbox TTL extend) and uses web_fetch for reading task output.
#
# Prerequisites: Node.js (via _ensure_node), gemini CLI, Antigravity IDE
#
# Public functions:
#   antigravity_install                  — verify full stack installed
#   antigravity_trigger_copilot_review   — trigger GitHub Copilot coding agent task
#   antigravity_poll_task                — poll task until complete, print output

_ANTIGRAVITY_GEMINI_MODELS=(
  "gemini-2.5-flash"
  "gemini-2.0-flash"
  "gemini-1.5-flash"
)

function _antigravity_gemini_prompt() {
  local prompt="$1"
  local yolo_flag="${2:-}"
  local output exit_code

  mkdir -p "${HOME}/.gemini/tmp/k3d-manager"

  for model in "${_ANTIGRAVITY_GEMINI_MODELS[@]}"; do
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

  _err "All gemini models exhausted (429). Models tried: ${_ANTIGRAVITY_GEMINI_MODELS[*]}"
}

function _ensure_antigravity() {
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
    _err "curl is required for Antigravity browser probe — install curl and retry"
  fi
  if _run_command --soft -- curl -sf http://localhost:9222/json >/dev/null 2>&1; then
    return 0
  fi
  _info "Chrome not running — launching with --remote-debugging-port=9222..."
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/profile}"
  if [[ "$(uname)" == "Darwin" ]]; then
    local _chrome_app="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if [[ ! -x "${_chrome_app}" ]]; then
      _err "[antigravity] Google Chrome not found at ${_chrome_app}"
    fi
    mkdir -p "${_cdp_profile_dir}"
    "${_chrome_app}" \
      --remote-debugging-port=9222 \
      --password-store=basic \
      --user-data-dir="${_cdp_profile_dir}" \
      --no-first-run \
      --no-default-browser-check \
      >>/tmp/k3d-manager-chrome-cdp.err 2>&1 &
  else
    local _chrome_bin
    _chrome_bin=$(command -v google-chrome 2>/dev/null || command -v google-chrome-stable 2>/dev/null || command -v chromium-browser 2>/dev/null || command -v chromium 2>/dev/null || true)
    if [[ -z "${_chrome_bin}" ]]; then
      _err "[antigravity] Chrome/Chromium not found — install google-chrome, google-chrome-stable, chromium-browser, or chromium"
    fi
    "${_chrome_bin}" \
      --headless=new \
      --no-sandbox \
      --disable-dev-shm-usage \
      --remote-debugging-port=9222 \
      --password-store=basic \
      --user-data-dir="${_cdp_profile_dir}" &
  fi
  _antigravity_browser_ready 30
}

function _antigravity_ensure_github_session() {
  _info "Checking GitHub session in Antigravity browser..."

  local gemini_prompt
  gemini_prompt="You are a browser automation agent. Use Playwright (Node.js) to do the following:

1. Connect to the running Antigravity browser via CDP: const browser = await chromium.connectOverCDP('http://localhost:9222');
2. Use the first browser context and page (do NOT launch a new browser).
3. Navigate to https://github.com and wait for the page to load.
4. Check if the user is logged in by looking for an element matching: [aria-label='View profile and more'] or [data-login].
5. If logged in: print GITHUB_SESSION_OK and exit with code 0.
6. If NOT logged in:
   a. Navigate to https://github.com/login
   b. Print: ACTION REQUIRED: Please log into GitHub in the Antigravity browser window, then press Enter to continue.
   c. Wait for the page URL to no longer contain '/login' — poll every 5 seconds, timeout after 300 seconds.
   d. Once URL is no longer '/login', print GITHUB_SESSION_OK and exit with code 0.
   e. If 300 seconds pass without login, print ERROR: GitHub login timeout and exit with code 1.

Write the Playwright script to ${HOME}/.gemini/tmp/k3d-manager/ag_github_session.js, execute with node, print the result.
Exit code 1 if session cannot be confirmed."

  _antigravity_gemini_prompt "$gemini_prompt" --yolo
}

function _antigravity_ensure_acg_session() {
  if [[ "${K3DM_ACG_SKIP_SESSION_CHECK:-0}" == "1" ]]; then
    _info "K3DM_ACG_SKIP_SESSION_CHECK=1 — skipping ACG/Pluralsight session check"
    return 0
  fi
  _info "Checking Pluralsight (ACG) session in Antigravity browser..."

  local gemini_prompt
  gemini_prompt="You are a browser automation agent. Use Playwright (Node.js) to do the following:

1. Connect to the running Antigravity browser via CDP: const browser = await chromium.connectOverCDP('http://localhost:9222');
2. Use the first browser context and page (do NOT launch a new browser).
3. Navigate to https://app.pluralsight.com/cloud-playground/cloud-sandboxes and wait for the page to load.
4. Check if the user is logged in by looking for user avatar, account menu, or sandbox list elements (e.g. [data-testid='user-menu'], [aria-label='User menu'], or a heading containing 'Cloud Sandboxes').
5. If logged in: print ACG_SESSION_OK and exit with code 0.
6. If NOT logged in:
   a. Navigate to https://app.pluralsight.com/id/signin
   b. Print: ACTION REQUIRED: Please log into Pluralsight in the Antigravity browser window, then press Enter to continue.
   c. Wait for the page URL to no longer contain '/signin' — poll every 5 seconds, timeout after 300 seconds.
   d. Once URL is no longer '/signin', print ACG_SESSION_OK and exit with code 0.
   e. If 300 seconds pass without login, print ERROR: Pluralsight login timeout and exit with code 1.

Write the Playwright script to ${HOME}/.gemini/tmp/k3d-manager/ag_acg_session.js, execute with node, print the result.
Exit code 1 if session cannot be confirmed."

  _antigravity_gemini_prompt "$gemini_prompt" --yolo
}

function antigravity_install() {
  _ensure_node
  _ensure_antigravity
  _ensure_antigravity_ide
  _ensure_antigravity_mcp_playwright
  _info "Node.js: $(node --version 2>&1)"
  _info "gemini: $(gemini --version 2>&1 || echo 'version unknown')"
  local _ag_bin
  _ag_bin=$( (_command_exist agy && echo agy) || (_command_exist antigravity && echo antigravity) || echo "")
  _info "antigravity: $( [[ -n "$_ag_bin" ]] && "$_ag_bin" --version 2>&1 || echo 'version unknown')"
  _info "Playwright MCP: configured in Antigravity mcp_config.json"
  _info "Run 'antigravity_trigger_copilot_review <owner> <repo>' — Antigravity will launch and prompt for GitHub login if needed."
}

function antigravity_trigger_copilot_review() {
  local owner="${1:?usage: antigravity_trigger_copilot_review <owner> <repo> [prompt]}"
  local repo="${2:?usage: antigravity_trigger_copilot_review <owner> <repo> [prompt]}"
  local review_prompt="${3:-Review this codebase for code quality, security, and architecture.}"

  _ensure_antigravity
  _ensure_antigravity_ide
  _ensure_antigravity_mcp_playwright
  _browser_launch
  _antigravity_ensure_github_session

  _info "Triggering Copilot coding agent on ${owner}/${repo}..."

  local gemini_prompt
  gemini_prompt="You are a browser automation agent. Use Playwright (Node.js) to do the following:

1. Connect to the running Antigravity browser via CDP: const browser = await chromium.connectOverCDP('http://localhost:9222');
2. Use the first browser context and page (do NOT launch a new browser).
3. Navigate to https://github.com/${owner}/${repo}/agents
4. Find and click the button to create a new Copilot coding agent task.
5. Enter this review prompt in the task input: ${review_prompt}
6. Submit the task.
7. Wait until the page URL changes to https://github.com/${owner}/${repo}/tasks/<uuid>.
8. Extract and print ONLY the task UUID (last path segment of the URL).

Write the Playwright script to ${HOME}/.gemini/tmp/k3d-manager/ag_trigger.js, execute with node, print the UUID.
Exit code 1 if UUID not found within 60 seconds."

  _antigravity_gemini_prompt "$gemini_prompt" --yolo
}

function antigravity_poll_task() {
  local owner="${1:?usage: antigravity_poll_task <owner> <repo> <task_uuid> [timeout]}"
  local repo="${2:?usage: antigravity_poll_task <owner> <repo> <task_uuid> [timeout]}"
  local task_uuid="${3:?usage: antigravity_poll_task <owner> <repo> <task_uuid> [timeout]}"
  local timeout="${4:-300}"

  _ensure_antigravity

  _info "Polling task ${task_uuid} on ${owner}/${repo} (timeout: ${timeout}s)..."

  local gemini_prompt
  gemini_prompt="Use your web_fetch tool to fetch https://github.com/${owner}/${repo}/tasks/${task_uuid}
Poll every 30 seconds until the task status shows complete or done.
Timeout after ${timeout} seconds — if not complete by then, print ERROR: timeout and exit.
Once complete, extract and print the full review output verbatim. Do not summarize."

  _antigravity_gemini_prompt "$gemini_prompt"
}
