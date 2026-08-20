# Bug: `_provider_k3d_configure_istio` uses EXIT trap — leaks into caller shell on inline call

**Date:** 2026-04-24
**Status:** OPEN
**Severity:** HIGH (breaks `make up` whenever `deploy_cluster --provider k3d` is called inline)
**Branch:** `k3d-manager-v1.1.0`

## Summary

`_provider_k3d_configure_istio` in `scripts/lib/providers/k3d.sh` line 100 registers:

```bash
trap '$(_cleanup_trap_command "$istio_yamlfile")' EXIT
```

Using `EXIT` instead of `RETURN` means the trap is registered on the **current shell process**,
not scoped to the function. When called from a long-running script (e.g., `bin/acg-up`) via
an inline `deploy_cluster` call, the trap fires when that script exits — long after
`_provider_k3d_configure_istio` has returned and `$istio_yamlfile` has gone out of scope.

Under `set -u`, referencing an unbound variable is a hard error, causing the caller script
to exit with error 1.

## Why Now

Previously, `deploy_cluster --provider k3d` was only invoked via `scripts/k3d-manager`, which
runs as a subprocess. The EXIT trap fired when that subprocess exited (right after deploy_cluster
completed), while `$istio_yamlfile` was still in scope.

`bin/acg-up` Step 3.5 (`73382eb2`) now calls `deploy_cluster --provider k3d` inline in the
same shell. The EXIT trap registers on `bin/acg-up`'s process and fires much later.

## Observed Error

```
namespace/default labeled
/Users/cliang/.../scripts/lib/providers/k3d.sh: line 169: yamlfile: unbound variable
/Users/cliang/.../scripts/lib/providers/k3d.sh: line 1: istio_yamlfile: unbound variable
make: *** [up] Error 1
```

## Root Cause

`_provider_k3d_create_cluster` (same file) already uses `RETURN` correctly:
```bash
trap '$(_cleanup_trap_command "$yamlfile")' RETURN   # ← correct
```

`_provider_k3d_configure_istio` uses `EXIT` instead:
```bash
trap '$(_cleanup_trap_command "$istio_yamlfile")' EXIT  # ← wrong
```

`RETURN` fires when the function returns (local variables still in scope).
`EXIT` fires when the shell exits (local variables gone).

## Fix

**File:** `scripts/lib/providers/k3d.sh`

**Old (line 100):**
```bash
   trap '$(_cleanup_trap_command "$istio_yamlfile")' EXIT
```

**New (line 100):**
```bash
   trap '$(_cleanup_trap_command "$istio_yamlfile")' RETURN
```

One word changed. No other lines change.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `scripts/lib/providers/k3d.sh` lines 72–101 (`_provider_k3d_configure_istio`) in full.
3. Read `scripts/lib/providers/k3d.sh` lines 103–152 (`_provider_k3d_create_cluster`) — confirm
   it already uses `RETURN` as the reference pattern.
4. Read `memory-bank/activeContext.md`.
5. Run `shellcheck -x scripts/lib/providers/k3d.sh` — must exit 0 before and after.

---

## Rules

- `shellcheck -x scripts/lib/providers/k3d.sh` must exit 0.
- Only `scripts/lib/providers/k3d.sh` may be touched.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `scripts/lib/providers/k3d.sh` line 100 matches the **New** block above exactly — one word changed.
2. `shellcheck -x scripts/lib/providers/k3d.sh` exits 0.
3. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(k3d-provider): use RETURN trap in configure_istio to prevent EXIT trap leak
   ```
4. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
5. `memory-bank/activeContext.md`: add entry for this fix as COMPLETE with real commit SHA under Open Items.
6. `memory-bank/progress.md`: add `[x] **k3d-provider EXIT trap leak** — COMPLETE (<sha>)` under Known Bugs / Gaps.
7. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `scripts/lib/providers/k3d.sh`.
- Do NOT commit to `main`.
- Do NOT change the RETURN trap in `_provider_k3d_create_cluster` — it is already correct.
