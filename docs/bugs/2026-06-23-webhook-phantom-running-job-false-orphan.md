# Bugfix: webhook — phantom `running` job fires false "orphaned" alarm on restart

**Branch:** `fix/webhook-phantom-running-job-false-orphan` (cut from `origin/main`)
**Files:** `bin/k3dm-webhook`

---

## Problem

When the webhook restarts, `_clear_stale_jobs()` posts a Slack alarm —
`❌ *cluster-<action>* orphaned — webhook restarted mid-job; check cluster state manually` —
for **every** job still marked `running`, regardless of how old it is. A job whose work
actually completed but whose process was killed (e.g. by `make restart-webhook`) *before* it
wrote its terminal status stays `running` forever, so it re-fires this alarm on the next
restart — days later, for a job that finished successfully and tore nothing down unexpectedly.

**Observed incident (2026-06-23):** Job `0310d5a4` was a `cluster-down` that ran and
**completed** on 2026-06-21 17:22 (`output` ends `Done. Remote cluster deleted; local Hub
preserved.`) but its `status` file stayed `running`. When the webhook was restarted on
2026-06-23 15:44 during the Slack-secret rotation, `_clear_stale_jobs()` flipped it to
`failed` and posted the orphan alarm. It surfaced right as the user ran `/cluster-status`,
making it look like `/cluster-status` had triggered a teardown. It had not — `/cluster-status`
routing is correct (`workers/slack-relay/index.js:118` → `/api/v1/cluster-status` →
`_run_cluster_status`).

**Root cause:** `_clear_stale_jobs()` does not age-gate the orphan notice. The sibling
function `_running_cluster_job()` (`bin/k3dm-webhook:470`) already treats a `running` job
older than `_MAX_JOB_AGE_SECS` (3h) as stale and silently fails it — `_clear_stale_jobs()`
must apply the same gate so a long-dead phantom job is cleared quietly instead of alarming.

> The deeper trigger (a killed process leaving `status=running`) is a SIGTERM/SIGKILL race —
> a `finally`/signal-handler fix is **out of scope** for this bugfix (see *What NOT to Do*).
> The age-gate fully eliminates the false alarm for the realistic case.

---

## Reproduction

1. Create a job dir under `~/.local/share/k3d-manager/webhook-jobs/<id>/` with
   `action` = `down` and `status` = `running`, and back-date its mtime > 3h
   (`touch -t` the dir).
2. Restart the webhook (`make restart-webhook`).
3. **Actual:** Slack receives `❌ *cluster-down* orphaned — webhook restarted mid-job …`.
4. **Expected:** the phantom job is cleared quietly (logged to stdout only); no Slack alarm.

A genuinely recent `running` job (mtime < 3h) must still produce the orphan notice.

---

## Fix

### Change 1 — `bin/k3dm-webhook`: age-gate the orphan notice in `_clear_stale_jobs()`

**Exact old block (lines 1260–1285):**

```python
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
                    f"❌ *cluster-{action}* orphaned — webhook restarted mid-job; "
                    f"check cluster state manually (job `{entry.name}`)",
                )
            elif status in {"success", "failed"} and (now - entry.stat().st_mtime) > _JOB_RETENTION_SECS:
                shutil.rmtree(entry, ignore_errors=True)
                print(f"[k3dm-webhook] purged old job {entry.name} (status={status})")
        except Exception:
            pass
```

**Exact new block:**

```python
def _clear_stale_jobs():
    """On startup: orphan recently-running jobs (mtime within _MAX_JOB_AGE_SECS) with a
    Slack notice; clear phantom older running jobs quietly (no alarm); purge terminal jobs
    older than retention."""
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
                age = now - entry.stat().st_mtime
                status_file.write_text("failed")
                if age > _MAX_JOB_AGE_SECS:
                    print(f"[k3dm-webhook] cleared phantom running job {entry.name} "
                          f"(age {int(age)}s > {_MAX_JOB_AGE_SECS}s) — no orphan notice")
                    continue
                print(f"[k3dm-webhook] cleared stale job {entry.name}")
                action_file = entry / "action"
                action = action_file.read_text().strip() if action_file.exists() else "job"
                _notify_job(
                    entry.name,
                    f"❌ *cluster-{action}* orphaned — webhook restarted mid-job; "
                    f"check cluster state manually (job `{entry.name}`)",
                )
            elif status in {"success", "failed"} and (now - entry.stat().st_mtime) > _JOB_RETENTION_SECS:
                shutil.rmtree(entry, ignore_errors=True)
                print(f"[k3dm-webhook] purged old job {entry.name} (status={status})")
        except Exception:
            pass
```

`_MAX_JOB_AGE_SECS` is already defined (`bin/k3dm-webhook:393`); no new import or constant
needed. `status_file.write_text("failed")` runs in both branches so the phantom is always
cleared — only the Slack `_notify_job` call is gated.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | Age-gate the orphan Slack notice in `_clear_stale_jobs()`; phantom (>3h) running jobs cleared quietly |

---

## Rules

- `python3 -m py_compile bin/k3dm-webhook` — must pass (file is Python, not bash; do NOT run shellcheck on it)
- `./scripts/k3d-manager _agent_audit` — must pass (no bare sudo / inline creds / hardcoded IPs introduced)
- No other files touched; no behavior change to the recent-job orphan notice or the retention purge

---

## Definition of Done

- [ ] `_clear_stale_jobs()` matches the new block exactly
- [ ] `python3 -m py_compile bin/k3dm-webhook` passes
- [ ] `_agent_audit` passes
- [ ] Committed and pushed to `fix/webhook-phantom-running-job-false-orphan`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(webhook): age-gate orphan notice so phantom running jobs don't false-alarm on restart
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/k3dm-webhook`
- Do NOT commit to `main` — work on `fix/webhook-phantom-running-job-false-orphan`
- Do NOT add SIGTERM/SIGKILL signal handlers or `finally` terminal-status writes in this
  bugfix — that deeper root-cause fix is separate, out-of-scope future work
- Do NOT change `_MAX_JOB_AGE_SECS`, `_JOB_RETENTION_SECS`, or `_running_cluster_job()`
- Do NOT run `make restart-webhook` — Claude does that after verifying the commit
