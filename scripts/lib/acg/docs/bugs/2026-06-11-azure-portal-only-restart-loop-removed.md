# Bug: Azure portal-only restart loop causes cascading failures — remove in favor of fail-fast

**Date:** 2026-06-11
**Repo:** lib-acg
**Branch:** feat/v0.1.5
**File:** `bin/acg-credential-test`

---

## Problem

The retry loop introduced in `b61e22e` calls `_do_restart` when Azure credentials are
portal-only and portal login fails. The restart flow (`acg_restart.js`) is fragile and
hits edge cases on every test, blocking the core bidirectional switching requirement:

- `488b558` — conflict warning guard (never on page at call time)
- `7547130` — panelInStartState removed (correct fix, unrelated)
- `1c81cb4` — unscoped Start Sandbox fallback → triggers `_waitForCredentials` tolerance bug

Each fix exposes the next edge case. The restart path is not reliably testable within the
4-hour sandbox window.

**The user's manual workaround is correct:** delete the portal-only sandbox and start a
new one. The retry loop was automating this but the automation is too fragile.

---

## Fix

Replace the retry loop with a fail-fast error. Remove `_azure_sp_retries`, the while
loop scaffolding, and all `_do_restart` calls. The SP and identity paths are unchanged.
The portal-only path immediately calls `_azure_auth_failed` with a clear action message.

### Change 1 — `bin/acg-credential-test`: replace retry loop with fail-fast

**Exact old block (lines 264–306):**

```bash
# Step 3: validate Azure creds — CLI auth first, portal/TAP only when no CLI path exists
# Retry up to 3 times when portal-only sandbox lacks SP credentials (ACG provisioning gap).
_azure_sp_retries=0
_azure_validate_done=false
while [[ "$_azure_validate_done" == "false" ]]; do
  if grep -q '^AZURE_CLIENT_ID=' "$_tmpout" && grep -q '^AZURE_CLIENT_SECRET=' "$_tmpout"; then
    if _az_sp_valid; then
      printf 'INFO: Azure SP credentials validated (az login + token probe OK)\n' >&2
      _write_azure_credentials
    else
      _azure_auth_failed 'ERROR: Azure CLI auth failed — service-principal credentials invalid after all attempts.'
    fi
    _azure_validate_done=true
  elif grep -q '^AZURE_CLIENT_ID=' "$_tmpout"; then
    if _az_identity_valid; then
      printf 'INFO: Azure identity credentials validated (az login + token probe OK)\n' >&2
    else
      _azure_auth_failed 'ERROR: Azure CLI auth failed — identity credentials invalid after all attempts.'
    fi
    _azure_validate_done=true
  elif grep -q '^AZURE_USERNAME=' "$_tmpout" && grep -q '^AZURE_PASSWORD=' "$_tmpout"; then
    if _az_portal_valid; then
      printf 'INFO: Azure portal credentials validated (az login + token probe OK)\n' >&2
      _azure_validate_done=true
    else
      _azure_sp_retries=$(( _azure_sp_retries + 1 ))
      if (( _azure_sp_retries > 3 )); then
        _azure_auth_failed "ERROR: Azure portal auth failed and SP credentials absent after ${_azure_sp_retries} sandbox restarts — MFA enforcement prevents portal login."
      fi
      printf 'WARN: Azure portal-only sandbox with MFA enforcement — SP not provisioned (attempt %d/3). Restarting sandbox...\n' \
        "$_azure_sp_retries" >&2
      _do_restart "$@"
      _wait_cdp_ready
      _extract_credentials "$@" || {
        printf 'ERROR: Credential extraction failed after restart.\n' >&2
        exit 1
      }
      _print_masked
    fi
  else
    _azure_validate_done=true
  fi
done
```

**Exact new block:**

```bash
# Step 3: validate Azure creds — CLI auth first, portal/TAP only when no CLI path exists
if grep -q '^AZURE_CLIENT_ID=' "$_tmpout" && grep -q '^AZURE_CLIENT_SECRET=' "$_tmpout"; then
  if _az_sp_valid; then
    printf 'INFO: Azure SP credentials validated (az login + token probe OK)\n' >&2
    _write_azure_credentials
  else
    _azure_auth_failed 'ERROR: Azure CLI auth failed — service-principal credentials invalid after all attempts.'
  fi
elif grep -q '^AZURE_CLIENT_ID=' "$_tmpout"; then
  if _az_identity_valid; then
    printf 'INFO: Azure identity credentials validated (az login + token probe OK)\n' >&2
  else
    _azure_auth_failed 'ERROR: Azure CLI auth failed — identity credentials invalid after all attempts.'
  fi
elif grep -q '^AZURE_USERNAME=' "$_tmpout" && grep -q '^AZURE_PASSWORD=' "$_tmpout"; then
  if _az_portal_valid; then
    printf 'INFO: Azure portal credentials validated (az login + token probe OK)\n' >&2
  else
    _azure_auth_failed 'ERROR: Azure portal-only sandbox detected — MFA prevents login (no SP credentials provisioned). Delete this sandbox and start a new one to get SP credentials.'
  fi
fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-credential-test` | Replace retry while-loop with flat if/elif; portal-only + portal-fail → fail-fast |

---

## Rules

- `shellcheck -S warning bin/acg-credential-test` — zero new warnings
- No other files touched
- Do NOT modify `playwright/` or any Node files

---

## Definition of Done

- [ ] `_azure_sp_retries` variable removed
- [ ] `_azure_validate_done` variable and while loop removed
- [ ] `_do_restart`, `_wait_cdp_ready`, `_extract_credentials` calls in portal-only path removed
- [ ] Portal-only + portal-fail calls `_azure_auth_failed` with clear action message
- [ ] SP and identity paths unchanged
- [ ] `shellcheck -S warning bin/acg-credential-test` passes with zero new warnings
- [ ] Committed and pushed to `feat/v0.1.5`
- [ ] memory-bank updated with commit SHA and task status (in k3d-manager repo)

**Commit message (exact):**
```
fix(credential-test): remove portal-only restart loop — replace with fail-fast error
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-credential-test`
- Do NOT commit to `main` — work on `feat/v0.1.5`
- Do NOT touch the SP or identity validation paths
- Do NOT modify `acg_restart.js` or `sandbox.js`
