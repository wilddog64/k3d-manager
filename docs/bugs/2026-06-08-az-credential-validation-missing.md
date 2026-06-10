# Bug: Azure credentials not validated after extraction (no az login gate)

**Branch:** `feat/v0.1.4`
**Date:** 2026-06-08
**File:** `bin/acg-credential-test`

---

## Problem

After successful Azure credential extraction, the script exits 0 without validating
the credentials. AWS credentials are validated via `sts:GetCallerIdentity`; Azure has
no equivalent gate. Stale or wrong credentials pass silently.

**Root cause:** Lines 110–134 in `bin/acg-credential-test` validate AWS only.
No `az login --service-principal` block exists for the Azure path.

---

## Fix

### `bin/acg-credential-test`: add `_az_sp_valid` helper + Azure validation gate

**Exact old block (lines 84–87):**

```bash
_sts_valid() {
  grep -q '^AWS_ACCESS_KEY_ID=' "$_tmpout" &&
    AWS_CONFIG_FILE=/dev/null aws sts get-caller-identity >/dev/null 2>&1
}
```

**Exact new block:**

```bash
_sts_valid() {
  grep -q '^AWS_ACCESS_KEY_ID=' "$_tmpout" &&
    AWS_CONFIG_FILE=/dev/null aws sts get-caller-identity >/dev/null 2>&1
}

_az_sp_valid() {
  local client_id tenant secret
  client_id=$(grep '^AZURE_CLIENT_ID=' "$_tmpout" | cut -d= -f2-)
  tenant=$(grep '^AZURE_TENANT_ID=' "$_tmpout" | cut -d= -f2-)
  secret=$(grep '^AZURE_CLIENT_SECRET=' "$_tmpout" | cut -d= -f2-)
  [[ -n "$client_id" && -n "$tenant" && -n "$secret" ]] || return 1
  az login --service-principal \
    -u "$client_id" \
    -p "$secret" \
    --tenant "$tenant" \
    --output none 2>/dev/null
}
```

**Exact old block (line 134 — end of file):**

```bash
fi
```

**Exact new block:**

```bash
fi

# Step 3: if Azure SP creds present, validate with az login --service-principal
if grep -q '^AZURE_CLIENT_ID=' "$_tmpout"; then
  if ! _az_sp_valid; then
    printf 'WARN: az login --service-principal failed — restarting sandbox for fresh credentials...\n' >&2
    _do_restart "$@"
    _wait_cdp_ready
    _extract_credentials "$@" || {
      printf 'ERROR: Credential extraction after restart failed.\n' >&2
      exit 1
    }
    _print_masked
  fi
  if _az_sp_valid; then
    printf 'INFO: Azure SP credentials validated (az login OK)\n' >&2
    printf 'INFO: Subscriptions:\n' >&2
    az account list --output table 2>/dev/null >&2 || true
  else
    printf 'ERROR: az login --service-principal failed — credentials invalid after all attempts.\n' >&2
    exit 1
  fi
fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-credential-test` | Add `_az_sp_valid` helper + Azure SP validation gate matching AWS pattern |

---

## Rules

- `shellcheck -S warning bin/acg-credential-test` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] `_az_sp_valid` function present above `_sts_valid`
- [ ] Azure gate block present after the AWS gate (line ~134)
- [ ] `shellcheck -S warning bin/acg-credential-test` passes
- [ ] Committed and pushed to `feat/v0.1.4`

**Commit message (exact):**
```
fix(credential-test): validate Azure SP credentials with az login after extraction
```
