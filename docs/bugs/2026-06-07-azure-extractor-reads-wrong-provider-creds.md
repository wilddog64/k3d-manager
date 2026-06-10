# Bugfix: v0.1.4 — azure extractor and _waitForCredentials read wrong provider credentials

**Branch:** `feat/v0.1.4`
**Files:** `playwright/lib/sandbox.js`, `playwright/providers/azure.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

`make credential-test PROVIDER=az` outputs `AZURE_USERNAME/PASSWORD/SUBSCRIPTION_ID/TENANT_ID`
but the values are the current AWS sandbox credentials, not Azure credentials.

**Root cause — two defects:**

1. `_waitForCredentials(page)` (line 165) polls for any `input[aria-label="Copyable input"]`
   globally. When the AWS panel is already open with credentials, `_waitForCredentials`
   finds the AWS inputs immediately and returns — the Azure sandbox never gets to populate.

2. `azure.js extractCredentials` reads all `input[aria-label="Copyable input"]` on the page,
   then applies label matching ("Username" → AZURE_USERNAME, "Password" → AZURE_PASSWORD,
   positional fallback for subscription/tenant). The AWS "cloud_user" + password + key + secret
   map cleanly into the four AZURE_* vars.

The visible symptom: log says `AZURE_USERNAME=***` but the browser shows the AWS sandbox panel
with `cloud_user` credentials.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: scope `_waitForCredentials` to provider card

**Exact old block (lines 165–180):**

```javascript
async function _waitForCredentials(page) {
  console.error('INFO: Waiting for credentials to populate (up to 420s)...');
  const deadline = Date.now() + 420000;
  while (Date.now() < deadline) {
    await _dismissExtendYourSessionDialog(page);
    const inputs = page.locator('input[aria-label="Copyable input"]');
    if (await inputs.count() > 0) {
      const value = await inputs.first().inputValue().catch(() => '');
      if (value.trim().length > 0) {
        return;
      }
    }
    await page.waitForTimeout(2000);
  }
  throw new Error('Locator polling timed out after 420000ms waiting for input[aria-label="Copyable input"] to have a non-empty value.');
}
```

**Exact new block:**

```javascript
async function _waitForCredentials(page, providerLabel) {
  console.error(`INFO: Waiting for ${providerLabel} credentials to populate (up to 420s)...`);
  const deadline = Date.now() + 420000;
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
}
```

### Change 2 — `playwright/lib/sandbox.js`: update all three `_waitForCredentials` callers

All three calls are inside `startSandbox` which has `providerLabel` in scope.

**Exact old block (line 335 — after start button disabled):**
```javascript
    await _waitForCredentials(page);
  } else if (openButton) {
```

**Exact new block:**
```javascript
    await _waitForCredentials(page, providerLabel);
  } else if (openButton) {
```

---

**Exact old block (line 366 — after open/start flow):**
```javascript
    await _waitForCredentials(page);
  } else if (resumeButton) {
```

**Exact new block:**
```javascript
    await _waitForCredentials(page, providerLabel);
  } else if (resumeButton) {
```

---

**Exact old block (line 371 — after resume):**
```javascript
    await _waitForCredentials(page);
  }
}
```

**Exact new block:**
```javascript
    await _waitForCredentials(page, providerLabel);
  }
}
```

---

### Change 3 — `playwright/providers/azure.js`: scope extractor to Azure provider card

**Exact old block (entire file, lines 1–42):**

```javascript
async function extractCredentials(page, outputFn) {
  await page.waitForSelector('input[aria-label="Copyable input"]', { timeout: 15000 });
  const inputs = await page.locator('input[aria-label="Copyable input"]').all();
  console.error(`INFO: Found ${inputs.length} copyable inputs.`);

  let username, password, subscriptionId, tenantId;
  for (let i = 0; i < inputs.length; i++) {
    const val = await inputs[i].inputValue().catch(() => '');
    const parent = await inputs[i].evaluateHandle(el => el.closest('div')?.parentElement ?? null);
    const text = parent ? await parent.evaluate(el => el.innerText || '') : '';
    const textLower = text.toLowerCase();

    if (textLower.includes('username') || textLower.includes('email')) {
      username = val;
    } else if (textLower.includes('password')) {
      password = val;
    } else if (textLower.includes('subscription')) {
      subscriptionId = val;
    } else if (textLower.includes('tenant')) {
      tenantId = val;
    }
  }

  if (!username && inputs.length >= 1) username = await inputs[0].inputValue().catch(() => '');
  if (!password && inputs.length >= 2) password = await inputs[1].inputValue().catch(() => '');
  if (!subscriptionId && inputs.length >= 3) subscriptionId = await inputs[2].inputValue().catch(() => '');
  if (!tenantId && inputs.length >= 4) tenantId = await inputs[3].inputValue().catch(() => '');

  if (!username || !password) {
    throw new Error('Could not find Azure Username and Password credentials');
  }

  const creds = {
    AZURE_USERNAME: username.trim(),
    AZURE_PASSWORD: password.trim(),
  };
  if (subscriptionId) creds.AZURE_SUBSCRIPTION_ID = subscriptionId.trim();
  if (tenantId) creds.AZURE_TENANT_ID = tenantId.trim();
  outputFn(creds);
}

