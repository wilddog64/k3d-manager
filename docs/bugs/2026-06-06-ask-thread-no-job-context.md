# Bug: `ask claude` in job thread provides no failure context — Claude wastes all turns on discovery

**Branch:** `k3d-manager-v1.6.3`
**Files:** `bin/k3dm-webhook`

---

## Problem

When the user types `ask claude investigate` (with `turns=20`) in the Slack thread of a
failed `acg-resume` job, Claude exhausts all 20 turns on discovery — listing namespaces,
listing pods across contexts, etc. — before reaching the actual failure. The job thread
already contains all the relevant output (which job step failed, which namespace, which
service), but `_handle_thread_command` passes only the bare question to `_run_cluster_ask`,
discarding that context entirely.

**Root cause:** `bin/k3dm-webhook` `ask` branch (line ~605): the question string is passed
verbatim to `_run_cluster_ask` with no reference to the parent job's `output` or `log`.
Claude starts cold every time.

---

## Reproduction

1. Run `/acg-resume` — job fails on Keycloak step.
2. Reply `diagnosis` in the thread — bot reports "Keycloak failed to initialize".
3. Reply `ask claude turns=20 please investigate the issue`.
4. Claude hits `Error: Reached max turns (20)` without completing diagnosis.

---

## Fix

### Change 1 — `bin/k3dm-webhook`: inject parent job tail as context before the question

**Exact old block (lines 612–616):**

```python
        import re as _re
        _turns_match = _re.search(r'\bturns=(\d+)\b', question)
        ask_max_turns = int(_turns_match.group(1)) if _turns_match else _ASK_MAX_TURNS_DEFAULT
        if _turns_match:
            question = _re.sub(r'\s*turns=\d+\s*', ' ', question).strip()
```

**Exact new block:**

```python
        import re as _re
        _turns_match = _re.search(r'\bturns=(\d+)\b', question)
        ask_max_turns = int(_turns_match.group(1)) if _turns_match else _ASK_MAX_TURNS_DEFAULT
        if _turns_match:
            question = _re.sub(r'\s*turns=\d+\s*', ' ', question).strip()
        _job_log = JOB_DIR / job_id / "log"
        _job_out = JOB_DIR / job_id / "output"
        _ctx_file = _job_log if _job_log.exists() else (_job_out if _job_out.exists() else None)
        if _ctx_file:
            _ctx_lines = [l.rstrip() for l in _ctx_file.read_text().splitlines() if l.strip()][-80:]
            _ctx_text = "\n".join(_ctx_lines)
            question = (
                f"Job output context (last 80 lines of job `{job_id}`):\n"
                f"```\n{_ctx_text}\n```\n\n"
                f"User question: {question}"
            )
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | Inject parent job tail into `ask` question when output/log exists |

---

## Rules

- No other files touched
- `python3 -m py_compile bin/k3dm-webhook` — zero errors

---

## Definition of Done

- [ ] `ask` branch prepends last 80 lines of parent job output to the question
- [ ] Falls back gracefully when neither `log` nor `output` exists (question passed unchanged)
- [ ] `python3 -m py_compile bin/k3dm-webhook` passes
- [ ] Committed and pushed to `k3d-manager-v1.6.3`
- [ ] `make restart-webhook` run after commit
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(webhook): inject parent job output tail into ask context to reduce wasted turns
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/k3dm-webhook`
- Do NOT commit to `main` — work on `k3d-manager-v1.6.3`
