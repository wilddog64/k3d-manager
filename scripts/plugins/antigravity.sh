#!/usr/bin/env bash
# scripts/plugins/antigravity.sh
#
# Antigravity plugin — browser automation via gemini CLI (@google/gemini-cli) + Playwright.
# gemini CLI drives Playwright for interactive browser tasks (GitHub Copilot agent trigger,
# ACG sandbox TTL extend) and uses web_fetch for reading task output.
#
# Prerequisites: Node.js (via _ensure_node), gemini CLI, Playwright + Chromium
#
# Public functions:
#   antigravity_install                  — verify full stack installed
#   antigravity_trigger_copilot_review   — trigger GitHub Copilot coding agent task
#   antigravity_poll_task                — poll task until complete, print output
#   antigravity_acg_extend               — extend ACG sandbox TTL via browser

function _ensure_antigravity() {
	if _command_exist gemini; then
		return 0
	fi
	_log "gemini CLI not found — installing @google/gemini-cli..."
	_ensure_node
	_run_command -- npm install -g @google/gemini-cli
	if ! _command_exist gemini; then
		_err "gemini CLI install succeeded but binary not found in PATH"
	fi
}

function _ensure_playwright() {
	if _command_exist playwright; then
		return 0
	fi
	_log "Playwright not found — installing..."
	_ensure_node
	_run_command -- npm install -g playwright
	_run_command -- playwright install chromium
}

function antigravity_install() {
	_ensure_node
	_ensure_antigravity
	_ensure_playwright
	_log "Node.js: $(node --version 2>&1)"
	_log "gemini: $(gemini --version 2>&1 || echo 'version unknown')"
	_log "playwright: $(playwright --version 2>&1 || echo 'version unknown')"
}

function antigravity_trigger_copilot_review() {
	local owner="${1:?usage: antigravity_trigger_copilot_review <owner> <repo> [prompt]}"
	local repo="${2:?usage: antigravity_trigger_copilot_review <owner> <repo> [prompt]}"
	local review_prompt="${3:-Review this codebase for code quality, security, and architecture.}"

	_ensure_antigravity
	_ensure_playwright

	_log "Triggering Copilot coding agent on ${owner}/${repo}..."

	local gemini_prompt
	gemini_prompt="You are a browser automation agent. Use Playwright (Node.js) to do the following:

1. Launch a Chromium browser (headless: true).
2. Navigate to https://github.com/${owner}/${repo}/agents
3. Find and click the button to create a new Copilot coding agent task.
4. Enter this review prompt in the task input: ${review_prompt}
5. Submit the task.
6. Wait until the page URL changes to https://github.com/${owner}/${repo}/tasks/<uuid>.
7. Extract and print ONLY the task UUID (last path segment of the URL).

Write the Playwright script to /tmp/ag_trigger.js, execute with node, print the UUID.
Exit code 1 if UUID not found within 60 seconds."

	gemini --prompt "$gemini_prompt"
}

function antigravity_poll_task() {
	local owner="${1:?usage: antigravity_poll_task <owner> <repo> <task_uuid> [timeout]}"
	local repo="${2:?usage: antigravity_poll_task <owner> <repo> <task_uuid> [timeout]}"
	local task_uuid="${3:?usage: antigravity_poll_task <owner> <repo> <task_uuid> [timeout]}"
	local timeout="${4:-300}"

	_ensure_antigravity

	_log "Polling task ${task_uuid} on ${owner}/${repo} (timeout: ${timeout}s)..."

	local gemini_prompt
	gemini_prompt="Use your web_fetch tool to fetch https://github.com/${owner}/${repo}/tasks/${task_uuid}
Poll every 30 seconds until the task status shows complete or done.
Timeout after ${timeout} seconds — if not complete by then, print ERROR: timeout and exit.
Once complete, extract and print the full review output verbatim. Do not summarize."

	gemini --prompt "$gemini_prompt"
}

function antigravity_acg_extend() {
	local sandbox_url="${1:?usage: antigravity_acg_extend <sandbox_url> [hours]}"
	local hours="${2:-4}"

	_ensure_antigravity
	_ensure_playwright

	_log "Extending ACG sandbox TTL by ${hours}h at ${sandbox_url}..."

	local gemini_prompt
	gemini_prompt="You are a browser automation agent. Use Playwright (Node.js) to do the following:

1. Launch a Chromium browser (headless: true).
2. Navigate to ${sandbox_url}
3. If a Google login page appears, use stored session cookies or prompt the user to authenticate.
4. Find the sandbox TTL extend button (look for 'Extend', '+4 hours', or similar).
5. Click to extend by ${hours} hours.
6. Confirm the new TTL is shown on the page.
7. Print the new sandbox expiry time.

Write the Playwright script to /tmp/ag_acg_extend.js, execute with node, print the result.
Exit code 1 if the extend button is not found or the action fails."

	gemini --prompt "$gemini_prompt"
}
