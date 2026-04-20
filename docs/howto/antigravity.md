# How-To: Antigravity Browser Automation

The `antigravity` plugin handles browser automation tasks — extending ACG sandbox TTL and triggering GitHub Copilot coding agent reviews. The browser is **Google Chrome**, launched with `--remote-debugging-port=9222` and `--password-store=basic`. Playwright connects to Chrome over CDP (port 9222). Antigravity IDE (a VS Code fork) is used as the Playwright MCP host for the Copilot agent trigger workflow.

## Prerequisites

- Node.js 18+ (`_ensure_node` installs it if missing)
- Antigravity IDE installed (see below)
- gemini CLI authenticated (`gemini auth login`)

## First-Time Setup

```bash
./scripts/k3d-manager antigravity_install
```

This verifies and installs (if missing):
- Node.js
- `@google/gemini-cli`
- Antigravity IDE binary (`agy` or `antigravity`)
- Playwright MCP entry in Antigravity's `mcp_config.json`

### First-Run Login

On first use, Google Chrome will open and navigate to the target site's login page. **Log in manually** — the session cookie is saved in `~/.local/share/k3d-manager/playwright-auth` and reused on all subsequent runs until it expires.

- **ACG login:** triggered by `antigravity_acg_extend`
- **GitHub login:** triggered by `antigravity_trigger_copilot_review`

## Extend ACG Sandbox TTL

```bash
./scripts/k3d-manager antigravity_acg_extend <sandbox-url>
```

Chrome opens the sandbox page and Playwright clicks the extend button (+4 hours). The new expiry time is printed on completion.

```bash
# Example
./scripts/k3d-manager antigravity_acg_extend "https://app.pluralsight.com/cloud-playground/cloud-sandboxes"

# Skip ACG session check (useful for CI or if Playwright cannot launch)
K3DM_ACG_SKIP_SESSION_CHECK=1 ./scripts/k3d-manager antigravity_acg_extend "<sandbox-url>"
```

## Trigger a GitHub Copilot Coding Agent Review

```bash
antigravity_trigger_copilot_review <owner> <repo> [prompt]
```

Navigates to `github.com/<owner>/<repo>/agents`, creates a new Copilot coding agent task with the given prompt, and returns the task UUID.

```bash
# Default prompt: "Review this codebase for code quality, security, and architecture."
./scripts/k3d-manager antigravity_trigger_copilot_review wilddog64 k3d-manager

# Custom prompt
./scripts/k3d-manager antigravity_trigger_copilot_review wilddog64 k3d-manager "Focus on shell injection risks."
```

## Poll a Copilot Task

```bash
./scripts/k3d-manager antigravity_poll_task <owner> <repo> <task-uuid> [timeout-seconds]
```

Polls the task URL every 30 seconds until complete (default timeout: 300s). Prints the full review output verbatim.

## How It Works

```
k3d-manager function
    → gemini CLI (--model gemini-2.5-flash, fallback to 2.0/1.5)
        → Playwright MCP over CDP → Google Chrome (port 9222)
```

gemini generates a Playwright Node.js script, writes it to `${HOME}/.gemini/tmp/k3d-manager/`, and executes it. The script connects to the running Chrome instance via CDP — it does not launch a new headless browser.

## Troubleshoot

```bash
# Verify Chrome is running with CDP exposed
curl -sf http://127.0.0.1:9222/json | jq '.[0].title'

# Manually launch Chrome with CDP
open -a "Google Chrome" --args --remote-debugging-port=9222 --password-store=basic --user-data-dir=~/.local/share/k3d-manager/playwright-auth   # macOS
google-chrome --remote-debugging-port=9222 --password-store=basic --user-data-dir=~/.local/share/k3d-manager/playwright-auth &                  # Linux
```

# Check gemini CLI
gemini --version
gemini --model gemini-2.5-flash --prompt "say hello"
```
