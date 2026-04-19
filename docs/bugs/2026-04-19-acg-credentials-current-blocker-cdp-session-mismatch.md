# Bug: ACG credential extraction is currently blocked by CDP/session mismatch, not the old singleton lock

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/playwright/acg_credentials.js`, `scripts/plugins/gcp.sh`, `scripts/plugins/acg.sh`

---

## Summary

Two older findings remain valid, but they do **not** fully describe the current live failure mode:

- `3b3d4071` correctly documented the historical `ProcessSingleton`/profile-lock failure.
- `edf498ad` correctly extended the stability hardening plan with IDP safety measures.

However, the current blocker reported in live runs is different:

```text
INFO: [gcp] Chrome is running without CDP. It must be restarted to enable --remote-debugging-port=9222.
...
ERROR: [gcp] Timed out waiting for Chrome CDP on port 9222
```

and later:

```text
ERROR: [gcp] Chrome is running without CDP; it cannot be fixed automatically.
```

This means the active issue is now **CDP attach/session-state reliability**:

1. Chrome may already be running without remote debugging enabled.
2. The automation depends on attaching to a CDP-enabled browser that shares the user's real logged-in session.
3. If CDP cannot attach to that browser, Playwright cannot reliably inspect the already-authenticated ACG state.
4. The old singleton-lock issue may still be a historical risk, but it is **not** the primary root cause of the current failures.

---

## What is still correct from the older findings

### Historical finding: `3b3d4071`

Still correct as historical RCA:

- `process.exit(1)` could bypass cleanup.
- stale persistent-profile locks could break later runs.
- shared profile usage amplified failures across AWS/GCP flows.

### Plan finding: `edf498ad`

Still correct as hardening guidance:

- single-session discipline is desirable;
- jitter can reduce bot-like interaction patterns;
- Auth0 / suspicious-activity detection should fail fast with clear messaging.

---

## Current Root Cause

The current live failures are caused by **a mismatch between the browser session the user sees and the browser session the automation can actually control**.

More specifically:

1. **CDP dependency**
   - `acg_credentials.js` now relies on Chrome CDP instead of isolated persistent profiles.
   - This is correct for session reuse, but it makes the workflow depend on a healthy CDP endpoint.

2. **Browser-state ambiguity**
   - The user may already have Chrome open and logged into Pluralsight/ACG.
   - But that Chrome instance may not expose `--remote-debugging-port=9222`.
   - From the user's perspective, "Chrome is open and logged in" looks healthy.
   - From the automation's perspective, that session is unreachable.

3. **Relaunch friction on macOS**
   - Attempting to repair this automatically by killing/restarting Chrome is destructive and unreliable.
   - Attempting to wait for CDP after a relaunch may still fail due to timing, app restore behavior, or launch semantics.

4. **Session-validity ambiguity**
   - Even when CDP is available, the attached tab may still be on `/id`, an intermediate landing page, or another stale auth state.
   - This creates a second class of failure: CDP is reachable, but the authenticated ACG state is not yet usable.

---

## Recommended Fix Direction

Do **not** treat the problem as only a profile-lock issue.

Instead, fix the workflow around these principles:

1. **Single authoritative browser launcher**
   - one helper owns Chrome/CDP detection and launch instructions;
   - all ACG/Playwright entry points use it.

2. **Explicit session contract**
   - if Chrome is running without CDP, print the exact recovery command and stop;
   - do not pretend the session is automatable.

3. **Post-attach health checks**
   - once CDP attaches, verify the active tab/session is actually usable for ACG extraction;
   - distinguish between:
     - no CDP,
     - CDP attached but user not signed in,
     - CDP attached but session stranded on `/id` or another intermediary.

4. **Provider-neutral behavior**
   - AWS and GCP should use the same browser/session orchestration path so one provider does not silently diverge from the other.

---

## Impact

This issue blocks both AWS and GCP credential extraction whenever the visible browser session cannot be reused via CDP. It also causes confusion because historical bug docs appear relevant while the active failure has shifted to a different layer of the system.
