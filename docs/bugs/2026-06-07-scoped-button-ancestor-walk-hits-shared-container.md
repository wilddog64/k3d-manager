# Bugfix: v0.1.4 — ancestor walk reaches shared container, wrong provider card selected

**Branch:** `feat/v0.1.4`
**Files:** `playwright/lib/sandbox.js`, `playwright/providers/azure.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

When the sandbox page has multiple provider cards (AWS, Azure, GCP), the ancestor walk in
`_findScopedButton` (8 levels) and the credential scoped checks (12 levels) climb high enough
to reach the shared container element whose `innerText` includes ALL provider labels.

Result: `_findScopedButton(page, 'Start Sandbox', 'Azure', 5000)` returns the AWS "Start
Sandbox" button because one of its 8 ancestors is the shared wrapper containing "Azure".
Then clicking that button starts a NEW AWS sandbox instead of the Azure one.

**Symptom observed:**
```
INFO: Clicking Open Sandbox...
INFO: Clicking Start Sandbox (Step 2)...
INFO: Waiting for Azure credentials to populate (up to 420s)...
```
Browser shows a freshly started AWS sandbox with `cloud_user` + AKIA credentials.

**Root cause:** Every ancestor-walk check uses only `new RegExp(label, 'i').test(t)` as the
match condition. This returns `true` for any container element whose `innerText` includes the
target label — including the shared parent that contains all provider cards. The individual
provider card is the FIRST ancestor whose text has the target label WITHOUT the other providers'
labels. That exclusion is missing.

The defect exists in four places (NOT `_waitForCredentials` — see Change 2 below):
1. `_findScopedButton` — 8-level walk (sandbox.js)
2. `credentialsAlreadyVisible` evaluate in `startSandbox` — 12-level walk (sandbox.js)
3. `azure.js` `waitForFunction` — 12-level walk
4. `azure.js` `page.evaluate` filter — 12-level walk

`_waitForCredentials` is intentionally NOT given the exclusion check. Its credential-area
text often contains only field labels ("Username", "Password", "Access Key Id") with no
provider keyword — making the DOM walk unreliable. `_waitForCredentials` just needs to know
when ANY credentials have populated; the provider-specific extractor does the filtering.

---

## Fix

The exclusion check: when an ancestor's `innerText` contains the target label, also verify
it does NOT contain any OTHER provider keyword. The individual Azure card has "Azure" but not
"AWS" or "Google Cloud". The shared wrapper has all three and is rejected.

---

### Change 1 — `playwright/lib/sandbox.js`: `_findScopedButton` ancestor walk

**Exact old block (lines 198–206):**

```javascript
      const inCard = await btn.evaluate((el, label) => {
        let node = el.parentElement;
        for (let j = 0; j < 8; j++) {
          if (!node) break;
          if (new RegExp(label, 'i').test(node.innerText || '')) return true;
          node = node.parentElement;
        }
        return false;
      }, providerLabel).catch(() => false);
```

**Exact new block:**

```javascript
      const inCard = await btn.evaluate((el, label) => {
        const others = ['AWS', 'Google Cloud', 'GCP', 'Azure'].filter(
          p => !new RegExp(p, 'i').test(label)
        );
        let node = el.parentElement;
        for (let j = 0; j < 8; j++) {
          if (!node) break;
          const t = node.innerText || '';
          if (new RegExp(label, 'i').test(t) && !others.some(p => t.includes(p))) return true;
          node = node.parentElement;
        }
        return false;
      }, providerLabel).catch(() => false);
```

---

### Change 2 — `playwright/lib/sandbox.js`: revert `_waitForCredentials` to simple global check

The DOM-walk version (added in e383f1f) hangs for AWS because the credential area's
`innerText` contains only field labels ("Username", "Password", "Access Key Id") — no
"AWS" literal — so the walk never matches. `_waitForCredentials` doesn't need scoping;
it just signals "credentials populated." The extractor filters by provider.

**Exact old block (lines 168–183):**

```javascript
  while (Date.now() < deadline) {
    await _dismissExtendYourSessionDialog(page);
    const found = await page.evaluate((pLabel) => {
      const inputs = Array.from(document.querySelectorAll('input[aria-label="Copyable input"]'));
      for (const input of inputs) {
        if (!input.value.trim()) continue;
        let node = input.parentElement;
        for (let j = 0; j < 12; j++) {
          if (!node) break;
          if (new RegExp(pLabel, 'i').test(node.innerText || '')) return true;
          node = node.parentElement;
        }
      }
      return false;
    }, providerLabel).catch(() => false);
    if (found) return;
    await page.waitForTimeout(2000);
  }
  throw new Error(`Timed out after 420000ms waiting for ${providerLabel} credentials to populate.`);
```

**Exact new block:**

```javascript
  while (Date.now() < deadline) {
    await _dismissExtendYourSessionDialog(page);
    const inputs = page.locator('input[aria-label="Copyable input"]');
    if (await inputs.count() > 0) {
      const value = await inputs.first().inputValue().catch(() => '');
      if (value.trim().length > 0) return;
    }
    await page.waitForTimeout(2000);
  }
  throw new Error(`Timed out after 420000ms waiting for ${providerLabel} credentials to populate.`);
