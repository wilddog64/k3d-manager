# Issue: sandbox.js addLocatorHandler strict-mode violation blocks credential extraction

**Date:** 2026-06-10
**Component:** scripts/lib/acg/playwright/lib/sandbox.js — startSandbox()
**Status:** Fixed (pending lib-acg upstream PR + subtree pull)

## Symptom

`make up CLUSTER_PROVIDER=k3s-aws` fails at Step 1 — credential extraction — with:

```
ERROR: page.waitForSelector: Error: strict mode violation:
  locator('text=/sandbox has been extended|session extended/i') resolved to 2 elements:
    1) <h3 class="pando-c_neutral.text.300">Session extended</h3>
    2) <p class="pando-mb_md">Your sandbox has been extended.</p>
  Call log:
    - waiting for locator('input[aria-label="Copyable input"]') to be visible
```

The sandbox restart recovery path hits the same error, so `acg-up` exits 1 after exhausting retries.

## Investigation

The error is thrown by the `addLocatorHandler` call in `startSandbox()` at
`scripts/lib/acg/playwright/lib/sandbox.js:408`. Playwright enforces strict mode on the
trigger locator — it must resolve to **exactly one** element. The regex
`/sandbox has been extended|session extended/i` matches both the `<h3>` heading and the
`<p>` body of the "Session extended" toast card, giving 2 matches instead of 1.

The credential extraction (`input[aria-label="Copyable input"]`) never runs because the
`addLocatorHandler` setup throws before the wait is reached.

## Root Cause

Pluralsight's "Session extended" toast card renders two text nodes that both satisfy the
broad regex trigger:
- Heading: `<h3>Session extended</h3>`
- Body: `<p>Your sandbox has been extended.</p>`

Playwright strict mode in `addLocatorHandler` requires a unique match; finding 2 elements
raises `strict mode violation` and aborts the handler registration.

## Fix Applied

Add `.first()` to the trigger locator in `startSandbox()` so Playwright receives exactly
one element regardless of how many toast text nodes are present.

File: `scripts/lib/acg/playwright/lib/sandbox.js` line 408

```diff
-    page.locator('text=/sandbox has been extended|session extended/i'),
+    page.locator('text=/sandbox has been extended|session extended/i').first(),
```

**Delivery path:** fix must go to the upstream lib-acg repo first, then subtree-pull into
k3d-manager. Do not edit `scripts/lib/acg/` directly.

## Notes

- `acg_extend.js` and `acg_restart.js` already use `.first()` on `getByText(...)` for the
  same toast — this fix brings `sandbox.js` into line with that established pattern.
- The restart path in `acg-up` masked the failure (delete + restart sandbox) but hit the
  identical strict-mode error on the second attempt, confirming the bug is in the handler
  setup rather than in transient page state.
