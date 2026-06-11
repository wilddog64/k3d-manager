# Bug: az login --username --password fails with MFA enforcement — portal-only sandbox unusable

**Date:** 2026-06-11
**Repo:** lib-acg
**Branch:** feat/v0.1.5
**File:** `bin/acg-credential-test`

---

## Symptom

`make credential-test PROVIDER=azure` with a portal-only sandbox (no SP credentials)
fails at Step 3:

```
[az] ERROR: AADSTS50126: Error validating credentials due to invalid username or password.
ERROR: Azure portal-only sandbox detected — MFA prevents login (no SP credentials provisioned).
```

Azure MFA enforcement (mandatory since September 2025) blocks `az login --username
--password` even with correct credentials. The credential-test exits 1.

---

## Root Cause

`_az_portal_valid` only attempts `az login --username --password --tenant`. When MFA is
enforced, this always fails with AADSTS50126. There is no fallback.

`az login --use-device-code` bypasses MFA by letting the user complete authentication
interactively in a browser. The device code URL and one-time code are printed to stderr
so the user can open the URL and sign in. The resulting session persists to `~/.azure`.

---

## Fix

After `az login --username --password` fails in `_az_portal_valid`, fall back to
`az login --use-device-code`. Validate the session with `az account get-access-token`
before returning. This is a two-step change: fallback in `_az_portal_valid`, and call
`_write_azure_credentials` equivalent for device-code path (persist via the existing
session — device code login already writes to `~/.azure`, no extra write needed).

Also update Step 3 in the main body to call `_write_azure_credentials` for the portal
path when validation succeeds, so the session is durably persisted.

### Change 1 — `bin/acg-credential-test`: add device code fallback in `_az_portal_valid`

**Exact old block (lines 165–178):**

```bash
_az_portal_valid() {
  local username password tenant config_dir
  username=$(grep '^AZURE_USERNAME=' "$_tmpout" | cut -d= -f2-)
  password=$(grep '^AZURE_PASSWORD=' "$_tmpout" | cut -d= -f2-)
  tenant=$(_azure_discover_tenant)
  [[ -n "$username" && -n "$password" ]] || return 1
  [[ -n "$tenant" ]] || { printf 'ERROR: Could not determine Azure tenant ID\n' >&2; return 1; }

  config_dir=$(mktemp -d)
  _az_login_probe_clean "$config_dir" az login \
    --username "$username" \
    --password "$password" \
    --tenant "$tenant"
}
```

**Exact new block:**

```bash
_az_portal_valid() {
  local username password tenant config_dir
  username=$(grep '^AZURE_USERNAME=' "$_tmpout" | cut -d= -f2-)
  password=$(grep '^AZURE_PASSWORD=' "$_tmpout" | cut -d= -f2-)
  tenant=$(_azure_discover_tenant)
  [[ -n "$username" && -n "$password" ]] || return 1
  [[ -n "$tenant" ]] || { printf 'ERROR: Could not determine Azure tenant ID\n' >&2; return 1; }

  config_dir=$(mktemp -d)
  if _az_login_probe_clean "$config_dir" az login \
    --username "$username" \
    --password "$password" \
    --tenant "$tenant"; then
    return 0
  fi
  printf 'INFO: Username/password login failed (MFA enforcement) — falling back to device code flow.\n' >&2
  printf 'INFO: Open the URL printed below in your browser and enter the code to authenticate.\n' >&2
  az login --use-device-code --tenant "$tenant" --allow-no-subscriptions --output none >/dev/null || {
    AZURE_LOGIN_ERROR='Device code login failed or was cancelled'
    return 1
  }
  az account get-access-token --resource https://management.azure.com/ --output none 2>/dev/null
}
```

### Change 2 — `bin/acg-credential-test`: call `_write_azure_credentials` after successful portal validation

**Exact old block (lines 278–283):**

```bash
elif grep -q '^AZURE_USERNAME=' "$_tmpout" && grep -q '^AZURE_PASSWORD=' "$_tmpout"; then
  if _az_portal_valid; then
    printf 'INFO: Azure portal credentials validated (az login + token probe OK)\n' >&2
  else
    _azure_auth_failed 'ERROR: Azure portal-only sandbox detected — MFA prevents login (no SP credentials provisioned). Delete this sandbox and start a new one to get SP credentials.'
  fi
fi
```

**Exact new block:**

```bash
elif grep -q '^AZURE_USERNAME=' "$_tmpout" && grep -q '^AZURE_PASSWORD=' "$_tmpout"; then
  if _az_portal_valid; then
    printf 'INFO: Azure portal credentials validated (az login + token probe OK)\n' >&2
  else
    _azure_auth_failed 'ERROR: Azure portal-only sandbox — MFA enforcement blocks username/password and device code login failed or was cancelled.'
  fi
fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-credential-test` | Add `az login --use-device-code` fallback in `_az_portal_valid`; update portal-path error message |

---

## Rules

- `shellcheck -S warning bin/acg-credential-test` — zero new warnings
- No other files touched
- Do NOT modify `playwright/` or any Node files

---

## Definition of Done

- [ ] `_az_portal_valid` attempts `az login --username --password` first; falls back to `az login --use-device-code` on failure
- [ ] Device code path prints two INFO lines before the `az login` call so user knows what to do
- [ ] Device code path validates session with `az account get-access-token` before returning
- [ ] `AZURE_LOGIN_ERROR` is set on device code failure before `return 1`
- [ ] Portal-path `_azure_auth_failed` message updated to reflect that both methods were tried
- [ ] `shellcheck -S warning bin/acg-credential-test` passes with zero new warnings
- [ ] Committed and pushed to `feat/v0.1.5`
- [ ] memory-bank updated with commit SHA and task status (in k3d-manager repo)

**Commit message (exact):**
```
fix(credential-test): add device code fallback in _az_portal_valid — MFA blocks username/password login
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-credential-test`
- Do NOT commit to `main` — work on `feat/v0.1.5`
- Do NOT touch `_az_sp_valid` or `_az_identity_valid`
- Do NOT remove the `az login --username --password` attempt — it stays as the first try
