# Bug: `diagnosis` thread command fails for acg-resume jobs — checks `log`, not `output`

**Branch:** `k3d-manager-v1.6.3`
**Files:** `bin/k3dm-webhook`

---

## Problem

Typing `diagnosis` in the Slack thread of a completed or failed `acg-resume` job returns:

```
⚠️ No log found for job <job_id>
```

`acg-resume` jobs (action: `resume`) write their output to `JOB_DIR/<job_id>/output`.
The `diagnosis` branch of `_handle_thread_command` only checks for `JOB_DIR/<job_id>/log`.
Since `log` is never created for `acg-resume` jobs, diagnosis always fails on those threads.

**Root cause:** `bin/k3dm-webhook` line 484 — `log_file = JOB_DIR / job_id / "log"` — does not
fall back to the `output` file used by `acg-resume`.

---

## Reproduction

1. Run `/acg-resume` in Slack — observe the job thread.
2. After the job completes or fails, reply `diagnosis` in that thread.
3. Bot responds: `⚠️ No log found for job <job_id>`.

Confirmed: job `d055b912` (action: `resume`, status: `failed`) had `output` file (9 KB)
but no `log` file.

---

## Fix

### Change 1 — `bin/k3dm-webhook`: fall back to `output` when `log` is absent

**Exact old block (lines 483–493):**

```python
    elif cmd == "diagnosis":
        log_file = JOB_DIR / job_id / "log"
        if log_file.exists():
            lines = log_file.read_text().splitlines(keepends=True)
            try:
                result = _analyze_failure(lines)
                _notify_job(job_id, f"🔍 *Re-diagnosis* (job `{job_id}`)\n{result}")
            except Exception as exc:
                _notify_job(job_id, f"⚠️ Diagnosis failed: {exc}")
        else:
            _notify_job(job_id, f"⚠️ No log found for job `{job_id}`")
```

**Exact new block:**

```python
    elif cmd == "diagnosis":
        log_file = JOB_DIR / job_id / "log"
        output_file = JOB_DIR / job_id / "output"
        source_file = log_file if log_file.exists() else (output_file if output_file.exists() else None)
        if source_file:
            lines = source_file.read_text().splitlines(keepends=True)
            try:
                result = _analyze_failure(lines)
                _notify_job(job_id, f"🔍 *Re-diagnosis* (job `{job_id}`)\n{result}")
            except Exception as exc:
                _notify_job(job_id, f"⚠️ Diagnosis failed: {exc}")
        else:
            _notify_job(job_id, f"⚠️ No log found for job `{job_id}`")
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | Fall back to `output` file in `diagnosis` command when `log` absent |

---

## Rules

- No other files touched
- `python3 -m py_compile bin/k3dm-webhook` — zero errors

---

## Definition of Done

- [ ] `diagnosis` branch checks `log` first, falls back to `output`
- [ ] `python3 -m py_compile bin/k3dm-webhook` passes
- [ ] Committed and pushed to `k3d-manager-v1.6.3`
- [ ] `make restart-webhook` run after commit
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(webhook): diagnosis command falls back to output file for acg-resume jobs
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/k3dm-webhook`
- Do NOT commit to `main` — work on `k3d-manager-v1.6.3`
