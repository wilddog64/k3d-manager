# Bug: Webhook job state in /tmp — lost on reboot, no cleanup

**Branch:** `k3d-manager-v1.6.4`
**Date:** 2026-06-08
**Files:** `bin/k3dm-webhook`, `bin/k3dm-cleanup`, `docs/architecture/cloudflare-slack-relay.md`

---

## Problem

`JOB_DIR` is hardcoded to `/tmp/k3dm-webhook-jobs`. Two consequences:

1. **Lost on reboot** — all job history (output, thread_ts, status) disappears on restart.
   Thread commands (`status`, `logs`, `diagnosis`) in Slack stop working for any job
   started before the reboot.

2. **No cleanup** — completed and failed job dirs accumulate indefinitely.
   After extended use the directory fills with hundreds of stale dirs (observed: 250+).
   `bin/k3dm-cleanup` has no webhook job section.

---

## Fix

### Change 1 — `bin/k3dm-webhook` line 38: move JOB_DIR to persistent state dir

**Exact old line:**

```python
JOB_DIR = Path("/tmp/k3dm-webhook-jobs")
```

**Exact new line:**

```python
JOB_DIR = Path(os.environ.get("K3DM_JOB_DIR", Path.home() / ".local/share/k3d-manager/webhook-jobs"))
```

### Change 2 — `bin/k3dm-webhook` `_clear_stale_jobs()`: also delete old terminal jobs

Extend `_clear_stale_jobs()` to delete job dirs whose status is `success` or `failed`
and whose mtime is older than 7 days. This runs at startup and keeps the job dir tidy.

**Exact old block (lines 1118–1136):**

```python
def _clear_stale_jobs():
    """On startup, mark any job stuck in 'running' as 'failed' — they are orphaned."""
    if not JOB_DIR.exists():
        return
    for entry in JOB_DIR.iterdir():
        status_file = entry / "status"
        try:
            if status_file.exists() and status_file.read_text().strip() == "running":
                status_file.write_text("failed")
                print(f"[k3dm-webhook] cleared stale job {entry.name}")
                action_file = entry / "action"
                action = action_file.read_text().strip() if action_file.exists() else "job"
                _notify_job(
                    entry.name,
                    f"❌ *acg-{action}* orphaned — webhook restarted mid-job; "
                    f"check cluster state manually (job `{entry.name}`)",
                )
        except Exception:
            pass
```

**Exact new block:**

```python
_JOB_RETENTION_SECS = 7 * 24 * 3600  # keep completed/failed jobs for 7 days

def _clear_stale_jobs():
    """On startup: orphan running jobs; purge terminal jobs older than retention."""
    if not JOB_DIR.exists():
        return
    now = time.time()
    for entry in JOB_DIR.iterdir():
        if not entry.is_dir():
            continue
        status_file = entry / "status"
        try:
            status = status_file.read_text().strip() if status_file.exists() else ""
            if status == "running":
                status_file.write_text("failed")
                print(f"[k3dm-webhook] cleared stale job {entry.name}")
                action_file = entry / "action"
                action = action_file.read_text().strip() if action_file.exists() else "job"
                _notify_job(
                    entry.name,
                    f"❌ *acg-{action}* orphaned — webhook restarted mid-job; "
                    f"check cluster state manually (job `{entry.name}`)",
                )
            elif status in {"success", "failed"} and (now - entry.stat().st_mtime) > _JOB_RETENTION_SECS:
                shutil.rmtree(entry, ignore_errors=True)
                print(f"[k3dm-webhook] purged old job {entry.name} (status={status})")
        except Exception:
            pass
```

### Change 3 — `bin/k3dm-webhook`: ensure JOB_DIR created at startup

Add `JOB_DIR.mkdir(parents=True, exist_ok=True)` in `__main__` before `_clear_stale_jobs()`.

**Exact old block (near line 2409):**

```python
    _clear_stale_jobs()
```

**Exact new block:**

```python
    JOB_DIR.mkdir(parents=True, exist_ok=True)
    _clear_stale_jobs()
```

### Change 4 — `docs/architecture/cloudflare-slack-relay.md`: update job dir path

Replace both references to `/tmp/k3dm-webhook-jobs/<id>/` with
`~/.local/share/k3d-manager/webhook-jobs/<id>/`.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | Move JOB_DIR to persistent state dir; add 7-day retention cleanup; mkdir at startup |
| `docs/architecture/cloudflare-slack-relay.md` | Update job dir path references |

---

## Rules

- `python3 -m py_compile bin/k3dm-webhook` — no syntax errors
- No other files touched
- Do NOT restart the webhook until active job completes

---

## Definition of Done

- [ ] `JOB_DIR` resolves to `~/.local/share/k3d-manager/webhook-jobs` by default
- [ ] `K3DM_JOB_DIR` env var overrides the path
- [ ] Old terminal jobs (>7 days) are deleted at startup
- [ ] Running jobs are still orphaned with Slack notification
- [ ] `python3 -m py_compile bin/k3dm-webhook` passes
- [ ] Committed and pushed to `k3d-manager-v1.6.4`
- [ ] Webhook restarted after active job completes

**Commit message (exact):**
```
fix(webhook): move JOB_DIR to persistent state dir + 7-day stale job cleanup
```
