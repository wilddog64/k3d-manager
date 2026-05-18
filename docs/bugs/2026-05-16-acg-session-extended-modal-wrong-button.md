# Bug: acg — "Session extended" modal × button not clicked — wrong locator scope

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/acg/playwright/acg_extend.js`, `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

After `f39adc25`, the "Session extended" confirmation modal is still not dismissed.
The fix in f39adc25 changed `page.keyboard.press('Escape')` to a scoped button click,
but the modal remains visible. `make up` continues to hang after session extension.

**Root cause:** `[role="dialog"]:has-text("Session extended")` matches the **"Extend
Your Session"** dialog container, which gains "Session extended" text in its confirmation
state. That dialog still has the "Extend Session" button first in DOM order (now hidden
but still present). `{ force: true }` bypasses the hidden check and clicks that button
instead of the × close button on the actual confirmation card. The × is never clicked.
The modal stays open.

**Fix:** Use the unique body text `"Your sandbox has been extended."` with a `:has(button)`
filter and `.last()` to scope to the innermost matching container — the confirmation card
itself, not the "Extend Your Session" dialog wrapper.

---

## Reproduction

1. Run `make up`
2. acg_extend.js or acg_credentials.js handler clicks "Extend Session"
3. "Session extended" / "Your sandbox has been extended." card appears
4. Script attempts to dismiss — clicks wrong button via `[role="dialog"]:has-text("Session extended") button.first()` with force
5. Modal remains visible
6. `make up` proceeds with modal blocking sandbox controls

---

## Fix

**In all 6 locations across both files, change ONLY the locator declaration line:**

**Old pattern (all 6 locations):**
```javascript
page.locator('[role="dialog"]:has-text("Session extended")').first()
```

**New pattern (all 6 locations):**
```javascript
page.locator(':has-text("Your sandbox has been extended."):has(button)').last()
```

**Why:** `:has-text("Your sandbox has been extended.")` is the unique body text of the
confirmation card — it does not match the "Extend Your Session" dialog. `:has(button)`
ensures we only match a container that has a button descendant (the × button). `.last()`
selects the innermost matching element (the card itself, not its ancestors). The rest of
the logic (`locator('button').first().click({ force: true })` and `waitFor({ state: 'hidden' })`)
is unchanged — the innermost card container has only the × button, so `.first()` finds it correctly.

---

### Change 1 — `acg_extend.js` line 140: initial dismissal locator

**Exact old line:**
```javascript
    const _sessionExtendedModal = page.locator('[role="dialog"]:has-text("Session extended")').first();
```

**Exact new line:**
```javascript
    const _sessionExtendedModal = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
```

---

### Change 2 — `acg_extend.js` line 188: Immediate path locator

**Exact old line:**
```javascript
      const _extendedConfirm = page.locator('[role="dialog"]:has-text("Session extended")').first();
```

**Exact new line:**
```javascript
      const _extendedConfirm = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
```

---

### Change 3 — `acg_extend.js` line 387: general path locator

**Exact old line:**
```javascript
    const _extendedConfirmGeneral = page.locator('[role="dialog"]:has-text("Session extended")').first();
```

**Exact new line:**
```javascript
    const _extendedConfirmGeneral = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
```

---

### Change 4 — `acg_credentials.js` line 267: handler callback locator

**Exact old line:**
```javascript
          const _sessionExtendedConfirm = page.locator('[role="dialog"]:has-text("Session extended")').first();
```

**Exact new line:**
```javascript
          const _sessionExtendedConfirm = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
```

---

### Change 5 — `acg_credentials.js` line 375: proactive dismissal locator

**Exact old line:**
```javascript
    const _sessionExtendedModal = page.locator('[role="dialog"]:has-text("Session extended")').first();
```

**Exact new line:**
```javascript
    const _sessionExtendedModal = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
```

---

### Change 6 — `acg_credentials.js` line 463: `_waitForCredentials` inline dismiss locator

**Exact old line:**
```javascript
              const _sessionExtendedConfirm = page.locator('[role="dialog"]:has-text("Session extended")').first();
```

**Exact new line:**
```javascript
              const _sessionExtendedConfirm = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
```

---

## Files Changed

| File | Changes |
|------|---------|
| `scripts/lib/acg/playwright/acg_extend.js` | Changes 1, 2, 3 — fix locator on 3 dismissal paths |
| `scripts/lib/acg/playwright/acg_credentials.js` | Changes 4, 5, 6 — fix locator on handler, proactive, and wait-loop paths |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_extend.js` — must pass
- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass
- No other files touched
- Each change is EXACTLY ONE LINE — the `const _sessionExtended...` declaration. Nothing else changes.

---

## Definition of Done

**Change 1 — `acg_extend.js` line 140:**
- [ ] `page.locator('[role="dialog"]:has-text("Session extended")').first()` → `page.locator(':has-text("Your sandbox has been extended."):has(button)').last()`
- [ ] All other lines in the block unchanged

**Change 2 — `acg_extend.js` line 188:**
- [ ] Same substitution as Change 1

**Change 3 — `acg_extend.js` line 387:**
- [ ] Same substitution as Change 1

**Change 4 — `acg_credentials.js` line 267:**
- [ ] Same substitution as Change 1

**Change 5 — `acg_credentials.js` line 375:**
- [ ] Same substitution as Change 1

**Change 6 — `acg_credentials.js` line 463:**
- [ ] Same substitution as Change 1

**Both files:**
- [ ] `node --check` passes on both files
- [ ] No other lines touched
- [ ] No other files modified
- [ ] Commit message (exact): `fix(acg): use body text locator for Session extended modal — dialog scope finds wrong button`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change `button.first().click({ force: true })` — that part stays
- Do NOT change `waitFor({ state: 'hidden', timeout: 5000 })` — that part stays
- Do NOT change any `console.error(...)` lines
- Do NOT change `{ times: 1 }` on `addLocatorHandler`
- Do NOT change the "Extend Your Session" locators — those are different and correct
- Do NOT change the `waitForTimeout` lines in the handler or `_waitForCredentials`
