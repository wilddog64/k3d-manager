# Bugfix: v0.1.3 — Start/Resume Sandbox clicks missing force:true — viewport shift causes failure

**Branch:** `feat/v0.1.3`
**Files:** `playwright/lib/sandbox.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

`acg-up` fails with CLUSTER_FAILURE PERMANENT: "Failure to extract AWS credentials ...
browser automation timeouts during page element selection and button clicking."

In `startSandbox()`, the `addLocatorHandler` for "sandbox has been extended" can fire
**during** a click attempt. The handler triggers a React re-render and layout shift;
by the time Playwright fires the pointer event the element has moved out of the viewport
and throws `locator.click: Element is outside of the viewport`.

`scrollIntoViewIfNeeded()` was added in v0.1.2 but the scroll happens *before* the
handler fires — the scroll is therefore valid, then the layout shift invalidates it.
`{ force: true }` bypasses Playwright's post-scroll viewport actionability re-check
and fires the pointer event at the element's current bounding box regardless.

`openButton.click({ force: true })` at line 234 already uses the correct pattern.
The three surrounding clicks (`startButton`, `startButton2`, `resumeButton`) do not.

**Root cause:** v0.1.2 added `scrollIntoViewIfNeeded()` but omitted `{ force: true }`,
which is the half of the fix that survives the post-scroll layout shift.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js` line 227: startButton click

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

### Change 2 — `playwright/lib/sandbox.js` line 241: startButton2 click

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

### Change 3 — `playwright/lib/sandbox.js` line 247: resumeButton click

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
| `playwright/lib/sandbox.js` | Add `{ force: true }` to 3 `.click()` calls in `startSandbox` |

---

## Rules

- `node --check playwright/lib/sandbox.js` — zero errors
- `CHANGELOG.md` and `memory-bank/` updates are expected alongside the code change

---

## Definition of Done

- [ ] All three `.click()` calls in `startSandbox` use `{ force: true }`
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] Committed and pushed to `feat/v0.1.3`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(sandbox): add force:true to Start/Resume Sandbox clicks — survive layout shift after handler fires
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any code file other than `playwright/lib/sandbox.js` (CHANGELOG.md and memory-bank updates are expected)
- Do NOT commit to `main` — work on `feat/v0.1.3`
- Do NOT remove `scrollIntoViewIfNeeded()` — keep both scroll and force
