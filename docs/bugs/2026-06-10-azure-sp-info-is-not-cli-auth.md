# Bug: Azure SP metadata should not override portal/TAP credential validation

**Branch:** `feat/v0.1.4`
**Date:** 2026-06-10
**File:** `bin/acg-credential-test`

## Problem

The Azure sandbox now exposes both portal credentials and Azure SP-looking
fields (`Application Client ID` / `Secret`) in the same run. The extracted SP
values are not a reliable CLI auth path in this TAP/user-account sandbox. When
`bin/acg-credential-test` prefers SP validation first, it can fail with:

```text
[az] ERROR: AADSTS700016: Application with identifier '...'
was not found in the directory 'Pluralsight Cloud'.
```

That makes the test reject a sandbox that still contains usable portal/TAP
credentials.

## Root Cause

The validator treated SP metadata as the primary Azure CLI auth path whenever
`AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET` were present. In this sandbox
model, those fields are informational and may not map to a usable Azure AD app
for `az login --service-principal`.

## Fix

1. Prefer portal/TAP validation when `AZURE_USERNAME` / `AZURE_PASSWORD` are
   present.
2. Treat SP fields as secondary metadata unless the portal path is absent.
3. Keep the isolated `AZURE_CONFIG_DIR` and `az account get-access-token`
   probe so the validator only reports success after a real token is issued.

## Why this matters

- The sandbox can hide or show SP details inconsistently.
- Portal/TAP credentials remain the most reliable automation input.
- ACLI validation must not fail just because the sandbox displays SP-like
  fields that are not usable for this tenant.
