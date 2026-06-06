# Bug: /ask claude max-turns is hardcoded and too low — no way to adjust per-call or globally

**Branch:** `k3d-manager-v1.6.3`
**Files:** `bin/k3dm-webhook`

---

## Problem

`/ask claude` hits `Error: Reached max turns (5)` on any question that requires more than
5 tool calls to investigate. The non-filing/non-fixing claude path is hardcoded to
`--max-turns 5`; the filing path is hardcoded to `--max-turns 10`. Neither value is
adjustable without editing the webhook source.

There is no way to raise the cap for a single call from Slack, and no environment variable
to set a cluster-wide default.

---

## Fix

### Change 1 — `bin/k3dm-webhook`: read `K3DM_ASK_MAX_TURNS` env var at module level

Add after the existing module-level constants (near line 38 where `JOB_DIR` is defined):

**Exact old block (line 38 area):**

```python
JOB_DIR = Path("/tmp/k3dm-webhook-jobs")
```

**Exact new block:**

```python
JOB_DIR = Path("/tmp/k3dm-webhook-jobs")
_ASK_MAX_TURNS_DEFAULT = int(os.environ.get("K3DM_ASK_MAX_TURNS", "10"))
```

---

### Change 2 — `bin/k3dm-webhook`: parse optional `turns=N` token from the Slack message

In the `ask` command handler (lines 597–622), after `question` is extracted, strip any
`turns=N` token from the question string and capture the value.

**Exact old block (lines 599–608):**

```python
        parts = command.strip().split()
        if len(parts) >= 3 and parts[1].lower() in _VALID_AGENTS:
            agent = parts[1].lower()
            question = " ".join(parts[2:]).strip()
        elif len(parts) >= 2 and parts[1].lower() not in _VALID_AGENTS:
            agent = "claude"
            question = " ".join(parts[1:]).strip()
        else:
            _notify_job(job_id, "Usage: `ask [claude|gemini|codex] <question>`")
            return
```

**Exact new block:**

```python
        parts = command.strip().split()
        if len(parts) >= 3 and parts[1].lower() in _VALID_AGENTS:
            agent = parts[1].lower()
            question = " ".join(parts[2:]).strip()
        elif len(parts) >= 2 and parts[1].lower() not in _VALID_AGENTS:
            agent = "claude"
            question = " ".join(parts[1:]).strip()
        else:
            _notify_job(job_id, "Usage: `ask [claude|gemini|codex] <question>`")
            return
        import re as _re
        _turns_match = _re.search(r'\bturns=(\d+)\b', question)
        ask_max_turns = int(_turns_match.group(1)) if _turns_match else _ASK_MAX_TURNS_DEFAULT
        if _turns_match:
            question = _re.sub(r'\s*turns=\d+\s*', ' ', question).strip()
```

---

### Change 3 — `bin/k3dm-webhook`: thread `ask_max_turns` through `_run_cluster_ask`

**Exact old block (lines 617–622):**

```python
        threading.Thread(
            target=_run_cluster_ask,
            args=(new_job_id, agent, question, ""),
            kwargs={"thread_ts": thread_ts},
            daemon=True,
        ).start()
```

**Exact new block:**

```python
        threading.Thread(
            target=_run_cluster_ask,
            args=(new_job_id, agent, question, ""),
            kwargs={"thread_ts": thread_ts, "max_turns": ask_max_turns},
            daemon=True,
        ).start()
```

---

### Change 4 — `bin/k3dm-webhook`: add `max_turns` parameter to `_run_cluster_ask`

**Exact old line (line 1626):**

```python
def _run_cluster_ask(job_id, agent, question, response_url, thread_ts=None):
```

**Exact new line:**

```python
def _run_cluster_ask(job_id, agent, question, response_url, thread_ts=None, max_turns=None):
```

Add after the `def` line, before any existing code in the function body:

```python
    if max_turns is None:
        max_turns = _ASK_MAX_TURNS_DEFAULT
```

---

### Change 5 — `bin/k3dm-webhook`: replace hardcoded `--max-turns` values with `max_turns`

**Exact old block (filing/fixing path, line 1796):**

```python
                    "--max-turns", "10",
```

**Exact new block:**

```python
                    "--max-turns", str(max_turns),
```

**Exact old block (non-filing path, line 1806):**

```python
                    "--max-turns", "5",
```

**Exact new block:**

```python
                    "--max-turns", str(max_turns),
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | Add `_ASK_MAX_TURNS_DEFAULT` module constant; parse `turns=N` from Slack message; thread `max_turns` through `_run_cluster_ask`; replace both hardcoded `--max-turns` values |

---

## Usage After Fix

```
# Set cluster-wide default in .envrc:
export K3DM_ASK_MAX_TURNS=15

# Override for a single call from Slack:
/ask claude turns=20 why is the payment pod crashing?
/ask claude turns=3 what namespace is redis in?
```

The `turns=N` token is stripped from the question before it is sent to the agent.

---

## Rules

- No other files touched
- `python3 -c "import ast; ast.parse(open('bin/k3dm-webhook').read())"` — zero syntax errors

---

## Definition of Done

- [ ] `_ASK_MAX_TURNS_DEFAULT = int(os.environ.get("K3DM_ASK_MAX_TURNS", "10"))` added at module level
- [ ] `turns=N` parsed from Slack message; removed from question string before passing to agent
- [ ] `ask_max_turns` threaded through to `_run_cluster_ask` via `kwargs`
- [ ] `_run_cluster_ask` signature has `max_turns=None`; body defaults to `_ASK_MAX_TURNS_DEFAULT`
- [ ] Both `--max-turns` hardcoded values replaced with `str(max_turns)`
- [ ] `python3 -c "import ast; ast.parse(open('bin/k3dm-webhook').read())"` passes
- [ ] Committed and pushed to `k3d-manager-v1.6.3`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
feat(webhook): make /ask max-turns adjustable via K3DM_ASK_MAX_TURNS env var and turns=N inline token
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/k3dm-webhook`
- Do NOT commit to `main` — work on `k3d-manager-v1.6.3`
- Do NOT import `re` at the top of the file — use the local `import re as _re` inside the handler to avoid touching the existing import block
