# Issue: `make refresh` unconditionally re-extracts AWS credentials

**Date:** 2026-04-04
**File:** `bin/acg-refresh`
**Severity:** Medium — causes unnecessary Playwright launch and SingletonLock conflict

## Symptom

`make refresh` always runs `acg_get_credentials` regardless of whether AWS credentials
are still valid. When the Chrome CDP launchd agent is running (profile dir locked), this
triggers a `launchPersistentContext` conflict:

```
ERROR: browserType.launchPersistentContext: Failed to create a ProcessSingleton
for your profile directory. This usually means that the profile is already in use
by another instance of Chromium.
```

The primary purpose of `make refresh` is to restart the SSH tunnel. Credential extraction
is only needed when creds are actually expired.

## Root Cause

`bin/acg-refresh` calls `acg_get_credentials` unconditionally. `_acg_check_credentials`
(which calls `aws sts get-caller-identity`) exists and would detect valid creds, but is
not called before extraction.

## Fix

In `bin/acg-refresh`, check credentials first via `_acg_check_credentials`. Skip
`acg_get_credentials` if creds are still valid. Only extract if check fails.

Spec: `docs/plans/v1.0.3-fix-acg-refresh-skip-creds.md`
