# Issue: Remove ACG sandbox 404 retry — masks ACG ban / makes timeout worse

**Date:** 2026-06-15
**Component:** lib-acg / `scripts/lib/acg/playwright/lib/sandbox.js`
**Status:** Fixed (issue filed; code change required in lib-acg subtree)

## Symptom

`make up CLUSTER_PROVIDER=k3s-aws` from the webhook job `4570a5e0` terminated after
the credential extractor blocked for the full timeout window:

```
INFO: Sandbox route not active (https://s2.pluralsight.com/404.html) — retrying directly via targetUrl...
WARN: Timed out waiting for sandbox buttons or credentials — proceeding anyway
make: *** [up] Terminated: 15
ERROR: make up CLUSTER_PROVIDER=k3s-aws exited -15
```

The parent webhook then killed `make` (SIGTERM/-15).

## Investigation

The retry path lives in `scripts/lib/acg/playwright/lib/sandbox.js` lines 467–480:

```javascript
let sandboxEntryReady = await _waitForSandboxEntrySoft(page, 30000);
const retryPathname = (() => {
  try { return new URL(targetUrl).pathname; } catch { return ''; }
})();
if (!sandboxEntryReady && retryPathname.includes('cloud-sandboxes') && !page.url().includes('cloud-sandboxes')) {
  console.error(`INFO: Sandbox route not active (${page.url()}) — retrying directly via targetUrl...`);
  await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
  const postRetryUrl = page.url();
  if (postRetryUrl.includes('/id') || postRetryUrl.includes('sign-in') || postRetryUrl.includes('login')) {
    await _capturePageDebugState(page, providerLabel, `Sandbox retry redirected to ${postRetryUrl}`);
    throw new Error(`Pluralsight session expired — redirected to ${postRetryUrl}. Re-open or re-create the sandbox and retry.`);
  }
  sandboxEntryReady = await _waitForSandboxEntrySoft(page, 30000);
}
```

When Pluralsight serves `s2.pluralsight.com/404.html` because the account is in a
72-hour ACG cooldown/ban, no retry can succeed. The retry block instead burns
another `goto` (60s) + soft wait (30s) before falling through to the "proceeding
anyway" warning, and the surrounding webhook kills the job.

## Root Cause

The 404 page is not a transient routing glitch — it is the signal that the ACG
account is temporarily banned (72-hour cooldown). Retrying via `targetUrl` cannot
recover from this, it only delays the failure long enough for the webhook to
SIGTERM the run.

## Fix Applied

Filed this issue. Code change must land in the **lib-acg** repo (subtree source),
not in k3d-manager directly, per the lib-acg subtree discipline rule.

Required change in `playwright/lib/sandbox.js` (lib-acg):

- Remove the `if (!sandboxEntryReady && retryPathname.includes('cloud-sandboxes') && !page.url().includes('cloud-sandboxes')) { ... }` retry block (lines 471–480 in the current k3d-manager copy).
- When `_waitForSandboxEntrySoft` returns false AND the current URL is the
  Pluralsight 404 page (`s2.pluralsight.com/404.html`), throw a fast-fail error
  like: `ACG sandbox route returned 404 — account may be in 72-hour cooldown.
  Re-check ACG account status before retrying.`
- Keep the existing `sign-in / login / /id` session-expired branch.

After lib-acg PR merges:
1. `git subtree pull --prefix=scripts/lib/acg <lib-acg-remote> <branch> --squash`
2. Verify `scripts/lib/acg/playwright/lib/sandbox.js` no longer contains the retry block.

## Notes

- Related prior bug specs (kept the retry alive across earlier fixes):
  - `scripts/lib/acg/docs/bugs/2026-06-07-hands-on-retry-navigates-to-404.md`
  - `scripts/lib/acg/docs/bugs/2026-06-07-extend-dialog-force-and-early-creds-check.md`
- Companion job-output issue (sibling): `docs/issues/2026-06-15-acg-credential-extraction-sandbox-404-timeout.md`
- Webhook surface: `bin/k3dm-webhook` `_run_cluster` raises `make up ... exited -15`
  when the parent SIGTERMs — fast-failing inside Playwright lets the webhook
  surface the real reason instead of the SIGTERM trace.
- ACG ban context: user account is banned by ACG for 72 hours, so retry is not
  recoverable in any case.
