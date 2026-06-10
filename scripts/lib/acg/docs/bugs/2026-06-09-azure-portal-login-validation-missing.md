# Bug: Azure portal username/password not validated after extraction

**Branch:** `feat/v0.1.4`
**Date:** 2026-06-09
**File:** `bin/acg-credential-test`

---

## Problem

The Azure credential-test flow currently extracts `AZURE_USERNAME` and
`AZURE_PASSWORD`, but the validation gate only runs when service-principal
fields (`AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET`) are present. In the live
sandbox output, `make credential-test PROVIDER=az` prints the portal
username/password pair and exits without any `az login` validation message.

**Observed output:**
```text
INFO: Azure credentials already populated — skipping Start/Open flow
INFO: Extracting credentials...
INFO: Found 4 Azure-scoped copyable inputs.
INFO: Detached from Chrome CDP session.
AZURE_USERNAME=***
AZURE_PASSWORD=***
```

**Root cause:** the Azure validation block at the end of
`bin/acg-credential-test` only checks for `AZURE_CLIENT_ID` before calling
`az login --service-principal`. When the sandbox only exposes portal
username/password credentials, the validation gate is skipped entirely.

---

## Fix

### `bin/acg-credential-test`: validate Azure portal username/password with `az login`

Add a portal-login helper that:

- reads `AZURE_USERNAME` and `AZURE_PASSWORD` from `$_tmpout`
- discovers `AZURE_TENANT_ID` from the username domain via OIDC if it is not
  already present
- runs:
  ```bash
  az login --username "$username" --password "$password" --tenant "$tenant" --allow-no-subscriptions --output none
  ```
- on success, prints an INFO line and the active account name
- on failure, restarts the sandbox once and retries extraction/validation

Keep the service-principal validation helper as a fallback for sandboxes that
actually expose `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET`.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-credential-test` | Add Azure portal username/password validation gate using `az login --username ... --password ...` |

---

## Rules

- `shellcheck -S warning bin/acg-credential-test` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] Azure portal username/password path runs `az login --username ... --password ...`
- [ ] Azure portal validation prints an INFO line on success
- [ ] Validation retries once after sandbox restart on failure
- [ ] `shellcheck -S warning bin/acg-credential-test` passes
- [ ] Committed and pushed to `feat/v0.1.4`

**Commit message (exact):**
```text
fix(credential-test): validate Azure portal creds with az login after extraction
```
