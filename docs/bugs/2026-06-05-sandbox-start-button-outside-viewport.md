# Bugfix: v0.1.2 — Start Sandbox button outside viewport

**Branch:** `feat/v0.1.2`
**Files:** `playwright/lib/sandbox.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

`acg-up` fails with `locator.click: Element is outside of the viewport` when clicking
"Start Sandbox". The Pluralsight sandbox panel renders partially below the fold; Playwright's
default `click()` refuses to click an element not in the viewport.

**Root cause:** `startButton.click()`, `startButton2.click()`, and `resumeButton.click()` in
`startSandbox()` do not scroll the button into view before clicking. `openButton` already has
`{ force: true }` (added in PR #35) but the three Start/Resume paths were missed.

---

## Reproduction

```bash
bin/acg-up --no-login-prompt
# Expected: "Start Sandbox" clicked; credentials extracted
# Actual:   locator.click: Element is outside of the viewport
#           CLUSTER_FAILURE PERMANENT — failed to extract AWS credentials
```

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: add scrollIntoViewIfNeeded() before each click

**Exact old block (lines 222–246):**

```js
  if (await startButton.isVisible({ timeout: 5000 }).catch(() => false)) {
    const startEnabled = await startButton.isEnabled({ timeout: 1000 }).catch(() => false);
    if (startEnabled) {
      console.error('INFO: Clicking Start Sandbox...');
      await startButton.click();
    } else {
      console.error('INFO: Start Sandbox button is disabled — sandbox already running; waiting for credentials...');
    }
    await _waitForCredentials(page);
  } else if (await openButton.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Clicking Open Sandbox...');
    await openButton.click({ force: true });
    await page.waitForTimeout(3000);

    const startButton2 = page.locator('button:has-text("Start Sandbox")').first();
    if (await startButton2.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.error('INFO: Clicking Start Sandbox (Step 2)...');
      await startButton2.click();
    }
    await _waitForCredentials(page);
  } else if (await resumeButton.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Clicking Resume Sandbox...');
    await resumeButton.click();
    await _waitForCredentials(page);
  }
```

**Exact new block:**

```js
  if (await startButton.isVisible({ timeout: 5000 }).catch(() => false)) {
    const startEnabled = await startButton.isEnabled({ timeout: 1000 }).catch(() => false);
    if (startEnabled) {
      console.error('INFO: Clicking Start Sandbox...');
      await startButton.scrollIntoViewIfNeeded().catch(() => {});
      await startButton.click();
    } else {
      console.error('INFO: Start Sandbox button is disabled — sandbox already running; waiting for credentials...');
    }
    await _waitForCredentials(page);
  } else if (await openButton.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Clicking Open Sandbox...');
    await openButton.click({ force: true });
    await page.waitForTimeout(3000);

    const startButton2 = page.locator('button:has-text("Start Sandbox")').first();
    if (await startButton2.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.error('INFO: Clicking Start Sandbox (Step 2)...');
      await startButton2.scrollIntoViewIfNeeded().catch(() => {});
      await startButton2.click();
    }
    await _waitForCredentials(page);
  } else if (await resumeButton.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Clicking Resume Sandbox...');
    await resumeButton.scrollIntoViewIfNeeded().catch(() => {});
    await resumeButton.click();
    await _waitForCredentials(page);
  }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Add `scrollIntoViewIfNeeded()` before `startButton`, `startButton2`, and `resumeButton` clicks |

---

## Rules

- `node --check playwright/lib/sandbox.js` — must pass with zero errors
- Code change limited to `playwright/lib/sandbox.js`; `CHANGELOG.md`, this bug spec doc, and memory-bank updates are also expected

---

## Definition of Done

- [ ] `playwright/lib/sandbox.js` matches the exact new block above
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] Committed and pushed to `feat/v0.1.2`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(sandbox): scrollIntoViewIfNeeded before Start/Resume Sandbox clicks
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any code file other than `playwright/lib/sandbox.js` (CHANGELOG.md and memory-bank updates are expected)
- Do NOT commit to `main` — work on `feat/v0.1.2`
