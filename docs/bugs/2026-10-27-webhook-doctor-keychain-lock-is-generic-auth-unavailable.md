# Bug: webhook doctor hides recurring Keychain access blocks behind generic auth failure

**Status:** VERIFIED — explicit credential diagnostics implemented; offline fixtures passed
**Priority:** P2
**Filed:** 2026-10-27, operator requested recurring-lock handling
**Branch:** `k3d-manager-v1.43.9`
**Fix commit:** `1ff3b09b2bda92fc20125253f5c7b365db320e46`
**Related:** `docs/bugs/2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery.md`

The doctor reported only auth_unavailable while the operator's login Keychain
was locked, obscuring the actionable access issue. Manual unlock restored
the existing credential. The doctor should account for this common state
without automatically unlocking or weakening lock policy.

Now distinguishes keychain_interaction_required from missing reader credential
and bounded command failure states, exposes sanitized credential/action fields,
and leaves HTTP unknown without credentials. No unwarranted recovery_action
is shown. An unlock is observed on the next check without token caching.

Four pre-fix regression failures; final31 Python +5 BATS, Ruff, dry-run,
audit/lint/hooks pass. No live credential/lock/service changes were performed.
[Full evidence](../issues/2026-10-27-webhook-doctor-keychain-aware-auth.md).
