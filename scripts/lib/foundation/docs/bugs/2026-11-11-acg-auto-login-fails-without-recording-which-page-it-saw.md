# Bug: ACG unattended login fails with `ACG_LOGIN_FIELDS_MISSING` and records nothing about the page it saw

**Status:** OPEN — fix on `release/v0.5.6`; verification pending
**Priority:** P2 — `/cluster-up aws` from Slack fails at step 1 whenever the Pluralsight session lapses; workaround: sign in by hand on the host's CDP Chrome and rerun

**Branch:** `release/v0.5.6`
**Repo:** `lib-foundation` (standalone — NOT the k3d-manager subtree copy)
**Full spec:** k3d-manager `docs/bugs/2026-11-11-acg-auto-login-fails-without-recording-which-page-it-saw.md`

## Files

- `scripts/lib/acg/playwright/lib/pluralsight_login.js`
- `scripts/lib/acg/acg_session_check.js`
- `scripts/lib/acg/tests/providers/pluralsight_login.test.js`
- `scripts/lib/acg/tests/providers/acg_session_check.test.js`
- `docs/bugs/2026-11-11-acg-auto-login-fails-without-recording-which-page-it-saw.md`

## Summary

The root cause of the missing sign-in fields is still unknown. This change makes the next failure explain itself:

- `loginWithPage` prints one redacted `ACG_LOGIN_DIAG:` line on `login_form_unavailable` and `login_failed`: URL without query or fragment, title, Cloudflare challenge flag, selector counts, signed-in/out state.
- On `login_form_unavailable` (no credential typed) it saves a mode-0600 screenshot under `${XDG_STATE_HOME:-~/.local/state}/k3d-manager/acg-diag/`, keeping the newest 5.
- `ACG_SESSION_EXPIRED` gains `reason=<login reason>` (`no_attempt` when no credentials exist).
