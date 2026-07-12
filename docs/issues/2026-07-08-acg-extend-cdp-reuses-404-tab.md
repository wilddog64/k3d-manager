# Issue: 2026-07-08 — ACG extend reuses a CDP Pluralsight 404 tab and never navigates to Cloud Sandboxes

## What failed

The extend watcher reported:

```text
ERROR: Extend button not found or not visible after multiple attempts (including recovery)
INFO: [acg] Extend failed — open https://app.pluralsight.com/hands-on/playground/cloud-sandboxes to extend manually
INFO: [acg] Extending sandbox TTL...
INFO: [acg] Extending ACG sandbox TTL at https://app.pluralsight.com/hands-on/playground/cloud-sandboxes...
INFO: [acg] acg_extend failed: INFO: Connected via CDP to existing browser session.
INFO: Already on Pluralsight page: https://s2.pluralsight.com/404.html
WARN: Auto Shutdown text not found. Proceeding anyway.
WARN: Could not save extend failure screenshot: page.screenshot: Timeout 30000ms exceeded.
Call log:
  - taking page screenshot
  - waiting for fonts to load...
  - fonts loaded

ERROR: Extend button not found or not visible after multiple attempts (including recovery)
INFO: [acg] Extend failed — open https://app.pluralsight.com/hands-on/playground/cloud-sandboxes to extend manually
INFO: [acg] Instance gone — watcher stopping.
```

## Root cause

`scripts/lib/foundation/scripts/lib/acg/playwright/acg_extend.js` selected the first tab
whose hostname ended with `.pluralsight.com`, then used that same hostname-only check to
decide whether navigation was needed.

That allowed a stale CDP tab like:

```text
https://s2.pluralsight.com/404.html
```

to be treated as a valid "already on Pluralsight" page even though it was not on the
Cloud Sandboxes route. Once stuck there:

- `Auto Shutdown` text is absent
- no extend selectors can match
- the recovery path operates from the wrong page

`acg_restart.js` already had the safer route-based behavior; `acg_extend.js` had not been
updated to match it.

## Fix

Apply the fix upstream-first in `lib-foundation`, then subtree-sync it into k3d-manager:

- upstream lib-foundation commit:
  `011f6f859f1834ea8d761a6a693c0da21a972202`
  `fix(acg): route extend through sandbox-page checks instead of stale Pluralsight tabs`
- k3d-manager subtree sync commit:
  `e61a2ba6`

The fix changes `acg_extend.js` to:

- normalize legacy `cloud-playground/cloud-sandboxes` URLs
- prefer an actual sandbox tab over a generic Pluralsight tab
- treat only sandbox routes as "already on the right page"
- force navigation to the target Cloud Sandboxes URL when the reused CDP tab is a non-sandbox page
- fail explicitly if that navigation redirects to sign-in

A new regression test covers the `s2.pluralsight.com/404.html` case.

## Validation

Upstream in `lib-foundation`:

- `node --check scripts/lib/acg/playwright/acg_extend.js`
- `cd scripts/lib/acg && npm run check`
- `cd scripts/lib/acg && npm test`

Downstream in `k3d-manager`:

- `./scripts/k3d-manager _agent_audit`

## Follow-up

The fix is now in the subtree copy, but the user-reported live extend path itself was not
re-run in this session, so the change is test-verified rather than live-verified.
