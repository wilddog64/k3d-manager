# Bug: _deleteConflictingSandbox misses conflict when panel closed; panelStartBtn clicks disabled button forever

**Date:** 2026-06-12
**Branch (lib-acg):** `feat/v0.1.7`
**File:** `playwright/lib/sandbox.js`

---

## Symptom

```
INFO: Start Sandbox button is disabled — sandbox already running; waiting for credentials...
INFO: Waiting for AWS credentials to populate (up to 420s)...
INFO: AWS panel open but sandbox not started — clicking Start Sandbox...
INFO: AWS panel open but sandbox not started — clicking Start Sandbox...
... (repeats for 420s)
```

An active Azure sandbox is running. The Pluralsight UI shows:
"You may have only one active sandbox at a time. In order to start an AWS Sandbox,
you must first shut down your current AZURE sandbox."

The AWS Start Sandbox button is disabled. `make up CLUSTER_PROVIDER=k3s-aws` fails.

---

## Root Cause (3-step chain)

**Step 1 — `_deleteConflictingSandbox` uses `'Auto Shutdown'` as the only detection signal.**
`'Auto Shutdown'` text only appears when the conflicting provider's panel is **open**.
When Azure is running but its panel is closed, `_deleteConflictingSandbox` finds nothing
and returns silently. No deletion happens.

**Step 2 — `startSandbox` disabled-button branch assumes "sandbox already running".**
After `_deleteConflictingSandbox` returns without deleting, `startSandbox` finds the AWS
Start Sandbox button (disabled due to conflict), treats disabled as "sandbox already running",
and calls `_waitForCredentials` without checking the conflict banner.

**Step 3 — `_waitForCredentials` panelStartBtn loop has no `isDisabled()` check.**
Inside `_waitForCredentials`, the panelStartBtn scan finds the disabled AWS Start Sandbox
button (visible = true), no disabled check, clicks it with `force: true` every 5s for 420s.

---

## Fix

### Change 1 — `_deleteConflictingSandbox`: use conflict banner text as primary detection

The conflict banner "shut down your current X sandbox" is always visible on the page
regardless of panel state. Parse it first; fall back to `Auto Shutdown` scan for cases
where the banner is absent but the panel is open.

**Exact old block (lines 365–387):**

```js
  const conflictingLabel = await page.evaluate((tLabel) => {
    const candidates = [
      { label: 'AWS', keywords: ['AWS'] },
      { label: 'Google Cloud', keywords: ['Google Cloud', 'GCP'] },
      { label: 'Azure', keywords: ['Azure'] },
    ].filter(c => !c.keywords.some(k => tLabel.toLowerCase().includes(k.toLowerCase())));

    const allProviderKeywords = ['AWS', 'Google Cloud', 'GCP', 'Azure'];
    for (const c of candidates) {
      const otherKeywords = allProviderKeywords.filter(k => !c.keywords.includes(k));
      const found = Array.from(document.querySelectorAll('*'))
        .some(el => {
          const t = el.innerText || '';
          if (!t.includes('Auto Shutdown')) return false;
          if (!c.keywords.some(k => t.includes(k))) return false;
          // Skip shared containers that mention other providers
          if (otherKeywords.some(k => t.includes(k))) return false;
          return true;
        });
      if (found) return c.label;
    }
    return null;
  }, targetLabel).catch(() => null);
```

**Exact new block:**

```js
  const conflictingLabel = await page.evaluate((tLabel) => {
    // Primary: conflict banner is always visible when another sandbox is running,
    // regardless of whether that provider's panel is open.
    const bodyText = document.body ? (document.body.innerText || '') : '';
    const bannerMatch = bodyText.match(/shut down your current ([A-Za-z ]+?) sandbox/i);
    if (bannerMatch) {
      const label = bannerMatch[1].trim();
      if (!tLabel.toLowerCase().includes(label.toLowerCase())) return label;
    }

    // Fallback: Auto Shutdown text — only present when the provider panel is open.
    const candidates = [
      { label: 'AWS', keywords: ['AWS'] },
      { label: 'Google Cloud', keywords: ['Google Cloud', 'GCP'] },
      { label: 'Azure', keywords: ['Azure'] },
    ].filter(c => !c.keywords.some(k => tLabel.toLowerCase().includes(k.toLowerCase())));

    const allProviderKeywords = ['AWS', 'Google Cloud', 'GCP', 'Azure'];
    for (const c of candidates) {
      const otherKeywords = allProviderKeywords.filter(k => !c.keywords.includes(k));
      const found = Array.from(document.querySelectorAll('*'))
        .some(el => {
          const t = el.innerText || '';
          if (!t.includes('Auto Shutdown')) return false;
          if (!c.keywords.some(k => t.includes(k))) return false;
          // Skip shared containers that mention other providers
          if (otherKeywords.some(k => t.includes(k))) return false;
          return true;
        });
      if (found) return c.label;
    }
    return null;
  }, targetLabel).catch(() => null);
```

