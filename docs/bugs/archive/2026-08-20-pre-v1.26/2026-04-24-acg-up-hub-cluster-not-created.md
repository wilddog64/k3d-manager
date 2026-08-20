# Bug: `bin/acg-up` Step 3.5 errors on missing Hub cluster instead of creating it

**Date:** 2026-04-24
**Status:** OPEN
**Severity:** HIGH (make down → make up cycle always fails at Step 3.5)
**Branch:** `k3d-manager-v1.1.0`

## Summary

Step 3.5 (added in `e577579e`) checks for the local Hub k3d cluster and errors if it is not
found. But `bin/acg-up` never creates the local Hub cluster — Step 2 provisions only the
remote k3s-aws CloudFormation stack. After `make down` deletes the Hub cluster, a fresh
`make up` always fails at Step 3.5.

## Observed Failure

```
INFO: [acg-up] Step 3.5/12 — Verifying local Hub cluster (OrbStack clamshell resume guard)...
ERROR: [acg-up] Local Hub cluster 'k3d-cluster' not found — OrbStack may have restarted after Mac sleep. Run 'k3d cluster list' and check OrbStack, then re-run.
make: *** [up] Error 1
```

## Root Cause

`deploy_cluster --provider "${_cluster_provider}"` at Step 2 calls the k3s-aws provider,
which provisions the remote EC2 cluster only. The local Hub k3d cluster is created by
`deploy_cluster --provider k3d`, which `bin/acg-up` never calls.

Step 3.5 was designed as a guard for when the Hub existed and was killed by OrbStack
restarting after Mac sleep — but it also fires when the Hub was legitimately deleted by
`make down`, which is the normal teardown path.

## Fix

Change the "not found" branch in Step 3.5 from `_err` (abort) to `deploy_cluster --provider k3d`
(auto-create). Keep the second check (`kubectl get nodes --request-timeout=10s`) as the
OrbStack-broken-state guard — it fires only if the cluster appears in the list but is
unreachable, which is the true "OrbStack killed it after sleep" case.

**File:** `bin/acg-up`

**Old (lines 102–110):**
```bash
_HUB_CLUSTER_CTX="k3d-${HUB_CLUSTER_NAME:-k3d-cluster}"
_info "[acg-up] Step 3.5/12 — Verifying local Hub cluster (OrbStack clamshell resume guard)..."
if ! k3d cluster list 2>/dev/null | grep -q "^${HUB_CLUSTER_NAME:-k3d-cluster}[[:space:]]"; then
  _err "[acg-up] Local Hub cluster '${HUB_CLUSTER_NAME:-k3d-cluster}' not found — OrbStack may have restarted after Mac sleep. Run 'k3d cluster list' and check OrbStack, then re-run."
fi
if ! kubectl get nodes --context "${_HUB_CLUSTER_CTX}" --request-timeout=10s >/dev/null 2>&1; then
  _err "[acg-up] Local Hub cluster '${_HUB_CLUSTER_CTX}' is unreachable — OrbStack/k3d may be in a broken state after sleep. Check 'orbctl status'."
fi
_info "[acg-up] Local Hub cluster verified."
```

**New (lines 102–112):**
```bash
_HUB_CLUSTER_CTX="k3d-${HUB_CLUSTER_NAME:-k3d-cluster}"
_info "[acg-up] Step 3.5/12 — Verifying local Hub cluster (create if missing)..."
if ! k3d cluster list 2>/dev/null | grep -q "^${HUB_CLUSTER_NAME:-k3d-cluster}[[:space:]]"; then
  _info "[acg-up] Local Hub cluster '${HUB_CLUSTER_NAME:-k3d-cluster}' not found — creating it now..."
  deploy_cluster --provider k3d "${HUB_CLUSTER_NAME:-k3d-cluster}"
fi
if ! kubectl get nodes --context "${_HUB_CLUSTER_CTX}" --request-timeout=10s >/dev/null 2>&1; then
  _err "[acg-up] Local Hub cluster '${_HUB_CLUSTER_CTX}' is unreachable — OrbStack/k3d may be in a broken state after sleep. Check 'orbctl status'."
fi
_info "[acg-up] Local Hub cluster verified."
```

Two lines changed: the step label text, and `_err` → `_info` + `deploy_cluster` call.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `bin/acg-up` lines 99–115 in full.
3. Read `scripts/lib/providers/k3d.sh` function `_provider_k3d_deploy_cluster` — confirms
   `deploy_cluster --provider k3d` is idempotent (checks cluster exists before creating).
4. Read `memory-bank/activeContext.md`.
5. Run `shellcheck -x bin/acg-up` — must exit 0 before and after.

---

## Rules

- `shellcheck -x bin/acg-up` must exit 0.
- Only `bin/acg-up` may be touched.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `bin/acg-up` lines 102–112 match the **New** block above exactly.
2. `shellcheck -x bin/acg-up` exits 0.
3. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(acg-up): auto-create local Hub cluster in Step 3.5 instead of aborting
   ```
4. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
5. `memory-bank/activeContext.md`: add entry for this fix as COMPLETE with real commit SHA under Open Items.
6. `memory-bank/progress.md`: add `[x] **acg-up Hub cluster auto-create** — COMPLETE (<sha>)` under Known Bugs / Gaps.
7. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `bin/acg-up`.
- Do NOT commit to `main`.
- Do NOT remove the `kubectl get nodes` unreachable check — it is the real OrbStack guard.
