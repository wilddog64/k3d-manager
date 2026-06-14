# Bugfix: v1.7.1 — `/hostinger-status` report body posts without a code fence

**Branch:** `k3d-manager-v1.7.1`
**Files:** `bin/k3dm-webhook`

---

## Problem

Commit `5f764399` ("fix(slack): hostinger-status posts the report body…") fixed the primary
symptom (the success path now posts `status_out` instead of "report gathered"), but **deviated
from the approved spec** (`docs/bugs/2026-06-14-bugfix-hostinger-status-report-body.md`). Codex
hand-edited a narrow slice of the `if/else` instead of applying the spec's exact new block, so:

1. **No code fence** — the report is logged as raw text (`_log(report[-3500:].rstrip())`), not
   wrapped in a ```` ``` ```` block. The report contains columnar `kubectl get nodes/pods` output
   that only renders legibly in Slack monospace; without the fence the columns collapse.
2. **Wrong header glyph** — `✅ *Hostinger app cluster status*` instead of the spec's
   `🖥️ *Hostinger app cluster status*`.
3. **Failure path unchanged** — the spec replaced the whole `if/else` with a flat block that posts
   the full report **always** plus `⚠️ hostinger-status exited non-zero` on non-success. Codex kept
   the old `else` branch (8 tail lines only), so a non-success exit still drops the full report.

**Root cause:** Codex preserved the original `if "__WEBHOOK_SUCCESS__" in status_out: … else: …`
structure and edited only the success branch, rather than replacing the entire block with the
spec's exact new block. `py_compile`/`_agent_audit` pass (syntactically valid), so the gates did
not catch the spec-fidelity gap.

---

## Reproduction

```bash
# In Slack: /hostinger-status
#   -> success: report posts as RAW text — kubectl node/pod columns are misaligned,
#      header is ✅ not 🖥️.
#   -> on a non-success exit: only the last 8 lines post, not the full report.
# Expected: report wrapped in a ``` code fence under 🖥️; full report on failure + a warning line.
```

---

## Fix

### Change 1 — `bin/k3dm-webhook`: replace the success/failure block with the spec's exact new block

**Exact old block (current, from `5f764399`):**

```python
        if "__WEBHOOK_SUCCESS__" in status_out:
            _log("\n✅ *Hostinger app cluster status*")
            report = status_out.replace("__WEBHOOK_SUCCESS__", "")
            _log(report[-3500:].rstrip())
        else:
            tail_lines = [l for l in status_out.strip().splitlines()[-8:] if l]
            _log("\n❌ *Hostinger status failed*")
            if tail_lines:
                _log("```\n{}\n```".format("\n".join(tail_lines)))
        _finish("success")
```

**Exact new block:**

```python
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
| `bin/k3dm-webhook` | `_run_hostinger_status` posts the report inside a ```` ``` ```` fence under `🖥️`; flat success/failure handling per spec |

---

## Rules

- `python3 -m py_compile bin/k3dm-webhook` — compiles clean
- `./scripts/k3d-manager _agent_audit` — passes
- `_posix_spawn_capture` only — no `subprocess.run` (NEF-safe)
- No other file touched

---

## Definition of Done

- [ ] Report posts inside a ```` ``` ```` fence under `🖥️ *Hostinger app cluster status*`
- [ ] Non-success exit posts the full report + `⚠️ hostinger-status exited non-zero`
- [ ] `timeout=180` retained (untouched)
- [ ] `python3 -m py_compile` and `_agent_audit` clean
- [ ] Committed and pushed to `k3d-manager-v1.7.1`
- [ ] memory-bank updated; stale duplicate ASSIGNED row removed

**Commit message (exact):**
```
fix(slack): hostinger-status report posts inside a code fence
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/k3dm-webhook`
- Do NOT commit to `main` — work on `k3d-manager-v1.7.1`

---

## Operator follow-on (NOT part of this commit)

- `make restart-webhook`, then smoke-test `/hostinger-status` — expect the report rendered in a
  monospace block.

---

## Process note

Codex applied a narrower edit than the spec's exact new block despite a plan-review reminder to
"apply the spec's exact old→new block verbatim — do not preserve the `else`." Gates
(`py_compile`/`_agent_audit`) cannot catch spec-fidelity gaps. Verification must diff the commit
against the spec's exact new block, not just confirm the symptom is fixed.