---

### Change 2 — `_waitForCredentials` panelStartBtn: skip disabled buttons

**Exact old block (lines 254–258, inside the `for` loop in `_waitForCredentials`):**

```js
        const btn = allStart.nth(i);
        const visible = await btn.isVisible({ timeout: 300 }).catch(() => false);
        if (!visible) continue;
        const inTargetPanel = await btn.evaluate((el, pLabel) => {
```

**Exact new block:**

```js
        const btn = allStart.nth(i);
        const visible = await btn.isVisible({ timeout: 300 }).catch(() => false);
        if (!visible) continue;
        const disabled = await btn.isDisabled().catch(() => false);
        if (disabled) continue;
        const inTargetPanel = await btn.evaluate((el, pLabel) => {
```

---

### Change 3 — `startSandbox` disabled-button branch: check conflict banner before assuming running

**Exact old block (lines 501–508):**

```js
    const startEnabled = await startButton.isEnabled({ timeout: 1000 }).catch(() => false);
    if (startEnabled) {
      console.error('INFO: Clicking Start Sandbox...');
      await startButton.scrollIntoViewIfNeeded().catch(() => {});
      await startButton.click({ force: true });
    } else {
      console.error('INFO: Start Sandbox button is disabled — sandbox already running; waiting for credentials...');
    }
```

**Exact new block:**

```js
    const startEnabled = await startButton.isEnabled({ timeout: 1000 }).catch(() => false);
    if (startEnabled) {
      console.error('INFO: Clicking Start Sandbox...');
      await startButton.scrollIntoViewIfNeeded().catch(() => {});
      await startButton.click({ force: true });
    } else {
      const conflictBanner = await page.evaluate(() => {
        const t = document.body ? (document.body.innerText || '') : '';
        return t.includes('You may have only one active sandbox at a time');
      }).catch(() => false);
      if (conflictBanner) {
        console.error('INFO: Start Sandbox disabled due to active conflict — deleting conflicting sandbox...');
        await _deleteConflictingSandbox(page, provider);
        const retryStart = await _findScopedButton(page, 'Start Sandbox', providerLabel, 10000);
        if (retryStart && await retryStart.isEnabled({ timeout: 1000 }).catch(() => false)) {
          await retryStart.scrollIntoViewIfNeeded().catch(() => {});
          await retryStart.click({ force: true });
        }
      } else {
        console.error('INFO: Start Sandbox button is disabled — sandbox already running; waiting for credentials...');
      }
    }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | 3 targeted changes: conflict banner detection, disabled-button skip, disabled-button conflict re-check |

---

## Rules

- `node --check playwright/lib/sandbox.js` — must pass
- No other files touched

---

## Before You Start

- Repo: `lib-acg`
- Branch: `feat/v0.1.7`
- Run: `git pull origin feat/v0.1.7`
- Read: `playwright/lib/sandbox.js` in full
- Confirm:
  - lines 365–387 match Change 1 old block exactly
  - lines 254–258 match Change 2 old block exactly
  - lines 501–508 match Change 3 old block exactly

---

## Definition of Done

- [ ] Change 1: `bannerMatch` block inserted at top of `page.evaluate` in `_deleteConflictingSandbox`, before `candidates` array; existing `Auto Shutdown` fallback intact
- [ ] Change 1: `bannerMatch[1].trim()` returned only when label does not match `tLabel` (no self-conflict)
- [ ] Change 2: `const disabled = await btn.isDisabled().catch(() => false);` + `if (disabled) continue;` added after `if (!visible) continue;` in `_waitForCredentials` panelStartBtn loop
- [ ] Change 3: `conflictBanner` check + `_deleteConflictingSandbox` retry inserted in the `else` branch of `startEnabled` check, before proceeding to `_waitForCredentials`
- [ ] Change 3: existing `'INFO: Start Sandbox button is disabled — sandbox already running...'` message retained in the `else` (no conflict) sub-branch
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] No files other than `playwright/lib/sandbox.js` touched
- [ ] Committed and pushed to `feat/v0.1.7`
- [ ] memory-bank in k3d-manager updated with lib-acg commit SHA and task status

**Commit message (exact):**
```
fix(sandbox): detect conflict via banner text; skip disabled Start Sandbox in credential wait
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js`
- Do NOT commit to `main` — work on `feat/v0.1.7` in lib-acg
- Do NOT remove the `Auto Shutdown` fallback — it handles cases where the banner is absent
- Do NOT add conflict detection to the `resumeButton` branch — that branch is not affected
