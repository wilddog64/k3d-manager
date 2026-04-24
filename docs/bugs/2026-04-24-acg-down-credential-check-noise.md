# Bug: `bin/acg-down` prints ERROR-level credential noise when sandbox is already expired

**Date:** 2026-04-24
**Status:** OPEN
**Severity:** MEDIUM (confusing output — user cannot distinguish "expired sandbox" from "creds wrong for live sandbox")
**Branch:** `k3d-manager-v1.1.0`

## Summary

After `ae2fca66`, `bin/acg-down` catches `acg_teardown`'s non-zero return and continues.
However `acg_teardown` calls `_acg_check_credentials` which always prints ERROR-level lines
to stderr before returning 1:

```
ERROR: [acg] AWS credentials invalid or expired.
ERROR: [acg] If the sandbox was removed (expired TTL):
ERROR: [acg]   1. Start a new sandbox at ...
ERROR: [acg]   2. Run: acg_get_credentials
ERROR: [acg]   3. Re-run: make up
ERROR: [acg] If the sandbox is still running: update ~/.aws/credentials from the ACG console.
```

These ERROR lines appear whether the sandbox expired (stack already gone — expected) or whether
credentials are stale for a still-running sandbox (real problem requiring action). The user
cannot tell the difference from the output.

## Root Cause

`bin/acg-down` calls `acg_teardown --confirm` which internally runs `_acg_check_credentials`.
That private function always prints ERROR lines before returning 1. There is no quiet mode.

## Fix

In `bin/acg-down`'s `k3s-aws` case, check AWS credentials directly and silently before
deciding whether to call `acg_teardown`. `acg.sh` is already sourced at that point, so
`ACG_REGION` is set.

- Valid creds → `acg_teardown --confirm` runs normally, zero ERROR noise.
- Invalid creds → single clean `_info` skip message, local cleanup continues.

**File:** `bin/acg-down`

**Old (lines 49–51):**
```bash
    _info "[acg-down] Tearing down CloudFormation stack (AWS)..."
    acg_teardown --confirm || _info "[acg-down] CloudFormation teardown failed — credentials may have expired (sandbox already removed). Continuing local cleanup."
    ;;
```

**New (lines 49–55):**
```bash
    _info "[acg-down] Tearing down CloudFormation stack (AWS)..."
    if aws sts get-caller-identity --region "${ACG_REGION}" --query 'Arn' --output text >/dev/null 2>&1; then
      acg_teardown --confirm
    else
      _info "[acg-down] AWS credentials invalid or expired — sandbox already removed. Skipping CloudFormation teardown."
    fi
    ;;
```

No other lines change.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `bin/acg-down` in full (current version after `ae2fca66`).
3. Read `memory-bank/activeContext.md`.
4. Run `shellcheck -x bin/acg-down` — must exit 0 before and after.

---

## Rules

- `shellcheck -x bin/acg-down` must exit 0.
- Only `bin/acg-down` may be touched — do NOT modify `acg.sh` or any plugin.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `bin/acg-down` lines 49–55 match the **New** block above exactly.
2. `shellcheck -x bin/acg-down` exits 0.
3. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(acg-down): pre-check AWS creds silently; skip teardown with clean INFO when expired
   ```
4. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
5. `memory-bank/activeContext.md`: update "New Bug: acg-down expired credentials abort" entry — change status to COMPLETE with new SHA.
6. `memory-bank/progress.md`: update `**acg-down expired credentials abort**` line — append new SHA and note that ERROR noise is now suppressed.
7. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `bin/acg-down`.
- Do NOT commit to `main`.
- Do NOT suppress the `_info` skip message — it must remain visible so the user knows teardown was skipped.
