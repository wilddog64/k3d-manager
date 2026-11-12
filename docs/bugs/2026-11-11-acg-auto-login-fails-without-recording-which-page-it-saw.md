# Bug: ACG unattended login fails with `ACG_LOGIN_FIELDS_MISSING` and records nothing about the page it saw

**Status:** OPEN
**Priority:** P2 — `/cluster-up aws` from Slack fails at step 1 whenever the Pluralsight session lapses; workaround: sign in by hand on the M5's CDP Chrome (:9222) and rerun
**Waiting on:** operator decision — since 2026-11-12 (capture-first triage; nothing dispatched)
**Introduced by:** unknown
**Should have been caught by:** live check
**Severity:** medium — unattended cluster-up depends on a human at the M5's screen every few days; each recurrence of this flow is diagnosed by guessing
**Approval:** operator 2026-11-11: "can you investigate this and file bug if necessary"
**Intent approved:** operator, 2026-11-11 ("approve ACG auto-login P2")
**Prior art:** `scripts/lib/foundation/docs/bugs/2026-09-24-acg-pluralsight-login-click-preconditions.md`, `2026-09-12-acg-signin-wait-targets-dead-id-pluralsight-host.md`, `2026-09-12-acg-session-check-false-green-on-signed-out-page.md`, `2026-07-07-acg-session-check-render-race-false-negative.md` — read, same flow, different root causes, all FIXED; this is the fifth failure of the flow and the first filed for missing diagnostics (`make find-similar-docs` not run: vector store unreachable from the M4)
**Filed:** 2026-11-11
**Detected by:** Claude, reviewing operator Slack job `eebeb490` on the M5
**Affected:** lib-foundation `scripts/lib/acg/playwright/lib/pluralsight_login.js` (`loginWithPage`, `:108-143`), `scripts/lib/acg/acg_session_check.js` (`_main`, `:53-107`)
**Branch:** `k3d-manager-v1.43.15` (spec); fix lands upstream in lib-foundation first, then subtree pull
**Release:** carried to v1.44.0 unless it lands in v1.43.15 — operator 2026-11-11: "sounds good" (to keeping P2 and carrying it). Workaround: sign in by hand on the M5's CDP Chrome; M5 job history shows one lapse in 9 days between uses (`7bd85dcc` 2026-11-01 OK, `eebeb490` 2026-11-10 expired), and auto-login has never succeeded on the M5

