# Copilot PR #27 Review Findings

**PR:** #27 — fix/next-improvements-5
**Date:** 2026-05-23

---

## Findings

### Finding 1 — `button.first()` toast dismiss is ambiguous (3 locations in acg_extend.js, 1 in acg_restart.js)

**Files:** `playwright/acg_extend.js` (lines 150, 196, 385), `playwright/acg_restart.js` (line 223)
**What Copilot flagged:** Toast dismiss code uses `button.first()` within the toast container ancestor, which can hit an action button ("View Sandbox") before the close X, causing navigation that breaks the flow.
**Fix:** Replace XPath ancestor button click with `page.keyboard.press('Escape')` — dismisses the toast without targeting any specific button.
**Spec:** `docs/bugs/2026-05-23-toast-button-first-ambiguous-dismiss.md`
**Root cause:** The dismiss pattern was copied without accounting for Pando toasts that have two buttons (action + close X) in DOM order.

---

### Finding 2 — `_cdpBrowser.disconnect()` is not a Playwright API (3 locations in acg_credentials.js, 3 in acg_restart.js)

**Files:** `playwright/acg_credentials.js` (lines 201, 210, 568), `playwright/acg_restart.js` (lines 160, 168, 418)
**What Copilot flagged:** `Browser` objects from `chromium.connectOverCDP()` have no `.disconnect()` method — `.close()` is the correct API.
**Fix:** Replace all 6 occurrences of `.disconnect()` with `.close()`.
**Spec:** `docs/bugs/2026-05-23-cdp-browser-disconnect-not-a-function.md`
**Root cause:** `acg_extend.js` was fixed in a prior session; these two files were missed. Currently silent because the error is swallowed by `try {} catch {}`.

---

### Finding 3 — "No other files touched" wording in bug doc Rules sections (17 docs files)

**Files:** All `docs/bugs/2026-05-23-*.md` and several older bug docs
**What Copilot flagged:** Wording conflicts with repo process guidance from `docs/retro/2026-05-19-pr14-retrospective.md`, which recommends wording that explicitly allows CHANGELOG and memory-bank updates.
**Fix:** Replaced with "Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required" across all 17 affected files.
**Root cause:** Bug doc template was written before the retro established this rule; all docs written this session inherited the old wording.

---

## Process Note

Add to bug doc template: use "Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required" in the Rules section — not "No other files touched".
