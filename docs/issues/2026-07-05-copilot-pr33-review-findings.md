# Copilot PR #33 Review Findings — ACG headless Pluralsight auto-login

**PR:** [#33](https://github.com/wilddog64/lib-foundation/pull/33) (`feat/v0.4.1` → `main`)
**Date:** 2026-07-05
**Reviewer:** `copilot-pull-request-reviewer[bot]` — 4 inline findings (3 fixed, 1 declined with rationale)

---

## Finding 1 — hard-coded CDP port in expiry message (FIXED)

**`scripts/lib/acg/acg_session_check.js:68`** — the `ACG_SESSION_EXPIRED` message hard-coded
`:9222`, misleading when `PLAYWRIGHT_CDP_HOST` / `PLAYWRIGHT_CDP_PORT` are overridden.

**Before:**
```js
console.error('ACG_SESSION_EXPIRED: ... sign in on the host CDP Chrome (:9222) and re-run.');
```
**After:**
```js
console.error(`ACG_SESSION_EXPIRED: ... sign in on the host CDP Chrome (${CDP_URL}) and re-run.`);
```
`CDP_URL` is already derived from the two env vars at the top of the file, so the operator now
sees the actual endpoint.

---

## Finding 2 — `browser.close()` vs `browser.disconnect()` (DECLINED — Copilot is incorrect)

**`scripts/lib/acg/acg_session_check.js:91`** — Copilot flagged `browser.close()` as inconsistent
with the module (`gcp_login.js:157` uses `browser.disconnect()`) and asked to switch to `disconnect()`.

**Not applied.** Verified against the vendored Playwright 1.60.0 type definitions
(`node_modules/playwright-core/types/types.d.ts`, `interface Browser`):

- There is **no `Browser.disconnect()` method** — `disconnected` exists only as an *event*.
- `Browser.close()` (line 10065) is documented as: *"In case this browser is connected to, clears
  all created contexts belonging to this browser and disconnects from the browser server."* — i.e.
  for a `connectOverCDP` browser it detaches Playwright **without** terminating the operator's
  Chrome. The in-repo comment at `acg_extend.js:394` states the same.

Consequently `gcp_login.js:157`'s `try { await browser.disconnect(); } catch {}` calls a
nonexistent method whose `TypeError` is swallowed by the empty `catch` — a latent no-op, not a
convention to copy. Switching `acg_session_check.js` to `disconnect()` would replace correct,
documented teardown with a silent no-op. `close()` is retained. (Follow-up candidate: correct the
misleading `disconnect()` idiom in `gcp_login.js` in a separate change.)

---

## Finding 3 — missing session-check-level MFA coverage (FIXED)

**`scripts/lib/acg/tests/providers/acg_session_check.test.js`** — the two non-interactive tests
were near-duplicates (both no-creds) and neither exercised the `_autoLogin` MFA path
(`loginWithPage` → `mfa_required` → fast-fail without polling).

Reworked into two distinct branches:
- `no creds skips auto-login and fails fast without polling` — asserts `loginWithPage` **not**
  called, no `waitForTimeout`, fast `ACG_SESSION_EXPIRED`.
- `noninteractive MFA-required session fails fast without polling` — creds present,
  `loginWithPage` returns `{ ok: false, reason: 'mfa_required' }`; asserts `loginWithPage`
  **was** called, no `waitForTimeout`, fast `ACG_SESSION_EXPIRED`.

Full acg suite: 5 suites / 13 tests green; `npm run check` clean.

---

## Finding 4 — retro version-history inconsistency (FIXED)

**`docs/retro/2026-06-22-v0.4.0-retrospective.md:33-35`** — bullet claimed "v0.3.18–v0.3.20 are
tagged", contradicting `CHANGE.md`'s back-fill note. Corrected to: `v0.3.19` (`45040e2`) was tagged
straight off `[Unreleased]` without a section; `v0.3.18` was never tagged (its `_copilot_auth_check`
work shipped in v0.3.19); there was never a `v0.3.20`.

---

## Process note

Finding 2 is the reusable lesson: a Copilot "consistency" suggestion can point at code that is
itself wrong. Always verify a suggested API against the vendored dependency's type defs before
changing working code — a suggestion that matches a sibling file is not evidence the sibling is
correct.
