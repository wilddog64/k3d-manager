# Bugfix: v1.6.4 — Start/Resume Sandbox click fails — element outside viewport (regression)

**Branch:** `k3d-manager-v1.6.4`
**Files:** `scripts/lib/acg/playwright/lib/sandbox.js`

---

## Problem

`acg-up` fails with CLUSTER_FAILURE PERMANENT: "Failure to extract AWS credentials from the
Pluralsight sandbox due to browser automation timeouts during page element selection and
button clicking."

In `startSandbox`, all three click paths (`startButton`, `startButton2`, `resumeButton`)
call `scrollIntoViewIfNeeded().catch(() => {})` then `.click()` without `{ force: true }`.
When the `addLocatorHandler` for "sandbox has been extended" fires during the click attempt,
React re-renders and shifts the layout. By the time Playwright fires the click, the element
has moved outside the viewport and throws "Element is outside of the viewport".

**Root cause:** The `sandbox.js` refactor dropped the `{ force: true }` that was present in
the old `_clickStartSandbox` helper in `acg_credentials.js` (documented in
`docs/bugs/2026-05-16-acg-credentials-start-sandbox-outside-viewport.md`, fixed in v1.4.6).
The `openButton.click({ force: true })` at line 234 uses the correct pattern; the three
surrounding clicks do not.

**Note:** `scripts/lib/acg/` is a git subtree from lib-acg. This edit is direct-subtree
debt — track in memory-bank, upstream to lib-acg after this fix lands.

---

## Fix

Add `{ force: true }` to the three `.click()` calls that lack it in `startSandbox`. We
already verify `isVisible()` and `isEnabled()` before calling click, so bypassing the
viewport actionability check is safe.

### Change 1 — `sandbox.js` line 227: startButton click

**Exact old block:**
```javascript
      console.error('INFO: Clicking Start Sandbox...');
      await startButton.scrollIntoViewIfNeeded().catch(() => {});
      await startButton.click();
```

**Exact new block:**
```javascript
      console.error('INFO: Clicking Start Sandbox...');
      await startButton.scrollIntoViewIfNeeded().catch(() => {});
      await startButton.click({ force: true });
```

### Change 2 — `sandbox.js` line 241: startButton2 click

**Exact old block:**
```javascript
      console.error('INFO: Clicking Start Sandbox (Step 2)...');
      await startButton2.scrollIntoViewIfNeeded().catch(() => {});
      await startButton2.click();
```

**Exact new block:**
```javascript
      console.error('INFO: Clicking Start Sandbox (Step 2)...');
      await startButton2.scrollIntoViewIfNeeded().catch(() => {});
      await startButton2.click({ force: true });
```

### Change 3 — `sandbox.js` line 247: resumeButton click

**Exact old block:**
```javascript
    console.error('INFO: Clicking Resume Sandbox...');
    await resumeButton.scrollIntoViewIfNeeded().catch(() => {});
    await resumeButton.click();
```

**Exact new block:**
```javascript
    console.error('INFO: Clicking Resume Sandbox...');
    await resumeButton.scrollIntoViewIfNeeded().catch(() => {});
    await resumeButton.click({ force: true });
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/lib/sandbox.js` | Add `{ force: true }` to 3 `.click()` calls in `startSandbox` |

---

## Rules

- `node --check scripts/lib/acg/playwright/lib/sandbox.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] All three `.click()` calls in `startSandbox` use `{ force: true }`
- [ ] `node --check scripts/lib/acg/playwright/lib/sandbox.js` passes
- [ ] Committed and pushed to `k3d-manager-v1.6.4`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-credentials): restore force:true on Start/Resume Sandbox clicks in sandbox.js
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/lib/sandbox.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.6.4`
- Do NOT change the `openButton.click({ force: true })` at line 234 — it is already correct
