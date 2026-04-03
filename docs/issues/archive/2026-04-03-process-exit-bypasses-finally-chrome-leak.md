# Issue: process.exit(0) Bypasses finally Block — Chrome Left Open

**Date**: 2026-04-03
**Repo**: k3d-manager
**Fixed in**: `b06451b`
**File**: `scripts/playwright/acg_credentials.js`

## Symptom

Every successful run of `acg_get_credentials` left a Chrome window open. The process exited
with code 0 but the Chrome instance launched by `launchPersistentContext` was never closed.

## Root Cause

The success path in `extractCredentials()` called `process.exit(0)` directly inside the `try` block:

```js
if (accessKey && secretKey) {
  console.log(`AWS_ACCESS_KEY_ID=...`);
  ...
  process.exit(0);   // ← Node.js terminates immediately; finally never runs
}
```

In Node.js, `process.exit()` terminates the process immediately without executing any pending
`finally` blocks. The `finally` block that closes the browser context:

```js
} finally {
  if (_cdpBrowser) {
    await _cdpBrowser.disconnect().catch(() => {});
  } else if (browserContext) {
    await browserContext.close();   // ← never reached
  }
}
```

was never reached on the success path, leaving the Chrome process running.

## Why It Wasn't Caught Earlier

- Before the `launchPersistentContext` refactor (`f7f15c5`), the script connected via CDP
  (`connectOverCDP`) to an already-running Chrome. Disconnecting didn't close Chrome — that was
  intentional. Leaking the connection was invisible.
- After the refactor, `launchPersistentContext` makes Playwright the owner of the Chrome process.
  Playwright expects `browserContext.close()` to be called to terminate it. The leak became visible
  as a persistent Chrome window after each run.

## Fix

Replace `process.exit(0)` with `return` so the function returns normally, the `finally` block
executes, and Chrome is closed before the process exits:

```js
// Before
process.exit(0);

// After
return;
```

Node.js exits with code 0 naturally once all async work completes and the event loop drains.

## Files Affected

- `scripts/playwright/acg_credentials.js` — one line changed

## Not Affected

- `scripts/playwright/acg_extend.js` — success path uses `console.log(...)` with no `process.exit`;
  `finally` runs correctly.
