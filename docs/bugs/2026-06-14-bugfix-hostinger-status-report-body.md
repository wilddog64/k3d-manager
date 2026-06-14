# Bugfix: v1.7.1 — `/hostinger-status` drops the report body on success

**Branch:** `k3d-manager-v1.7.1`
**Files:** `bin/k3dm-webhook`

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- `git pull origin k3d-manager-v1.7.1`
- Read `bin/k3dm-webhook` `_run_hostinger_status` in full (≈ lines 1893–1936) before editing.

---

## Problem

`/hostinger-status` posts a "complete" message to Slack but **never includes the actual
`bin/hostinger-status` report**. On the success path the function logs only
`✅ *Hostinger status complete* — report gathered` and finishes — the captured cluster
status (`status_out`) is discarded. A user running `/hostinger-status` sees the ack and a
bare "complete" line, with no node/pod/ArgoCD status at all.

**Root cause:** commit `227de0f3` implemented Change 7 by mirroring `_run_cluster_refresh`'s
*action*-style success/failure logging instead of the spec's *report*-posting logic. The spec
(`docs/plans/v1.7.1-slack-hostinger-status.md`, Change 7) deliberately diverged from that
mirror precisely so the report body is posted. `/hostinger-status` is a read-only status
command — its entire purpose is to deliver the report, like its shell-script counterpart.

---

## Reproduction

```bash
# In Slack: /hostinger-status
#   -> ack: "🖥️ Checking Hostinger app cluster status…"
#   -> thread: "✅ Hostinger status complete — report gathered"   (NO report content)
# Expected: the full 6-section bin/hostinger-status report in the thread.
```

---

## Fix

### Change 1 — `bin/k3dm-webhook`: post the report body on the success path

Keep `timeout=180` (intentional — `bin/hostinger-status` reaches a remote cluster). Replace
only the success/failure logging block so the captured report is posted, matching the spec's
Change-7 intent.

**Exact old block (lines 1922–1933):**

```python
        if status_timeout:
            _log("\n❌ *Hostinger status timed out* after 180s — run `bin/hostinger-status` manually")
            _finish("failed")
            return
        if "__WEBHOOK_SUCCESS__" in status_out:
            _log("\n✅ *Hostinger status complete* — report gathered")
        else:
            tail_lines = [l for l in status_out.strip().splitlines()[-8:] if l]
            _log("\n❌ *Hostinger status failed*")
            if tail_lines:
                _log("```\n{}\n```".format("\n".join(tail_lines)))
        _finish("success")
```

**Exact new block:**

```python
        if status_timeout:
            _log("\n❌ *Hostinger status timed out* after 180s — run `bin/hostinger-status` manually")
            _finish("failed")
            return
        report = status_out.replace("__WEBHOOK_SUCCESS__", "").rstrip()
        _log("🖥️ *Hostinger app cluster status*")
        if report:
            _log("```\n{}\n```".format(report[-3500:]))
        if "__WEBHOOK_SUCCESS__" not in status_out:
            _log("⚠️ hostinger-status exited non-zero")
        _finish("success")
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | `_run_hostinger_status` success path posts the report body (`report[-3500:]`) instead of "report gathered" |

---

## Rules

- `python3 -m py_compile bin/k3dm-webhook` — compiles clean
- `./scripts/k3d-manager _agent_audit` — passes
- `_posix_spawn_capture` only — do NOT introduce `subprocess.run` (NEF-safe)
- No other file touched; no behavior change to any other command

---

## Definition of Done

- [ ] `_run_hostinger_status` success path posts `report[-3500:]` under `🖥️ *Hostinger app cluster status*`
- [ ] `timeout=180` retained
- [ ] `python3 -m py_compile bin/k3dm-webhook` and `_agent_audit` both clean
- [ ] Committed and pushed to `k3d-manager-v1.7.1`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the commit SHA

**Commit message (exact):**
```
fix(slack): hostinger-status posts the report body, not just "complete"
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/k3dm-webhook`
- Do NOT change any command other than `_run_hostinger_status`'s success/failure block
- Do NOT commit to `main` — work on `k3d-manager-v1.7.1`

---

## Operator follow-on (NOT part of this commit)

- `make restart-webhook` (mandatory after any `bin/k3dm-webhook` change), then smoke test
  `/hostinger-status` from Slack — expect the 6-section report in the thread.
