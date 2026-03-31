# Issue: Pluralsight Session Expiry Independent of Sandbox TTL

**Date:** 2026-03-31
**Milestone:** v1.0.2
**Severity:** Medium — blocks automated credential extraction; requires manual intervention

---

## Symptom

Chrome opens on the local machine and the Pluralsight page switches to the sign-in page
mid-session, even though:
- The ACG sandbox was recently extended (`acg_extend` / `antigravity_acg_extend` ran)
- The EC2 instances are still `Running`
- AWS credentials were recently valid

`acg_get_credentials` triggers the Playwright sign-in flow but cannot complete it
automatically, requiring the user to manually provide credentials to the agent.

---

## Root Cause

Two independent session timers exist:

| Timer | What expires | Detectable by `acg_watch`? |
|---|---|---|
| Sandbox TTL (~4h) | ACG sandbox — EC2 instances terminated, AWS creds invalid | No — UI only |
| Pluralsight browser session (~few hours) | Login cookie in `acg-chrome-profile` | No |

`acg_watch` only monitors EC2 instance existence (`_acg_get_instance_id`). It has no
visibility into the Pluralsight browser session. The sandbox can be alive and extended
while the browser session has independently expired.

When the Playwright script (`acg_credentials.js`) connects via CDP and finds the sign-in
page, it attempts auto sign-in (lines 70–119) by:
1. Filling email from `PLURALSIGHT_EMAIL` env var
2. Waiting for Google Password Manager to auto-fill the password

Google Password Manager auto-fill requires a real user gesture in many browser
configurations and does not fire reliably in a CDP-controlled session. Result: sign-in
stalls and the user must intervene manually.

---

## Impact

- Gemini tasks that call `acg_get_credentials` mid-session block on sign-in
- User must manually extend + provide credentials, defeating the automation goal
- Observed during v1.0.2 Gemini e2e run (2026-03-31)

---

## Workarounds (current)

1. Set `PLURALSIGHT_EMAIL` env var before running — fills email field automatically
2. Manually complete sign-in in the Chrome window when the page appears — Playwright
   detects the redirect back to `app.pluralsight.com` and continues
3. Keep the Chrome window visible during long Gemini sessions so session stays warm

---

## Proposed Fixes

**Short term (no code change):**
- Document that `PLURALSIGHT_EMAIL` must be set and Pluralsight credentials must be
  saved in `acg-chrome-profile` Chrome's password manager before running automated tasks

**Medium term:**
- Add `PLURALSIGHT_PASSWORD` env var support to `acg_credentials.js` — fill both fields
  directly without relying on Password Manager
  - Security tradeoff: secret in env; acceptable for local dev use
  - Guard: only fill if `PLURALSIGHT_PASSWORD` is set; never log or echo the value

**Proper fix (v1.0.3 candidate):**
- `acg_watch` should detect Pluralsight session health by probing the sandbox page via
  CDP, not just EC2 instance existence
- If session expired: warn user to re-authenticate before the next automated task runs
- Probe interval: every 30 minutes (much shorter than the 3.5h extend interval)

---

## Related

- `docs/issues/2026-03-28-argocd-sync-acg-credentials-expired.md` — similar issue where
  expired credentials broke ArgoCD sync mid-session
- `acg_watch` TTL detection gap — `acg_watch` fires on a fixed 3.5h timer regardless of
  actual TTL remaining; if started late it may not extend in time
