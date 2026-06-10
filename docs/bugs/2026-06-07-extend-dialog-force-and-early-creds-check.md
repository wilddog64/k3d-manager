# Bugfix: v0.1.4 — Extend dialog click missing force:true; credentialsAlreadyVisible check too late

**Branch:** `feat/v0.1.4`
**Files:** `playwright/lib/sandbox.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

Two bugs in `startSandbox`:

### Bug A — Extend dialog click silently fails (repeated WARN)

`_dismissExtendYourSessionDialog` uses `extendBtn.click().catch(() => {})` without
`force: true`. React apps require `force: true` for reliable synthetic event dispatch.
The click fails silently; the dialog stays visible. `startSandbox` calls
`_dismissExtendYourSessionDialog` at two points (before and after `_waitForSandboxEntrySoft`),
so both attempts log the WARN:

```
INFO: "Extend Your Session" dialog detected — clicking Extend button...
WARN: "Extend Your Session" dialog still visible — credentials populate on either Cancel or Extend; continuing
INFO: "Extend Your Session" dialog detected — clicking Extend button...
WARN: "Extend Your Session" dialog still visible — credentials populate on either Cancel or Extend; continuing
```

### Bug B — credentialsAlreadyVisible checked after _deleteConflictingSandbox

If the target provider's sandbox is already running with credentials populated, the script
still runs `_deleteConflictingSandbox` (which tries and fails to find/delete a non-conflicting
sandbox) before finally checking `credentialsAlreadyVisible`. This causes unnecessary deletion
attempts and log noise when the sandbox was already in the correct state.

**Observed symptom:**
```
INFO: Running AWS sandbox detected — deleting before starting Azure...
WARN: Delete Sandbox not found for AWS — proceeding anyway
INFO: Azure credentials already populated — skipping Start/Open flow
```

The deletion attempt should never have run — Azure credentials were already there.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: add `force: true` to Extend button click

**Exact old line (inside `_dismissExtendYourSessionDialog`):**

```javascript
    await extendBtn.click().catch(() => {});
```

**Exact new line:**

```javascript
    await extendBtn.click({ force: true }).catch(() => {});
```

---

### Change 2 — `playwright/lib/sandbox.js`: move `credentialsAlreadyVisible` check before `_deleteConflictingSandbox`

**Exact old block (lines 280–317 in current file — the section from `_dismissExtendYourSessionDialog` through `credentialsAlreadyVisible` return):**

```javascript
  await _dismissExtendYourSessionDialog(page);
  let sandboxEntryReady = await _waitForSandboxEntrySoft(page, 30000);
  const retryPathname = (() => {
    try { return new URL(targetUrl).pathname; } catch { return ''; }
  })();
  if (!sandboxEntryReady && retryPathname.includes('cloud-sandboxes') && !page.url().includes('cloud-sandboxes')) {
    console.error(`INFO: Sandbox route not active (${page.url()}) — navigating directly back to sandbox URL...`);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    sandboxEntryReady = await _waitForSandboxEntrySoft(page, 30000);
  }
  await _dismissExtendYourSessionDialog(page);
  if (!sandboxEntryReady) {
    console.error('WARN: Timed out waiting for sandbox buttons or credentials — proceeding anyway');
  }

  await _deleteConflictingSandbox(page, provider);

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

  if (credentialsAlreadyVisible) {
    console.error(`INFO: ${providerLabel} credentials already populated — skipping Start/Open flow`);
    return;
  }
```

**Exact new block (move credentialsAlreadyVisible check BEFORE _deleteConflictingSandbox):**

```javascript
  await _dismissExtendYourSessionDialog(page);
  let sandboxEntryReady = await _waitForSandboxEntrySoft(page, 30000);
  const retryPathname = (() => {
    try { return new URL(targetUrl).pathname; } catch { return ''; }
  })();
  if (!sandboxEntryReady && retryPathname.includes('cloud-sandboxes') && !page.url().includes('cloud-sandboxes')) {
    console.error(`INFO: Sandbox route not active (${page.url()}) — navigating directly back to sandbox URL...`);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    sandboxEntryReady = await _waitForSandboxEntrySoft(page, 30000);
  }
  await _dismissExtendYourSessionDialog(page);
  if (!sandboxEntryReady) {
    console.error('WARN: Timed out waiting for sandbox buttons or credentials — proceeding anyway');
  }

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

  if (credentialsAlreadyVisible) {
    console.error(`INFO: ${providerLabel} credentials already populated — skipping Start/Open flow`);
    return;
  }

  await _deleteConflictingSandbox(page, provider);
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Add `force: true` to Extend button click; move `credentialsAlreadyVisible` before `_deleteConflictingSandbox` |
| `CHANGELOG.md` | Add `[Unreleased]` entry under `### Fixed` |
| `memory-bank/activeContext.md` | Update current status |
| `memory-bank/progress.md` | Update v0.1.4 track |

---

## Rules

- `node --check playwright/lib/sandbox.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] `extendBtn.click({ force: true })` — `force: true` added
- [ ] `credentialsAlreadyVisible` evaluate block and early-return moved to BEFORE `await _deleteConflictingSandbox(page, provider)`
- [ ] `_deleteConflictingSandbox` call remains in place, just after the `credentialsAlreadyVisible` early-return
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] `make check lint test` passes (run in lib-acg repo root)
- [ ] `CHANGELOG.md` updated under `### Fixed`
- [ ] Committed and pushed to `feat/v0.1.4`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(sandbox): add force:true to extend dialog click; check credentialsAlreadyVisible before deletion
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js` (plus `CHANGELOG.md` and `memory-bank/`)
- Do NOT commit to `main` — work on `feat/v0.1.4`
- Do NOT remove or reorder any other logic in `startSandbox`
- Do NOT change `_dismissExtendYourSessionDialog` beyond the single `force: true` addition
- Do NOT touch `azure.js`, `acg_credentials.js`, or any provider file