## Observed (M5, 2026-11-11, job output `~/.local/share/k3d-manager/webhook-jobs/eebeb490/output`)

    INFO: [acg] Reusing existing CDP browser on :9222
    INFO: Checking Pluralsight (ACG) session in Antigravity browser...
    ACG_CREDENTIALS: username=<present> password=<present>
    INFO: Session not authenticated — attempting headless Pluralsight login...
    ACG_LOGIN_FIELDS_MISSING: email=missing password=<…>
    INFO: headless auto-login did not succeed.
    ACG_SESSION_EXPIRED: Pluralsight session not authenticated and auto-login unavailable — sign in on the host CDP Chrome (http://127.0.0.1:9222) and re-run.

- `loginWithPage` went to `https://app.pluralsight.com/id/signin`, and no element matching `EMAIL_SELECTOR` became visible within 15 s.
- About 8 minutes later the CDP Chrome's only tab was `https://app.pluralsight.com/library/`, "Home | Pluralsight" (read-only `GET :9222/json/list`). Chrome had been running since 2026-11-08 08:17.
- The operator then signed in by hand. The rerun, job `c998511f` (02:27Z), printed `ACG_SESSION_OK path=existing-session`, so `LOGGED_IN_SELECTORS` do match a signed-in page.
- An anonymous GET of `/id/signin` from the M4 returns HTTP 200: a 3,021-byte Cloudflare-served page with no `<input>` and a `challenge-platform` reference. That fits a JavaScript shell or a bot check alike, and curl cannot tell them apart.

## Root cause

**Not established.** What the browser showed at the moment of failure is unknown, because nothing records it. Candidates:
1. A Cloudflare challenge on a cold navigation, which the CDP session cannot clear (memory `reference_acg_stale_tab_invalid_creds`, 2026-07-18).
2. A changed sign-in form whose email input matches none of the arms of `EMAIL_SELECTOR`.
3. A redirect to a signed-out page with no form.

The fix below is therefore diagnostics first. The next recurrence names its cause, and a follow-up fixes that cause.

## Fix (lib-foundation)

1. **Diagnostic line.** In `loginWithPage`, on the `login_form_unavailable` and `login_failed` paths, before returning, print one line to stderr:
   `ACG_LOGIN_DIAG: reason=<reason> url=<origin+path, query and fragment dropped> title=<page title, at most 80 chars, newlines removed> challenge=<yes|no> email_matches=<n> password_matches=<n> signed_out=<yes|no> logged_in=<yes|no>`.
   - `challenge=yes` when the title matches `/just a moment|attention required/i`, or an `iframe[src*="challenges.cloudflare.com"]` exists.
   - The counts are `page.locator(SELECTOR).count()`.
2. **Screenshot.** On `login_form_unavailable` only (no field has been filled), save `page.screenshot()` to `${XDG_STATE_HOME:-$HOME/.local/state}/k3d-manager/acg-diag/login-<UTC yyyymmddThhmmssZ>.png`:
   - create the directory with mode 0700 and the file with mode 0600;
   - keep the newest 5 files;
   - add `screenshot=<path>` to the diagnostic line.
   - A screenshot failure prints `screenshot=failed` and never changes the return value.
3. **Reason on the final message.** In `acg_session_check.js`, the `ACG_SESSION_EXPIRED:` line gains ` reason=<reason>`. The reason is the `loginWithPage` result reason (`login_form_unavailable`, `mfa_required`, `login_failed`, `no_creds`), or `no_attempt` when no credentials exist. `_autoLogin` returns the result object, not only `ok`. The thrown `Error('ACG_SESSION_EXPIRED')` message is unchanged.

## Files (lib-foundation)

- `scripts/lib/acg/playwright/lib/pluralsight_login.js`
- `scripts/lib/acg/acg_session_check.js`
- `scripts/lib/acg/tests/providers/pluralsight_login.test.js`
- `scripts/lib/acg/tests/providers/acg_session_check.test.js`
- `docs/bugs/2026-11-11-acg-auto-login-fails-without-recording-which-page-it-saw.md` (short mirror pointing here)

## Contract readers

The stderr markers `ACG_SESSION_EXPIRED`, `ACG_LOGIN_FIELDS_MISSING` and `ACG_LOGIN_MFA_REQUIRED`, plus the new `ACG_LOGIN_DIAG` (found with `git grep -n -E "ACG_SESSION_EXPIRED|ACG_LOGIN_"` outside docs):
- `acg_session_check.js:48,105-106` and `pluralsight_login.js:123` — **writers**. They change: a `reason=` field is appended, and a new DIAG line is added. The prefixes are unchanged.
- `scripts/lib/acg/playwright/acg_pluralsight_login.js:39` — **writer** of `ACG_LOGIN_MFA_REQUIRED`. Unchanged.
- `tests/providers/acg_session_check.test.js:66,79,118` and `tests/providers/pluralsight_login.test.js:108` — read with `toThrow('ACG_SESSION_EXPIRED')` / `stringContaining(...)`. Unchanged: prefix matches still hold.
- k3d-manager `scripts/plugins/e2e.sh:441` — mentions the session check in prose only; it does not parse the markers. Unchanged.
- k3d-manager webhook failure notes (`failure.md`) take their signature from the `make` exit, not these lines. Unchanged.
- New path `~/.local/state/k3d-manager/acg-diag/` — **writer**: this fix. No readers.

## Do not

- Print or screenshot anything after a field has been filled. Print no cookies, no page text other than the title, and no credential value or length.
- Change `EMAIL_SELECTOR`, `LOGGED_IN_SELECTORS`, the timeouts, or the login flow. The cause is unknown, so don't guess at it.
- Edit `scripts/lib/foundation/` in k3d-manager. Fix in lib-foundation on its own branch, not `feat/run-parallel`.

## Acceptance

```yaml
must:
  - id: M1
    text: "when no email field appears on the sign-in page, stderr has one ACG_LOGIN_DIAG line with reason=login_form_unavailable, url without query string, title, challenge, email_matches=0, and a screenshot path that exists with mode 0600"
  - id: M2
    text: "when the page title is 'Just a moment...' the DIAG line says challenge=yes (paired control: a plain sign-in page says challenge=no)"
  - id: M3
    text: "ACG_SESSION_EXPIRED line carries reason=<loginWithPage reason>, or reason=no_attempt when no credentials exist; the thrown error message stays 'ACG_SESSION_EXPIRED'"
  - id: M4
    text: "at most 5 screenshots are kept in the acg-diag directory"
must_not:
  - id: N1
    text: "the DIAG line or any screenshot is produced after a credential field was filled (login_failed path prints DIAG without screenshot=)"
  - id: N2
    text: "the DIAG line contains the username, the password, a cookie, or a URL query string (fixture URL carries ?token=SENTINEL and the username SENTINEL_USER; neither appears in stderr)"
  - id: N3
    text: "a screenshot error changes loginWithPage's return value or throws"
  - id: N4
    text: "a successful login (existing-session or auto-login) prints an ACG_LOGIN_DIAG line"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    kind: offline
    intent: "lib-foundation's own tests drive the login code against fake pages: when the sign-in form is missing it writes one line naming the page and saves a picture, flags a Cloudflare check, never shows a username, password or query string, and stays silent when login works"
  - id: E2
    proves: [M1, M3]
    kind: live
    intent: "the next time the Pluralsight session lapses on the M5, the Slack cluster-up output shows a DIAG line and a screenshot that tell us which page the browser saw, so the follow-up fix targets the real cause"
interface:
  - "lib-foundation: loginWithPage(page, username, password) and acg_session_check _main() with a stubbed Playwright page/browser, as in scripts/lib/acg/tests/providers/*.test.js; env XDG_STATE_HOME pointed at a scratch dir"
```

## Definition of done (worker)

1. Run `npm run check` and `npm test` in `scripts/lib/acg/`, with the command, exit code and every error line.
2. For each `must_not`: break the guard, show its test red, restore it, show it green. List any that stayed green.
3. "No read-only real-data run possible": a real run needs a signed-out Pluralsight session.
4. List every choice the spec did not decide.
