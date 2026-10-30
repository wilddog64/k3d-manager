# Bug: webhook doctor hides recurring Keychain access blocks behind generic auth failure

**Status:** VERIFIED — offline fixtures passed; live locked-keychain check passed 2026-10-29; unlock-then-recheck pending (operator tmux)
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

## Live evidence — 2026-10-29 (Claude, read-only)

Locked half: run from Claude's session, where `security show-keychain-info` on the login keychain returns `User interaction is not allowed`. `make webhook-doctor` exited 0 in 0.23 s with `classification: keychain_interaction_required`, credential `status: interaction_required` (`lookup_exit` 36), `health.status: auth_unavailable` with `http_responsive: false`, the explicit unlock instruction, "HTTP health was not tested", `recovery_recommended: false` and `recovery_action: null`. Launchd, listener, process and log fields all reported healthy (pid 87282, port 7443). This matches the fix: the access block is named, and no restart is suggested.

Remaining: the unlock half. The operator unlocks in a GUI-capable shell (tmux) and reruns `make webhook-doctor`; the next check must report the credential available and HTTP healthy, without token caching. Claude's session cannot run this half; `!` commands run in the same non-GUI context.
