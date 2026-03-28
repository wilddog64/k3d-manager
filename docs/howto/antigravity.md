# How-To: Antigravity Browser Automation

Antigravity is an agent-first IDE (VS Code fork) with a built-in Chromium browser. k3d-manager uses it for browser automation tasks — extending ACG sandbox TTL and triggering GitHub Copilot coding agent reviews — via the Playwright MCP server over CDP (port 9222).

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

On first use, Antigravity will open its browser window and navigate to the target site's login page. **Log in manually** — the session cookie is saved in Antigravity's browser profile and reused on all subsequent runs until it expires.

- **ACG login:** triggered by `antigravity_acg_extend`
- **GitHub login:** triggered by `antigravity_trigger_copilot_review`

## Extend ACG Sandbox TTL

```bash
antigravity_acg_extend <sandbox-url>
```

Antigravity opens the sandbox page and clicks the extend button (+4 hours). The new expiry time is printed on completion.

```bash
# Example
antigravity_acg_extend "https://learn.acloud.guru/lab/..."

# Skip ACG session check (while domain migration to Pluralsight is pending)
K3DM_ACG_SKIP_SESSION_CHECK=1 antigravity_acg_extend "<sandbox-url>"
```

## Trigger a GitHub Copilot Coding Agent Review

```bash
antigravity_trigger_copilot_review <owner> <repo> [prompt]
```

Navigates to `github.com/<owner>/<repo>/agents`, creates a new Copilot coding agent task with the given prompt, and returns the task UUID.

```bash
# Default prompt: "Review this codebase for code quality, security, and architecture."
antigravity_trigger_copilot_review wilddog64 k3d-manager

# Custom prompt
antigravity_trigger_copilot_review wilddog64 k3d-manager "Focus on shell injection risks."
```

## Poll a Copilot Task

```bash
antigravity_poll_task <owner> <repo> <task-uuid> [timeout-seconds]
```

Polls the task URL every 30 seconds until complete (default timeout: 300s). Prints the full review output verbatim.

## How It Works

```
k3d-manager function
    → gemini CLI (--model gemini-2.5-flash, fallback to 2.0/1.5)
        → Playwright MCP over CDP → Antigravity browser (port 9222)
```

gemini generates a Playwright Node.js script, writes it to `${HOME}/.gemini/tmp/k3d-manager/`, and executes it. The script connects to the running Antigravity browser via CDP — it does not launch a new headless browser.

## Troubleshoot

```bash
# Verify Antigravity is running and CDP is exposed
curl -sf http://localhost:9222/json | jq '.[0].title'

# Manually launch Antigravity with CDP
open -a "Antigravity" --args --remote-debugging-port=9222   # macOS
antigravity --remote-debugging-port=9222 &                  # Linux

# Check gemini CLI
gemini --version
gemini --model gemini-2.5-flash --prompt "say hello"
```
