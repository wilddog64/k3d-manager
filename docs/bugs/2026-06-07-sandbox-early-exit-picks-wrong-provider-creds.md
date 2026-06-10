# Bugfix: v0.1.4 — startSandbox early-exit picks wrong provider credentials

**Branch:** `feat/v0.1.4`
**Files:** `playwright/lib/sandbox.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

`make credential-test PROVIDER=az` reports `AZURE_USERNAME/PASSWORD/SUBSCRIPTION_ID/TENANT_ID`
but the values are the current AWS sandbox credentials, not Azure credentials.

**Root cause:** `startSandbox()` checks for any populated `input[aria-label="Copyable input"]`
before calling `_deleteConflictingSandbox`. When the AWS panel is already open with credentials,
the unscoped check fires and returns early — the conflict deletion never runs, and the Azure
provider's `extractCredentials` subsequently reads the AWS inputs.

Two defects on consecutive lines:
1. Lines 274–281 — unscoped credential check runs before `_deleteConflictingSandbox` (line 309)
2. Line 283 — log message still says `'INFO: Looking for Start/Open button...'` (not provider-aware)

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: remove unscoped early-exit, fix log message

**Exact old block (lines 270–283):**

```javascript
async function startSandbox(page, targetUrl, provider) {
  provider = provider || 'aws';
  const _providerLabels = { aws: 'AWS', gcp: 'Google Cloud', azure: 'Azure' };
  const providerLabel = _providerLabels[provider] || provider;
  const firstCredInput = page.locator('input[aria-label="Copyable input"]').first();
  const firstCredVisible = await firstCredInput.isVisible({ timeout: 3000 }).catch(() => false);
  const firstCredValue = firstCredVisible ? await firstCredInput.inputValue().catch(() => '') : '';
  const credentialsAlreadyVisible = firstCredVisible && firstCredValue.trim().length > 0;
  if (credentialsAlreadyVisible) {
    console.error('INFO: Credentials already populated — skipping Start/Open flow');
    return;
  }

  console.error('INFO: Looking for Start/Open button...');
```

**Exact new block:**

```javascript
async function startSandbox(page, targetUrl, provider) {
  provider = provider || 'aws';
  const _providerLabels = { aws: 'AWS', gcp: 'Google Cloud', azure: 'Azure' };
  const providerLabel = _providerLabels[provider] || provider;

  console.error(`INFO: Looking for ${providerLabel} sandbox buttons...`);
```

---

### Change 2 — `playwright/lib/sandbox.js`: add provider-scoped credential check after conflict deletion

**Exact old block (lines 309–311):**

```javascript
  await _deleteConflictingSandbox(page, provider);

  const startButton = await _findScopedButton(page, 'Start Sandbox', providerLabel, 5000);
```

**Exact new block:**

```javascript
  await _deleteConflictingSandbox(page, provider);

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

  if (credentialsAlreadyVisible) {
    console.error(`INFO: ${providerLabel} credentials already populated — skipping Start/Open flow`);
    return;
  }

  const startButton = await _findScopedButton(page, 'Start Sandbox', providerLabel, 5000);
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Remove unscoped early-exit; add provider-scoped credential check after conflict deletion |
| `CHANGELOG.md` | Add `[Unreleased]` entry under `### Fixed` |
| `memory-bank/activeContext.md` | Update current status |
| `memory-bank/progress.md` | Update v0.1.4 track |

---

## Rules

- `node --check playwright/lib/sandbox.js` — zero errors
- `CHANGELOG.md` and `memory-bank/` updates are expected alongside the code change

---

## Definition of Done

- [ ] Unscoped `firstCredInput` / `credentialsAlreadyVisible` block removed from start of `startSandbox`
- [ ] Log message changed from `'INFO: Looking for Start/Open button...'` to `\`INFO: Looking for ${providerLabel} sandbox buttons...\``
- [ ] Provider-scoped credential check inserted immediately after `await _deleteConflictingSandbox(page, provider)`
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] `CHANGELOG.md` updated with entry under `### Fixed`
- [ ] Committed and pushed to `feat/v0.1.4`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(sandbox): scope early-exit credential check to provider card — unscoped check picks AWS creds for Azure
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any code file other than `playwright/lib/sandbox.js` (`CHANGELOG.md` and `memory-bank/` updates are expected)
- Do NOT commit to `main` — work on `feat/v0.1.4`
- Do NOT change the `_deleteConflictingSandbox` or `_findScopedButton` functions
- Do NOT touch `acg_credentials.js` or `providers/azure.js`