```

---

### Change 3 — `playwright/lib/sandbox.js`: `credentialsAlreadyVisible` evaluate in `startSandbox`

**Exact old block (lines 307–319):**

```javascript
  const credentialsAlreadyVisible = await page.evaluate((pLabel) => {
    const inputs = Array.from(document.querySelectorAll('input[aria-label="Copyable input"]'));
    for (const input of inputs) {
      if (!input.value.trim()) continue;
      let node = input.parentElement;
      for (let j = 0; j < 12; j++) {
        if (!node) break;
        if (new RegExp(pLabel, 'i').test(node.innerText || '')) return true;
        node = node.parentElement;
      }
    }
    return false;
  }, providerLabel).catch(() => false);
```

**Exact new block:**

```javascript
  const credentialsAlreadyVisible = await page.evaluate((pLabel) => {
    const others = ['AWS', 'Google Cloud', 'GCP', 'Azure'].filter(
      p => !new RegExp(p, 'i').test(pLabel)
    );
    const inputs = Array.from(document.querySelectorAll('input[aria-label="Copyable input"]'));
    for (const input of inputs) {
      if (!input.value.trim()) continue;
      let node = input.parentElement;
      for (let j = 0; j < 12; j++) {
        if (!node) break;
        const t = node.innerText || '';
        if (new RegExp(pLabel, 'i').test(t) && !others.some(p => t.includes(p))) return true;
        node = node.parentElement;
      }
    }
    return false;
  }, providerLabel).catch(() => false);
```

---

### Change 4 — `playwright/providers/azure.js`: `waitForFunction` check (lines 2–14)

**Exact old block:**

```javascript
  await page.waitForFunction(() => {
    const inputs = Array.from(document.querySelectorAll('input[aria-label="Copyable input"]'));
    return inputs.some(inp => {
      if (!inp.value.trim()) return false;
      let node = inp.parentElement;
      for (let j = 0; j < 12; j++) {
        if (!node) break;
        if (/azure/i.test(node.innerText || '')) return true;
        node = node.parentElement;
      }
      return false;
    });
  }, { timeout: 15000 });
```

**Exact new block:**

```javascript
  await page.waitForFunction(() => {
    const others = ['AWS', 'Google Cloud', 'GCP'];
    const inputs = Array.from(document.querySelectorAll('input[aria-label="Copyable input"]'));
    return inputs.some(inp => {
      if (!inp.value.trim()) return false;
      let node = inp.parentElement;
      for (let j = 0; j < 12; j++) {
        if (!node) break;
        const t = node.innerText || '';
        if (/azure/i.test(t) && !others.some(p => t.includes(p))) return true;
        node = node.parentElement;
      }
      return false;
    });
  }, { timeout: 15000 });
```

---

### Change 5 — `playwright/providers/azure.js`: `page.evaluate` filter (lines 16–27)

**Exact old block:**

```javascript
  const azureInputs = await page.evaluate(() => {
    const inputs = Array.from(document.querySelectorAll('input[aria-label="Copyable input"]'));
    return inputs
      .filter(inp => {
        let node = inp.parentElement;
        for (let j = 0; j < 12; j++) {
          if (!node) break;
          if (/azure/i.test(node.innerText || '')) return true;
          node = node.parentElement;
        }
        return false;
      })
```

**Exact new block:**

```javascript
  const azureInputs = await page.evaluate(() => {
    const others = ['AWS', 'Google Cloud', 'GCP'];
    const inputs = Array.from(document.querySelectorAll('input[aria-label="Copyable input"]'));
    return inputs
      .filter(inp => {
        let node = inp.parentElement;
        for (let j = 0; j < 12; j++) {
          if (!node) break;
          const t = node.innerText || '';
          if (/azure/i.test(t) && !others.some(p => t.includes(p))) return true;
          node = node.parentElement;
        }
        return false;
      })
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Exclusion check in `_findScopedButton` and `credentialsAlreadyVisible`; revert `_waitForCredentials` to simple global check |
| `playwright/providers/azure.js` | Add exclusion check to `waitForFunction` and `page.evaluate` filter ancestor walks |
| `CHANGELOG.md` | Add `[Unreleased]` entry under `### Fixed` |
| `memory-bank/activeContext.md` | Update current status |
| `memory-bank/progress.md` | Update v0.1.4 track |

---

## Rules

- `node --check playwright/lib/sandbox.js` — zero errors
- `node --check playwright/providers/azure.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] `_findScopedButton` evaluates to `true` only when ancestor contains `providerLabel` AND does NOT contain any other provider keyword
- [ ] `_waitForCredentials` reverted to simple `inputs.first().inputValue()` global check — NO exclusion, NO DOM walk
- [ ] `credentialsAlreadyVisible` evaluate in `startSandbox` has the exclusion check
- [ ] `azure.js` `waitForFunction` has the exclusion check (`others = ['AWS', 'Google Cloud', 'GCP']`)
- [ ] `azure.js` `page.evaluate` filter has the exclusion check
- [ ] `node --check` passes on both files
- [ ] `CHANGELOG.md` updated under `### Fixed`
- [ ] Committed and pushed to `feat/v0.1.4`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(sandbox): add provider exclusion check to ancestor walks — shared container matches wrong card
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js` and `playwright/providers/azure.js` (plus `CHANGELOG.md` and `memory-bank/`)
- Do NOT commit to `main` — work on `feat/v0.1.4`
- Do NOT change `_deleteConflictingSandbox`, `startSandbox` logic, or any provider file other than `azure.js`
- Do NOT change the depth limits (8 for buttons, 12 for credentials) — only add the exclusion check
- Do NOT touch `acg_credentials.js`, `providers/aws.js`, or `providers/gcp.js`
