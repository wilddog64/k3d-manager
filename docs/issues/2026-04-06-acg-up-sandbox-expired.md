---
date: 2026-04-06
component: acg.sh / _acg_check_credentials
symptom: make up fails silently when sandbox expired and removed
status: fix-ready (spec: docs/plans/v1.0.4-bugfix-acg-up-sandbox-expired.md)
agent: Codex
---

# Issue: `make up` fails with unhelpful error when ACG sandbox is expired/removed

## Symptom

When an ACG sandbox has expired and been removed by Pluralsight:
1. User runs `make up`
2. `_acg_check_credentials` fails — AWS credentials from the old sandbox are invalid
3. Error message: `"AWS credentials invalid or expired. Update ~/.aws/credentials from the ACG console."`
4. User doesn't know they need to **start a new sandbox first** before getting credentials
5. User must figure this out manually, go to Pluralsight, click "Start Sandbox", then re-run `acg_get_credentials`

The error message is misleading — it implies credentials just need to be refreshed, but a
sandbox that was **removed** requires starting an entirely new one first.

## Root Cause

`_acg_check_credentials` (`scripts/plugins/acg.sh` line 39–47) detects credential failure
but doesn't distinguish between:
- **Expired token** (sandbox running, token refreshed via ACG console)
- **Sandbox removed** (sandbox gone, user must start a new one at Pluralsight)

Both cases produce the same AWS error, but require different remediation steps.
The current message only describes the token-refresh path.

## Files Involved

| File | Issue |
|------|-------|
| `scripts/plugins/acg.sh` | `_acg_check_credentials` error message (line 43) not actionable for expired sandbox |

## Fix

Update the error message to explicitly describe both remediation paths, including the
"start new sandbox" step. See `docs/plans/v1.0.4-bugfix-acg-up-sandbox-expired.md`.