module.exports = { extractCredentials };
```

**Exact new block:**

```javascript
async function extractCredentials(page, outputFn) {
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
      .map(inp => {
        let node = inp.parentElement;
        let fieldLabel = null;
        for (let j = 0; j < 6; j++) {
          if (!node) break;
          const t = node.innerText || '';
          if (!fieldLabel) {
            if (/username|email/i.test(t)) fieldLabel = 'username';
            else if (/password/i.test(t)) fieldLabel = 'password';
            else if (/subscription/i.test(t)) fieldLabel = 'subscription';
            else if (/tenant/i.test(t)) fieldLabel = 'tenant';
          }
          node = node.parentElement;
        }
        return { value: inp.value, fieldLabel };
      });
  });

  console.error(`INFO: Found ${azureInputs.length} Azure-scoped copyable inputs.`);

  if (azureInputs.length === 0) {
    throw new Error('No credentials found in Azure provider card');
  }

  let username, password, subscriptionId, tenantId;
  for (const { value: val, fieldLabel } of azureInputs) {
    if (fieldLabel === 'username' && !username) username = val;
    else if (fieldLabel === 'password' && !password) password = val;
    else if (fieldLabel === 'subscription' && !subscriptionId) subscriptionId = val;
    else if (fieldLabel === 'tenant' && !tenantId) tenantId = val;
  }

  if (!username && azureInputs.length >= 1) username = azureInputs[0].value;
  if (!password && azureInputs.length >= 2) password = azureInputs[1].value;
  if (!subscriptionId && azureInputs.length >= 3) subscriptionId = azureInputs[2].value;
  if (!tenantId && azureInputs.length >= 4) tenantId = azureInputs[3].value;

  if (!username || !password) {
    throw new Error('Could not find Azure Username and Password credentials');
  }

  const creds = {
    AZURE_USERNAME: username.trim(),
    AZURE_PASSWORD: password.trim(),
  };
  if (subscriptionId) creds.AZURE_SUBSCRIPTION_ID = subscriptionId.trim();
  if (tenantId) creds.AZURE_TENANT_ID = tenantId.trim();
  outputFn(creds);
}

module.exports = { extractCredentials };
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Scope `_waitForCredentials` to provider card; update 3 callers to pass `providerLabel` |
| `playwright/providers/azure.js` | Replace global input scan with Azure-card-scoped DOM walk |
| `CHANGELOG.md` | Add `[Unreleased]` entry under `### Fixed` |
| `memory-bank/activeContext.md` | Update current status |
| `memory-bank/progress.md` | Update v0.1.4 track |

---

## Rules

- `node --check playwright/lib/sandbox.js` — zero errors
- `node --check playwright/providers/azure.js` — zero errors
- No other files touched (do NOT touch `acg_credentials.js`, `providers/aws.js`, `providers/gcp.js`, `_deleteConflictingSandbox`, `_findScopedButton`)

---

## Definition of Done

- [ ] `_waitForCredentials` signature changed to `(page, providerLabel)`
- [ ] `_waitForCredentials` body uses provider-scoped DOM walk (12-ancestor limit) instead of global locator
- [ ] All three `_waitForCredentials(page)` callers changed to `_waitForCredentials(page, providerLabel)`
- [ ] `azure.js` uses `page.waitForFunction` scoped to Azure card (not global `waitForSelector`)
- [ ] `azure.js` uses `page.evaluate` with 12-ancestor DOM walk to collect only Azure-card inputs
- [ ] `azure.js` throws `'No credentials found in Azure provider card'` when `azureInputs.length === 0`
- [ ] `node --check` passes on both changed files
- [ ] `CHANGELOG.md` updated with entry under `### Fixed`
- [ ] Committed and pushed to `feat/v0.1.4`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA and task status

**Commit message (exact):**
```
fix(azure): scope _waitForCredentials and azure extractor to provider card — global scan picks AWS creds
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js` and `playwright/providers/azure.js` (plus `CHANGELOG.md` and `memory-bank/`)
- Do NOT commit to `main` — work on `feat/v0.1.4`
- Do NOT change `_deleteConflictingSandbox`, `_findScopedButton`, or `startSandbox` logic
- Do NOT touch `acg_credentials.js`, `providers/aws.js`, or `providers/gcp.js`
- Do NOT change the 12-ancestor depth limit (matches the existing scoped credential check pattern)
