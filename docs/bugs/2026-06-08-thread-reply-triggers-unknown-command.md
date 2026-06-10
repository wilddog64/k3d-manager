# Bug: Every Slack thread reply triggers "Unknown command"

**Branch:** `k3d-manager-v1.6.4`
**Date:** 2026-06-08
**Files:** `bin/k3dm-webhook`

---

## Problem

Any message posted in a job thread — including conversational replies like "thanks",
"got it", or "ok" — is routed to `_handle_thread_command`. If the first word is not a
recognised command keyword, the webhook replies with:

```
❓ Unknown command `thanks` — available: kill, diagnosis, status, ...
```

This is noisy and confusing for normal conversation in a job thread.

**Root cause:** `_handle_thread_command` has no guard to distinguish commands from
conversational text. Every non-bot, non-subtype thread reply reaches the `else` branch.

---

## Fix

### Change 1 — `bin/k3dm-webhook`: add command-intent guard at top of `_handle_thread_command`

Only treat a message as a command if it starts with `/` OR its first word exactly matches
a known command keyword. Everything else returns silently.

**Exact old block (lines 474–481):**

```python
def _handle_thread_command(job_id, command):
    """Dispatch a thread command for job_id. Runs in a background thread."""
    cmd = command.strip().lstrip("/").lower().split()[0] if command.strip() else ""
    if cmd in {"gemini", "claude", "codex"}:
        _alias_parts = command.strip().lstrip("/").split(None, 1)
        command = f"ask {cmd} {_alias_parts[1]}" if len(_alias_parts) > 1 else f"ask {cmd}"
        cmd = "ask"
```

**Exact new block:**

```python
_THREAD_COMMANDS = {
    "kill", "diagnosis", "status", "logs", "ask",
    "acg-up", "acg-down", "acg-status", "acg-refresh", "acg-resume",
    "cluster-status", "gemini", "claude", "codex",
}

def _handle_thread_command(job_id, command):
    """Dispatch a thread command for job_id. Runs in a background thread."""
    cmd = command.strip().lstrip("/").lower().split()[0] if command.strip() else ""
    if not command.strip().startswith("/") and cmd not in _THREAD_COMMANDS:
        return
    if cmd in {"gemini", "claude", "codex"}:
        _alias_parts = command.strip().lstrip("/").split(None, 1)
        command = f"ask {cmd} {_alias_parts[1]}" if len(_alias_parts) > 1 else f"ask {cmd}"
        cmd = "ask"
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | Add `_THREAD_COMMANDS` set + silent-return guard before dispatch |

---

## Rules

- `python3 -m py_compile bin/k3dm-webhook` — no syntax errors
- No other files touched

---

## Definition of Done

- [ ] Conversational replies in a job thread produce no webhook response
- [ ] `kill`, `status`, `logs`, `diagnosis`, `ask claude <q>`, `/gemini <q>` still work
- [ ] `python3 -m py_compile bin/k3dm-webhook` passes
- [ ] Committed and pushed to `k3d-manager-v1.6.4`
- [ ] memory-bank updated

**Commit message (exact):**
```
fix(webhook): ignore non-command thread replies — silent return for conversational text
```
