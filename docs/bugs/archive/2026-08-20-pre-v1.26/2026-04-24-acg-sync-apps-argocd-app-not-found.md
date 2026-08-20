# Bug: `bin/acg-sync-apps` exits without listing available ArgoCD apps

**Date:** 2026-04-24
**Status:** OPEN
**Severity:** Low (usability)
**Branch:** `k3d-manager-v1.1.0`

## Summary

`bin/acg-sync-apps` defaults to `ARGOCD_APP=data-layer`. When that app is not registered in
ArgoCD (bootstrap not yet complete, or the app is named differently), the script exits with a
generic error that gives no indication of what apps ARE available.

## Terminal Output

```
INFO: [sync-apps] ERROR: ArgoCD app 'data-layer' not found — is bootstrap complete?
make: *** [sync-apps] Error 1
```

## Root Cause

Line 59–62:
```bash
if ! argocd app get "${ARGOCD_APP}" >/dev/null 2>&1; then
  _info "[sync-apps] ERROR: ArgoCD app '${ARGOCD_APP}' not found — is bootstrap complete?"
  exit 1
fi
```

The error message does not show what apps ARE registered, so the user cannot determine the
correct `ARGOCD_APP` value to set.

## Files Implicated

- `bin/acg-sync-apps` (lines 59–62)

---

## Fix

One hunk — `bin/acg-sync-apps` only.

**Location:** lines 59–62, the `if ! argocd app get` block.

**Old:**
```bash
if ! argocd app get "${ARGOCD_APP}" >/dev/null 2>&1; then
  _info "[sync-apps] ERROR: ArgoCD app '${ARGOCD_APP}' not found — is bootstrap complete?"
  exit 1
fi
```

**New:**
```bash
if ! argocd app get "${ARGOCD_APP}" >/dev/null 2>&1; then
  _info "[sync-apps] ERROR: ArgoCD app '${ARGOCD_APP}' not found — is bootstrap complete?"
  _info "[sync-apps] Available apps (set ARGOCD_APP=<name> to target a different one):"
  argocd app list --output name 2>/dev/null || true
  exit 1
fi
```

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `bin/acg-sync-apps` lines 55–65 in full.
3. Read `memory-bank/activeContext.md`.
4. Run `shellcheck bin/acg-sync-apps` — must exit 0 before and after.

---

## Rules

- `shellcheck bin/acg-sync-apps` must exit 0.
- Only `bin/acg-sync-apps` may be touched.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `bin/acg-sync-apps` lines 59–62 match the **New** block above exactly.
2. `shellcheck bin/acg-sync-apps` exits 0.
3. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(acg-sync-apps): list available ArgoCD apps when target app not found
   ```
4. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
5. `memory-bank/activeContext.md`: add entry for this fix as COMPLETE with real commit SHA.
6. `memory-bank/progress.md`: add `[x] **acg-sync-apps app-not-found** — COMPLETE (<sha>)` under Known Bugs / Gaps.
7. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `bin/acg-sync-apps`.
- Do NOT commit to `main`.
