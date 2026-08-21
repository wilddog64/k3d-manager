# Bug: `bin/acg-down` aborts on expired AWS credentials — local Hub never cleaned up

**Date:** 2026-04-24
**Status:** OPEN
**Severity:** HIGH (local k3d cluster left running after sandbox expires)
**Branch:** `k3d-manager-v1.1.0`

## Summary

When an ACG sandbox expires (TTL), AWS credentials become invalid.
`acg_teardown --confirm` calls `_acg_check_credentials || return 1` (line 628 of `acg.sh`),
which returns 1. Because `bin/acg-down` runs under `set -euo pipefail`, the non-zero return
aborts the script. The Vault port-forward kill and local k3d Hub teardown never run.

Result: the local Hub cluster (`k3d-cluster`) is left running even though the remote sandbox
is already gone. A subsequent `make up` may then fail or produce unexpected state because the
Hub cluster was never reset.

## Observed Failure

```
INFO: [acg-down] Stopping tunnel...
[tunnel] stopped
INFO: [acg-down] Tearing down CloudFormation stack (AWS)...
INFO: [acg] Checking AWS credentials...
ERROR: [acg] AWS credentials invalid or expired.
ERROR: [acg] If the sandbox was removed (expired TTL): ...
make: *** [down] Error 1
```

Local k3d Hub cluster and Vault port-forward were not cleaned up.

## Root Cause

`bin/acg-down` line 50 — `acg_teardown --confirm` — fails hard when credentials expire.
Under `set -euo pipefail` this aborts before the shared cleanup steps (Vault PF kill,
k3d cluster delete) that run unconditionally after the `case` block.

## Fix

Change line 50 from a hard call to a guarded call. If `acg_teardown` fails, log a warning
and continue — expired credentials mean the sandbox (and its CloudFormation stack) is already
gone; local cleanup must still run.

**File:** `bin/acg-down`

**Old (line 50):**
```bash
    acg_teardown --confirm
```

**New (line 50):**
```bash
    acg_teardown --confirm || _info "[acg-down] CloudFormation teardown failed — credentials may have expired (sandbox already removed). Continuing local cleanup."
```

No other lines change. The `|| true` pattern is intentionally avoided — `_info` is used so the
warning is always visible in output.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `bin/acg-down` in full (current version after `706e0ba2`).
3. Read `memory-bank/activeContext.md`.
4. Run `shellcheck bin/acg-down` — must exit 0 before and after.

---

## Rules

- `shellcheck bin/acg-down` must exit 0.
- Only `bin/acg-down` may be touched — do NOT modify `acg.sh` or any plugin.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `bin/acg-down` line 50 matches the **New** block above exactly — one line changed.
2. `shellcheck bin/acg-down` exits 0.
3. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(acg-down): continue local cleanup when AWS credentials are expired
   ```
4. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
5. `memory-bank/activeContext.md`: add entry for this fix as COMPLETE with real commit SHA under Open Items.
6. `memory-bank/progress.md`: add `[x] **acg-down expired credentials abort** — COMPLETE (<sha>)` under Known Bugs / Gaps.
7. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `bin/acg-down`.
- Do NOT commit to `main`.
- Do NOT use `|| true` — use `|| _info "[acg-down] ..."` so the warning is always visible.
