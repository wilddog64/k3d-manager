# Bug: acg-credential-test exits immediately when Azure SP validation fails — no restart

**Date:** 2026-06-12
**Branch (lib-acg):** `feat/v0.1.7`
**File:** `bin/acg-credential-test`

---

## Symptom

```
[az] ERROR: AADSTS700016: Application with identifier '<client-id>' was not found in the
directory 'Pluralsight Cloud'. This can happen if the application has not been installed
by the administrator of the tenant or consented to by any user in the tenant.
ERROR: Azure CLI auth failed — service-principal credentials invalid after all attempts.
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
```

All 4 credential fields (Username, Password, Application Client ID, Secret) are populated
in the Pluralsight UI so `_waitForCredentials` returns success — but the extracted service
principal doesn't exist in the Azure AD tenant. `make up CLUSTER_PROVIDER=k3s-azure` fails.

---

## Root Cause

`acg-credential-test` Step 3 (Azure SP validation, lines 300–307) calls `_az_sp_valid`.
When it returns false, `_azure_auth_failed` is called immediately — there is **no restart**.

The AWS path (lines 277–287) already handles this case:
```bash
if ! _sts_valid; then
  _do_restart "$@"
  _wait_cdp_ready
  _extract_credentials "$@" || { ... exit 1; }
```

Azure SP validation has no equivalent recovery. `_do_restart` deletes the sandbox and
starts a new one, which is exactly what is needed when a service principal is invalid in
Azure AD (sandbox recycled/expired, SP already deleted from tenant).

---

## Fix

### Change 1 — `bin/acg-credential-test`: add `_do_restart` recovery to Azure SP validation failure

Mirror the AWS restart pattern at lines 300–307.

**Exact old block (lines 300–307):**

```bash
# Step 3: validate Azure creds — CLI auth first, portal/TAP only when no CLI path exists
if grep -q '^AZURE_CLIENT_ID=' "$_tmpout" && grep -q '^AZURE_CLIENT_SECRET=' "$_tmpout"; then
  if _az_sp_valid; then
    printf 'INFO: Azure SP credentials validated (az login + token probe OK)\n' >&2
    _write_azure_credentials
  else
    _azure_auth_failed 'ERROR: Azure CLI auth failed — service-principal credentials invalid after all attempts.'
  fi
```

**Exact new block:**

```bash
# Step 3: validate Azure creds — CLI auth first, portal/TAP only when no CLI path exists
if grep -q '^AZURE_CLIENT_ID=' "$_tmpout" && grep -q '^AZURE_CLIENT_SECRET=' "$_tmpout"; then
  if _az_sp_valid; then
    printf 'INFO: Azure SP credentials validated (az login + token probe OK)\n' >&2
    _write_azure_credentials
  else
    printf 'WARN: Azure SP validation failed — restarting sandbox for fresh credentials...\n' >&2
    _do_restart "$@"
    _wait_cdp_ready
    _extract_credentials "$@" || {
      printf 'ERROR: Credential extraction failed after SP validation restart.\n' >&2
      exit 1
    }
    _print_masked
    if _az_sp_valid; then
      printf 'INFO: Azure SP credentials validated after restart (az login + token probe OK)\n' >&2
      _write_azure_credentials
    else
      _azure_auth_failed 'ERROR: Azure CLI auth failed — service-principal credentials invalid after all attempts.'
    fi
  fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-credential-test` | Add `_do_restart` + re-extract + re-validate recovery when `_az_sp_valid` returns false |

---

## Rules

- `shellcheck -S warning bin/acg-credential-test` — zero new warnings
- `node --check` not applicable (shell file only)
- No other files touched

---

## Before You Start

- Repo: `lib-acg`
- Branch: `feat/v0.1.7`
- Run: `git pull origin feat/v0.1.7`
- Read: `bin/acg-credential-test` in full
- Confirm lines 300–307 match the exact old block above before editing

---

## Definition of Done

- [ ] Old block (lines 300–307) replaced with new block exactly as written above
- [ ] `printf 'WARN: Azure SP validation failed — restarting sandbox for fresh credentials...\n' >&2` present
- [ ] `_do_restart "$@"` called on SP validation failure
- [ ] `_wait_cdp_ready` called after restart
- [ ] `_extract_credentials "$@"` called with hard exit on failure
- [ ] `_print_masked` called after re-extraction
- [ ] Second `_az_sp_valid` check present with `_write_azure_credentials` on success
- [ ] `_azure_auth_failed` still called on second failure (no infinite loop)
- [ ] `shellcheck -S warning bin/acg-credential-test` passes with zero new warnings
- [ ] No files other than `bin/acg-credential-test` touched
- [ ] Committed and pushed to `feat/v0.1.7`
- [ ] memory-bank in k3d-manager updated with lib-acg commit SHA and task status

**Commit message (exact):**
```
fix(credential-test): restart sandbox on Azure SP validation failure — mirrors AWS restart pattern
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-credential-test`
- Do NOT commit to `main` — work on `feat/v0.1.7` in lib-acg
- Do NOT add a second restart for the identity or portal-only paths — this fix is SP-only
- Do NOT change the error message in the final `_azure_auth_failed` call
