# How-To: Copilot CLI Integration

The `copilot` plugin exposes `_copilot_review` (from lib-foundation) as two practical public
functions: one for pod failure triage and one for bug spec drafting. A pre-commit hook
integration wires AI architectural lint on staged shell files.

## Prerequisites

- GitHub Copilot subscription (Individual, Business, or Enterprise)
- GitHub CLI authenticated: `gh auth login`
- Copilot CLI installed — `_ensure_copilot_cli` installs it automatically on first use:
  - macOS: via `brew install copilot-cli`
  - Linux: via the official Copilot release installer script

## Setup

Enable AI features:

```bash
export K3DM_ENABLE_AI=1
```

Persist it in your shell profile (`.zshrc`, `.bashrc`, or `.envrc`):

```bash
echo 'export K3DM_ENABLE_AI=1' >> ~/.zshrc
```

On first run, `_ensure_copilot_cli` verifies authentication via `copilot auth status`.
If auth fails, it prints an error — log in with `gh auth login` and retry.

## Triage a Failing Pod

Collects `kubectl describe pod` + the last 100 log lines and asks Copilot to diagnose the failure.

```bash
./scripts/k3d-manager copilot_triage_pod <namespace> <pod-name>
```

**Examples:**

```bash
# Triage a CrashLoopBackOff in the payment namespace
./scripts/k3d-manager copilot_triage_pod shopping-cart-payment \
  payment-service-789b779b45-ptpkm

# Triage a vault pod that won't start
./scripts/k3d-manager copilot_triage_pod vault vault-0
```

Copilot prints a diagnosis and suggested fix. It does not run any commands — output is read-only.

## Draft a Bug Spec

Collects the last 10 git commits and recently changed files, then asks Copilot to scaffold a
`docs/bugs/` spec with **Root Cause**, **What to Change** (Before/After code blocks), and a
**Definition of Done** checkbox list.

```bash
./scripts/k3d-manager copilot_draft_spec '<short bug description>'
```

**Examples:**

```bash
# Draft a spec for a path bug
./scripts/k3d-manager copilot_draft_spec \
  'cdp.sh uses ../foundation relative path which breaks in subtree context'

# Draft a spec for a CrashLoop root cause
./scripts/k3d-manager copilot_draft_spec \
  'payment-service crashes on startup because postgres password is CHANGE_ME'
```

Copy the output into `docs/bugs/YYYY-MM-DD-<slug>.md` and hand it off to Codex for
implementation.

## Pre-Commit Architectural Lint (opt-in)

`_copilot_review` is wired into the pre-commit hook via `AGENT_LINT_AI_FUNC`. When
`K3DM_ENABLE_AI=1`, the hook calls `_agent_lint` which passes staged `.sh` files to Copilot
for architectural lint against `scripts/etc/agent/lint-rules.md`.

This is **opt-in** — the hook does nothing extra when `K3DM_ENABLE_AI` is unset or `0`.
No Copilot CLI required for users who don't set it.

```bash
# Run a commit with AI lint enabled
K3DM_ENABLE_AI=1 git commit -m "feat: my change"

# Persist opt-in
export K3DM_ENABLE_AI=1
git commit -m "feat: my change"
```

If Copilot flags a violation, the commit is blocked with the lint output. Fix the flagged
code and commit again.

## Low-Level API: `_copilot_review`

`_copilot_review` is the sandboxed Copilot CLI wrapper in lib-foundation. You can call it
directly in any shell script that sources `scripts/lib/system.sh`:

```bash
source scripts/lib/system.sh

_copilot_review --prompt "Explain the purpose of _agent_lint in this repo."
_copilot_review --prompt "Review staged changes for security issues." --model claude-sonnet-4-5
```

**Guard rails applied automatically:**
- Prompt is scoped to the k3d-manager repo context
- Forbidden fragments blocked: `shell(git push)`, `shell(rm`, `shell(eval`, `shell(sudo`,
  `shell(curl`, `shell(wget`, `shell(cd`
- Runs from repo root (via `_k3dm_repo_root`)
- Errors out (exits non-zero) when `K3DM_ENABLE_AI=0`

**Signature:**

```
_copilot_review [--prompt|-p <text>] [--model <model-id>] [<copilot-flags>...]
```

## Using `_copilot_review` in Other Projects

`_copilot_review` ships in lib-foundation (`scripts/lib/system.sh`). Any project that pulls
lib-foundation as a subtree can call it directly.

**Step 1 — Pull lib-foundation:**

```bash
git subtree add --prefix scripts/lib/foundation \
  https://github.com/wilddog64/lib-foundation.git main --squash
```

**Step 2 — Source it and call:**

```bash
source scripts/lib/foundation/scripts/lib/system.sh

export K3DM_ENABLE_AI=1
_copilot_review --prompt "Review this deployment manifest for security issues."
```

**Step 3 — Write a project-specific wrapper** (same pattern as `copilot_triage_pod`):

```bash
function myproject_triage_db() {
  local context
  context="$(psql -c "SELECT * FROM pg_stat_activity;" 2>&1 || true)"
  _copilot_review --prompt "Diagnose this PostgreSQL activity. Do not run commands.\n\n${context}"
}
```

**Wire AI lint in your own pre-commit hook:**

```bash
# In .git/hooks/pre-commit or scripts/hooks/pre-commit
export AGENT_LINT_AI_FUNC="_copilot_review"
export AGENT_LINT_GATE_VAR="K3DM_ENABLE_AI"
export K3DM_ENABLE_AI="${K3DM_ENABLE_AI:-0}"
# ... then call _agent_lint
```

## Troubleshoot

```bash
# Verify Copilot CLI is installed and authenticated
copilot auth status

# Show usage for copilot_triage_pod
./scripts/k3d-manager copilot_triage_pod --help

# Run a minimal review
K3DM_ENABLE_AI=1 source scripts/lib/system.sh
_copilot_review --prompt "say hello"
```
