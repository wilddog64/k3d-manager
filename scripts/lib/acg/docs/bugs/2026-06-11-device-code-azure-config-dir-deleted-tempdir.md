# Bug: device code login uses deleted temp dir as AZURE_CONFIG_DIR — session never persists

**Date:** 2026-06-11
**Repo:** lib-acg
**Branch:** feat/v0.1.5
**File:** `bin/acg-credential-test`
**Introduced by:** 24a89f1

---

## Symptom

`make credential-test PROVIDER=azure` with a portal-only sandbox falls back to device
code flow, user completes browser sign-in, but `az account get-access-token` fails or
credentials are not usable afterward. No error about missing directory — Azure CLI silently
creates a new empty config at the deleted path.

---

## Root Cause

`_az_login_probe_clean` traps `rm -rf "$config_dir"` on RETURN. When username/password
login fails and it returns, the temp dir is deleted. Commit `24a89f1` then uses that same
deleted path as `AZURE_CONFIG_DIR` for both the device code login and the token probe:

```bash
AZURE_CONFIG_DIR="$config_dir" az login --use-device-code ...
AZURE_CONFIG_DIR="$config_dir" az account get-access-token ...
```

Azure CLI either fails to write to the deleted dir or creates a fresh empty one. Either
way the session is discarded on function return — it never reaches `~/.azure`. Subsequent
`az` calls outside this function see no valid session.

The spec (`docs/bugs/2026-06-11-az-portal-mfa-device-code-fallback.md`) deliberately
omitted `AZURE_CONFIG_DIR` from the device code path so credentials write to the default
`~/.azure` and persist.

Additionally, Change 2 from the same spec (update the `_azure_auth_failed` message in
Step 3 to reflect that both auth methods were tried) was not implemented.

---

## Fix

### Change 1 — remove `AZURE_CONFIG_DIR` from device code login and token probe

**Exact old block (lines 182–191 in current file):**

```bash
  printf 'INFO: Username/password login failed (MFA enforcement) — falling back to device code flow.\n' >&2
  printf 'INFO: Open the URL printed below in your browser and enter the code to authenticate.\n' >&2
  AZURE_CONFIG_DIR="$config_dir" az login --use-device-code --tenant "$tenant" --allow-no-subscriptions --output none >/dev/null || {
    AZURE_LOGIN_ERROR='Device code login failed or was cancelled'
    return 1
  }
  AZURE_CONFIG_DIR="$config_dir" az account get-access-token --resource https://management.azure.com/ --output none >/dev/null 2>&1
```

**Exact new block:**

```bash
  printf 'INFO: Username/password login failed (MFA enforcement) — falling back to device code flow.\n' >&2
  printf 'INFO: Open the URL printed below in your browser and enter the code to authenticate.\n' >&2
  az login --use-device-code --tenant "$tenant" --allow-no-subscriptions --output none >/dev/null || {
    AZURE_LOGIN_ERROR='Device code login failed or was cancelled'
    return 1
  }
  az account get-access-token --resource https://management.azure.com/ --output none 2>/dev/null
```

### Change 2 — update `_azure_auth_failed` message in Step 3 portal path

**Exact old line (line 291 in current file):**

```bash
    _azure_auth_failed 'ERROR: Azure portal-only sandbox detected — MFA prevents login (no SP credentials provisioned). Delete this sandbox and start a new one to get SP credentials.'
```

**Exact new line:**

```bash
    _azure_auth_failed 'ERROR: Azure portal-only sandbox — MFA enforcement blocks username/password and device code login failed or was cancelled.'
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-credential-test` | Remove `AZURE_CONFIG_DIR` from device code path; update portal-path error message |

---

## Rules

- `shellcheck -S warning bin/acg-credential-test` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] `AZURE_CONFIG_DIR="$config_dir"` removed from `az login --use-device-code` call
- [ ] `AZURE_CONFIG_DIR="$config_dir"` removed from `az account get-access-token` call
- [ ] `az account get-access-token` stderr redirect changed from `>/dev/null 2>&1` to `2>/dev/null` (stdout carries the token info — only suppress stderr)
- [ ] `_azure_auth_failed` message in Step 3 portal path updated to new wording
- [ ] `shellcheck -S warning bin/acg-credential-test` passes with zero new warnings
- [ ] Committed and pushed to `feat/v0.1.5`
- [ ] memory-bank updated with commit SHA and task status (in k3d-manager repo)

**Commit message (exact):**
```
fix(credential-test): remove AZURE_CONFIG_DIR from device code path — temp dir deleted before use
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-credential-test`
- Do NOT commit to `main` — work on `feat/v0.1.5`
- Do NOT touch `_az_sp_valid`, `_az_identity_valid`, or `_az_login_probe_clean`
- Do NOT add a new `config_dir` for the device code path — it must write to `~/.azure` (no AZURE_CONFIG_DIR override)
