# Bug: acg-status health check curl timeout shorter than maximum smoke test duration

**Branch:** `k3d-manager-v1.6.3`
**Files:** `bin/acg-status`

---

## Problem

`acg-status` reports `webhook unreachable at localhost:7443 — run: make restart-webhook`
even when the webhook process is running, if the cluster is slow.

**Root cause:** `bin/acg-status` calls `/api/v1/health` with `--max-time 35`. That
endpoint runs `_smoke_test_services(retries=1)`, which probes 8 services with an 8s
timeout each — up to 64s in the worst case. When the cluster is degraded (ArgoCD,
Prometheus, or other services slow to respond), the smoke test exceeds the 35s curl
limit, curl exits with code 28 (timeout), `_health_json` is empty, and the script
prints the "unreachable" message despite the webhook process being healthy.

When the webhook is actually down (connection refused), curl exits immediately — so
increasing the timeout does not make the "actually down" case slower.

---

## Reproduction

1. Ensure several smoke-test endpoints are slow or unreachable (e.g., ArgoCD, Prometheus)
2. Run `bin/acg-status`
3. The Service Health section prints `(webhook unreachable)` despite the webhook being up

---

## Fix

### Change 1 — `bin/acg-status`: increase health check curl timeout from 35s to 90s

**Exact old block (line 76):**

```bash
  _health_json=$(curl -sf --max-time 35 \
```

**Exact new block:**

```bash
  _health_json=$(curl -sf --max-time 90 \
```

90s gives the full smoke test (8 services × 8s timeout + overhead) room to complete.
Connection refused (webhook actually down) still returns immediately.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-status` | `--max-time 35` → `--max-time 90` on health check curl |

---

## Rules

- No other files touched
- `shellcheck -S warning bin/acg-status` — zero new warnings

---

## Definition of Done

- [ ] `bin/acg-status` line 76: `--max-time 90`
- [ ] `shellcheck -S warning bin/acg-status` passes
- [ ] Committed and pushed to `k3d-manager-v1.6.3`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-status): increase health check curl timeout from 35s to 90s to cover full smoke test duration
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-status`
- Do NOT commit to `main` — work on `k3d-manager-v1.6.3`
