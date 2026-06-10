# Bugfix: v0.1.4 — hands-on retry URL 404s, causing Playwright to lose the sandbox page

**Branch:** `feat/v0.1.4`
**Files:** `playwright/lib/sandbox.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

When `_waitForSandboxEntrySoft` times out (page drifted away from cloud-sandboxes URL),
the retry block in `startSandbox` navigates to `https://app.pluralsight.com/hands-on`
before going back to `targetUrl`. That URL returns a Pluralsight 404 page
(`s2.pluralsight.com/404.html`). The Playwright script then operates on the 404 page,
finds no sandbox buttons, and the whole flow fails.

**Root cause (lines 285–293):**

```javascript
if (!sandboxEntryReady && retryPathname.includes('cloud-sandboxes') && !page.url().includes('cloud-sandboxes')) {
  console.error(`INFO: Sandbox route not active (${page.url()}) — retrying via Hands-on route...`);
  await page.goto('https://app.pluralsight.com/hands-on', { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForFunction(() => { ... }, { timeout: 15000 }).catch(...);
  await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
  sandboxEntryReady = await _waitForSandboxEntrySoft(page, 30000);
}
```

The intermediate `hands-on` navigation is unnecessary. If the page drifted, going directly
to `targetUrl` is sufficient and correct.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: remove intermediate `hands-on` navigation from retry block

**Exact old block (lines 284–294):**

```javascript
  if (!sandboxEntryReady && retryPathname.includes('cloud-sandboxes') && !page.url().includes('cloud-sandboxes')) {
    console.error(`INFO: Sandbox route not active (${page.url()}) — retrying via Hands-on route...`);
    await page.goto('https://app.pluralsight.com/hands-on', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForFunction(() => {
      return document.readyState === 'complete' ||
        Boolean(document.querySelector('a[href*="cloud-sandboxes"]')) ||
        document.body.innerText.includes('Cloud Sandboxes');
    }, { timeout: 15000 }).catch(() => console.error('WARN: Hands-on route did not settle before sandbox retry'));
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    sandboxEntryReady = await _waitForSandboxEntrySoft(page, 30000);
  }
```

**Exact new block:**

```javascript
  if (!sandboxEntryReady && retryPathname.includes('cloud-sandboxes') && !page.url().includes('cloud-sandboxes')) {
    console.error(`INFO: Sandbox route not active (${page.url()}) — navigating directly back to sandbox URL...`);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    sandboxEntryReady = await _waitForSandboxEntrySoft(page, 30000);
  }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Remove `hands-on` intermediate navigation; go directly to `targetUrl` |
| `CHANGELOG.md` | Add `[Unreleased]` entry under `### Fixed` |
| `memory-bank/activeContext.md` | Update current status |
| `memory-bank/progress.md` | Update v0.1.4 track |

---

## Rules

- `node --check playwright/lib/sandbox.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] The `page.goto('https://app.pluralsight.com/hands-on', ...)` line and its `waitForFunction` call are removed
- [ ] The retry block goes directly to `page.goto(targetUrl, ...)` then `_waitForSandboxEntrySoft`
- [ ] The log message updated to `'navigating directly back to sandbox URL...'`
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] `CHANGELOG.md` updated under `### Fixed`
- [ ] Committed and pushed to `feat/v0.1.4`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(sandbox): remove hands-on intermediate navigation from retry block — URL 404s and loses sandbox page
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT remove the entire retry block — only the intermediate `hands-on` navigation inside it
- Do NOT modify any file other than `playwright/lib/sandbox.js` (plus `CHANGELOG.md` and `memory-bank/`)
- Do NOT commit to `main` — work on `feat/v0.1.4`
- Do NOT touch any other function in `sandbox.js`
