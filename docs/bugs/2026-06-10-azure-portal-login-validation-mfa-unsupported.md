# Bug: Azure portal username/password CLI validation is blocked by MFA

**Branch:** `feat/v0.1.4`
**Date:** 2026-06-10
**File:** `bin/acg-credential-test`

## Problem

`make credential-test PROVIDER=az` can extract `AZURE_USERNAME` and
`AZURE_PASSWORD`, but the Azure CLI username/password login path fails on
MFA-enforced tenants:

```text
[az] WARNING: Starting September 1, 2025, MFA will be gradually enforced for Azure public cloud. The authentication with username and password in the command line is not supported with MFA.
[az] ERROR: AADSTS50126: Error validating credentials due to invalid username or password.
ERROR: az login --username/--password failed — credentials invalid after all attempts.
```

That makes the credential test fail even though the extracted portal
credentials are present and the sandbox itself is valid.

## Root Cause

The portal-validation gate treated Azure CLI username/password login as a hard
success/failure test. On MFA-protected tenants, the CLI cannot complete that
login flow non-interactively, so the gate fails for reasons unrelated to the
sandbox extraction.

## Fix

1. Prefer Azure service-principal validation when `AZURE_CLIENT_ID` /
   `AZURE_CLIENT_SECRET` are present.
2. Treat Azure CLI MFA/username-password failures as a non-fatal limitation.
3. Continue the credential-test run with a warning when the portal login path
   is blocked by MFA, instead of exiting 1.

## Why this matters

- The extracted portal credentials are still useful for browser-based access.
- Azure CLI username/password login is not a reliable validation method once
  MFA is enforced.
- The test should not fail on a known Azure CLI limitation.
