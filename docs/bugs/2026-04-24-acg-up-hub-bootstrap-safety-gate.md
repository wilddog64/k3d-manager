# Bug: Step 3.6 Hub bootstrap hits safety gate — missing --confirm on dispatcher calls

**Date:** 2026-04-24
**Status:** OPEN
**Severity:** HIGH (make up fails at Step 3.6 on every fresh Hub create)
**Branch:** `k3d-manager-v1.1.0`

## Summary

`bin/acg-up` Step 3.6 (`c59f2c3a`) calls `deploy_vault` and `deploy_argocd` via
`"${REPO_ROOT}/scripts/k3d-manager"` without `--confirm`. The dispatcher's
`__k3dm_deploy_guard_args` fires the safety gate and exits 1:

```
Safety gate: rerun with explicit options or pass --confirm to apply defaults.
make: *** [up] Error 1
```

## Root Cause

The `scripts/k3d-manager` dispatcher wraps every `deploy_*` call through
`__k3dm_deploy_guard_args`, which requires either explicit options or `--confirm`
to proceed. Without it, the dispatcher prints the usage help and exits.

`--confirm` is consumed and stripped by the dispatcher — it is never forwarded to
`vault.sh` or `argocd.sh`. So adding `--confirm` to the dispatcher call does not
conflict with vault's `_vault_parse_deploy_opts` (which does not accept `--confirm`).

## Fix

Add `--confirm` to both dispatcher calls in Step 3.6.

**File:** `bin/acg-up`

**Old (lines 118–119):**
```bash
  "${REPO_ROOT}/scripts/k3d-manager" deploy_vault
  "${REPO_ROOT}/scripts/k3d-manager" deploy_argocd
```

**New (lines 118–119):**
```bash
  "${REPO_ROOT}/scripts/k3d-manager" deploy_vault --confirm
  "${REPO_ROOT}/scripts/k3d-manager" deploy_argocd --confirm
```

Two words added, one per line. No other lines change.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `bin/acg-up` lines 115–121 in full.
3. Read `scripts/k3d-manager` lines 482–523 (`__k3dm_deploy_guard_args`) — confirms
   `--confirm` is consumed by the dispatcher and stripped before the function is called.
4. Run `shellcheck -x bin/acg-up` — must exit 0 before and after.

---

## Rules

- `shellcheck -x bin/acg-up` must exit 0.
- Only `bin/acg-up` may be touched.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `bin/acg-up` lines 118–119 match the **New** block above exactly.
2. `shellcheck -x bin/acg-up` exits 0.
3. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(acg-up): pass --confirm to deploy_vault and deploy_argocd in Step 3.6
   ```
4. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
5. `memory-bank/activeContext.md`: add entry for this fix as COMPLETE with real commit SHA under Open Items.
6. `memory-bank/progress.md`: add `[x] **acg-up Hub bootstrap safety gate** — COMPLETE (<sha>)` under Known Bugs / Gaps.
7. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `bin/acg-up`.
- Do NOT commit to `main`.
- Do NOT add `--confirm` directly to `deploy_vault` or `deploy_argocd` function bodies — the fix is only in `bin/acg-up` Step 3.6.
