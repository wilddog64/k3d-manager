# Bug: acg-credentials — Escape does not dismiss "Extend Your Session" dialog — click × instead

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

In `_waitForCredentials` (proactive-dismiss block, line 384–397), when the "Extend Your
Session" dialog is visible but its "Cancel" button is not visible, the code falls back to
`page.keyboard.press('Escape')`. Escape does not dismiss the dialog — the modal ignores
keyboard events. `make up` hangs with the dialog blocking sandbox controls.

**Root cause:** The Escape fallback at line 392 assumes keyboard events close the dialog.
They do not. The correct dismissal is clicking the × close button in the upper right of the
dialog, which is a `button[aria-label="Close"]` element within `[role="dialog"]`.

---

## Reproduction

1. Run `make up`
2. "Extend Your Session" dialog appears mid-flow
3. "Cancel" button is not visible (e.g. dialog is in a different render state)
4. Code falls back to `page.keyboard.press('Escape')` at line 392
5. Dialog stays open — `make up` proceeds with dialog blocking controls

---

## Fix

### Change 1 — `acg_credentials.js` line 392: replace Escape with × button click

**Exact old line:**
```javascript
        await page.keyboard.press('Escape').catch(() => {});
```

**Exact new line:**
```javascript
        await _extendSessionPrompt.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
```

**Why:** `button[aria-label="Close"]` is the standard ARIA selector for the × close button
in modal dialogs. Scoping it to `_extendSessionPrompt` (already the "Extend Your Session"
dialog locator) ensures we click the correct button. `{ force: true }` handles any
overlay or CSS visibility quirk. `.catch(() => {})` fails gracefully if the button is
absent.

---

## Files Changed

| File | Changes |
|------|---------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Change 1 — replace Escape fallback with × button click |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass
- No other files touched
- The change is EXACTLY ONE LINE — line 392 only. Nothing else changes.

---

## Definition of Done

- [ ] Line 392: `page.keyboard.press('Escape').catch(() => {})` → `_extendSessionPrompt.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {})`
- [ ] All surrounding lines unchanged (lines 384–397 structure intact)
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg-credentials): click × close button instead of Escape to dismiss Extend Your Session dialog
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change line 388 (`_cancelBtn` declaration) — that part stays
- Do NOT change line 390 (`_cancelBtn.click`) — that part stays
- Do NOT change lines 394–396 (`waitFor` + WARN log) — those stay
- Do NOT change the "Session extended" card dismissal paths — those are different and correct
- Do NOT change `addLocatorHandler` — that handler is separate and correct
