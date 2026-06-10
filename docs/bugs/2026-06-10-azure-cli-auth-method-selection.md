# Bug: Azure credential-test must prefer CLI auth methods over portal/TAP fallback

**Branch:** `feat/v0.1.4`
**Date:** 2026-06-10
**File:** `bin/acg-credential-test`

## Problem

The Azure sandbox can expose OAuth-style metadata that is meant for CLI
authentication:

- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- sometimes a managed-identity style `AZURE_CLIENT_ID` path with no secret

When `bin/acg-credential-test` falls back to portal/TAP first, it can fail on
`AADSTS50126` even though the sandbox is actually providing a usable CLI auth
path. Likewise, it can print misleading success information if the wrong
credential branch is selected first.

## Root Cause

The validator treated the browser portal login as the primary Azure auth path
even when the sandbox exposed CLI-oriented auth metadata. That makes the test
choose the wrong login method and hides the actual auth failure mode.

## Fix

1. Prefer `az login --service-principal` when both `AZURE_CLIENT_ID` and
   `AZURE_CLIENT_SECRET` are present.
2. If only `AZURE_CLIENT_ID` is available, try `az login --identity --client-id`.
3. Fall back to portal/TAP only when no CLI auth path is available.
4. Keep the isolated `AZURE_CONFIG_DIR` and `az account get-access-token` probe
   so success is only reported after a real access token is issued.

## Why this matters

- The sandbox can expose both browser and CLI auth metadata at the same time.
- The validator needs to test the CLI path first when the sandbox supplies it.
- Portal/TAP login is a fallback, not the primary proof of Azure CLI auth.
