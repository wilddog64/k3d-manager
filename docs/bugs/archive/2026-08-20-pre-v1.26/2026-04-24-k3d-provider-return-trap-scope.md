# Bug: RETURN traps in k3d provider are shell-global — re-fire in parent functions

**Date:** 2026-04-24
**Status:** OPEN
**Severity:** HIGH (breaks `make up` — cleanup fires with out-of-scope local variables)
**Branch:** `k3d-manager-v1.1.0`

## Summary

In bash, `trap '...' RETURN` is global to the shell process — it is NOT scoped to the
function that set it. When a function sets a RETURN trap and returns, the trap fires (correct).
But the trap persists in the shell, so it fires again when the **calling** function returns,
and again when its caller returns, etc.

Both `_provider_k3d_create_cluster` (line 142) and `_provider_k3d_configure_istio` (line 100)
set RETURN traps that reference local variables (`$yamlfile`, `$istio_yamlfile`). When those
functions return from within `_provider_k3d_deploy_cluster`, the traps fire once correctly.
Then when `_provider_k3d_deploy_cluster` itself returns (and further up the call stack into
`bin/acg-up`), the traps fire again — but the local variables are long out of scope, causing
`unbound variable` under `set -u`.

## Observed Symptom

```
namespace/default labeled
INFO: Cleaning up temporary files... : /tmp/k3d-istio-operator.0T4NWi.yaml :   ← RETURN fires (OK)
INFO: Cleaning up temporary files... : /tmp/k3d-istio-operator.0T4NWi.yaml :   ← re-fires in parent (OK, file already gone)
.../k3d.sh: line 169: istio_yamlfile: unbound variable                         ← re-fires again, variable gone
make: *** [up] Error 1
```

## Root Cause

`trap '...' RETURN` does not auto-clear after firing. It stays registered in the shell until
explicitly cleared with `trap - RETURN`. The last RETURN trap set wins — so
`_provider_k3d_configure_istio`'s trap replaces `_provider_k3d_create_cluster`'s trap and
then re-fires in every parent function's return.

## Fix

Prepend `trap - RETURN;` inside each trap handler. This self-clears the trap on first
fire, preventing re-fire in parent functions.

**File:** `scripts/lib/providers/k3d.sh`

**Old line 100 (`_provider_k3d_configure_istio`):**
```bash
   trap '$(_cleanup_trap_command "$istio_yamlfile")' RETURN
```

**New line 100:**
```bash
   trap 'trap - RETURN; $(_cleanup_trap_command "$istio_yamlfile")' RETURN
```

**Old line 142 (`_provider_k3d_create_cluster`):**
```bash
   trap '$(_cleanup_trap_command "$yamlfile")' RETURN
```

**New line 142:**
```bash
   trap 'trap - RETURN; $(_cleanup_trap_command "$yamlfile")' RETURN
```

Two lines changed, same pattern in both.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `scripts/lib/providers/k3d.sh` lines 72–101 (`_provider_k3d_configure_istio`) in full.
3. Read `scripts/lib/providers/k3d.sh` lines 103–152 (`_provider_k3d_create_cluster`) in full.
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

1. `scripts/lib/providers/k3d.sh` line 100 and line 142 match the **New** blocks above exactly.
2. `shellcheck -x scripts/lib/providers/k3d.sh` exits 0.
3. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(k3d-provider): self-clear RETURN trap to prevent re-fire in parent functions
   ```
4. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
5. `memory-bank/activeContext.md`: add entry for this fix as COMPLETE with real commit SHA under Open Items.
6. `memory-bank/progress.md`: add `[x] **k3d-provider RETURN trap scope** — COMPLETE (<sha>)` under Known Bugs / Gaps.
7. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `scripts/lib/providers/k3d.sh`.
- Do NOT commit to `main`.
- Do NOT remove the existing RETURN trap — only prepend `trap - RETURN;` inside it.
