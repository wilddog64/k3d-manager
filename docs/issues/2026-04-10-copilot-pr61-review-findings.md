# Copilot PR #61 Review Findings

**PR:** #61 — `fix(acg): extend hardening, random passwords, sandbox-expired guidance`
**Files reviewed:** `scripts/playwright/acg_extend.js`
**Fix commit:** `4f7f273d`

---

## Finding 1 — CodeQL: Incomplete URL substring sanitization (line 77)

**Flagged:** `currentUrl.includes('pluralsight.com')` — arbitrary hosts can appear before or after the substring, bypassing the guard.

**Fix:** Parse `currentUrl` with `new URL()` and check `hostname === 'pluralsight.com' || hostname.endsWith('.pluralsight.com')`.

**Root cause:** URL guard written as a quick string check; not considering subdomain or path injection vectors.

---

## Finding 2 — Credential leak in shutdown text log (line 134)

**Flagged:** `shutdownText` extracted from `el.parentElement.innerText` logged verbatim — parent container may include AWS credential fields (Access Key ID / Session Token).

**Fix:** Removed the verbatim log line entirely. Only the parsed time string from `match[1]` is used downstream; nothing from the raw `innerText` is emitted.

**Root cause:** Debug log added during development without considering the content scope of `parentElement.innerText`.

---

## Finding 3 — CDP browser closed on attached session (line 53)

**Flagged:** `_cdpBrowser.close()` in the `finally` block shuts down the entire Chrome process when we attached to an existing session via CDP — disruptive to the user's active browser.

**Fix:** Changed `finally` to only call `browserContext.close()` when we launched the context ourselves (`!_cdpBrowser`). CDP-attached sessions are left running.

**Root cause:** The original `close()` call was written for the `launchPersistentContext` path and was not adjusted when the CDP attach path was added.

---

## Finding 4 — Ghost State recovery triggered on weak signal (line 204)

**Flagged:** `remainingMins === null` (TTL parse failure) triggers the destructive delete→start→extend flow — transient DOM changes could cause an unintended sandbox deletion.

**Fix:** Changed condition from `(remainingMins === null || remainingMins < 15)` to `(remainingMins !== null && remainingMins < 15)`. TTL parse failure alone is not sufficient to trigger a destructive action.

**Root cause:** Null was used as a fallback "critical" signal to ensure the recovery path was reachable during testing. The recovery path was later implemented without tightening the guard.
