# Issue: Remove ACG sandbox 404 → targetUrl retry while account is banned

**Date:** 2026-06-16
**Component:** lib-acg / `playwright/lib/sandbox.js` (subtree under `scripts/lib/acg/`)
**Status:** Open — spec filed, fix must go through lib-acg upstream

## Symptom

`make up CLUSTER_PROVIDER=k3s-aws` (job `4570a5e0`) terminates with SIGTERM after:

```
INFO: Sandbox route not active (https://s2.pluralsight.com/404.html) — retrying directly via targetUrl...
WARN: Timed out waiting for sandbox buttons or credentials — proceeding anyway
make: *** [up] Terminated: 15
```

The Playwright extractor lands on `s2.pluralsight.com/404.html`, then re-navigates to `targetUrl` and waits ~minutes for sandbox buttons that will never appear.

## Investigation

- `scripts/lib/acg/playwright/lib/sandbox.js:472-473` — `startSandbox()` detects the inactive sandbox route and retries via `page.goto(targetUrl, ...)`. This retry was added by lib-acg `feat/v0.1.4` (merge `83bea63`) to recover from stale Hands-on hops.
- The ACG account has been banned for 72 hours, so every navigation to the sandbox path resolves to the `404.html` placeholder. The retry cannot succeed; it only consumes the wait budget until `make` is killed.
- No local edit was made — `git status` on `k3d-manager-v1.7.1` shows only `memory-bank/*` modified; `sandbox.js` is untouched. There is nothing to push.

## Root Cause

Defensive 404 → `targetUrl` retry in `startSandbox()` assumes a transient bad hop. During an account ban the 404 is permanent, so the retry burns the run timeout instead of failing fast.

## Fix Applied

None yet — direct edit is blocked by two rules:

1. Troubleshooting scope restricts writes to `docs/issues/` only.
2. `scripts/lib/acg/` is a subtree; per `feedback_lib_acg_subtree_discipline.md` the change must land on `lib-acg` first, then be subtree-pulled.

## Proposed Fix (for Codex spec on `lib-acg`)

In `playwright/lib/sandbox.js` `startSandbox()`:

- When `page.url()` matches `s2.pluralsight.com/404.html`, throw a fast-fail error (e.g. `SANDBOX_404_ACCOUNT_LIKELY_BANNED`) instead of retrying via `targetUrl`.
- Keep the retry path for non-404 inactive routes (the original v0.1.4 case).
- Add a BATS / Playwright unit covering the 404 fast-fail branch.

## Notes

- Related: `scripts/lib/acg/docs/bugs/2026-06-07-hands-on-retry-navigates-to-404.md`, `scripts/lib/acg/docs/bugs/2026-06-09-acg-sandbox-expired-login-redirect.md`.
- Once lib-acg ships the fix, run `git subtree pull --prefix=scripts/lib/acg lib-acg <branch> --squash` on a k3d-manager feature branch and push.
- User is blocked for 72h regardless; this fix only changes the failure mode from "hang until SIGTERM" to "fail fast with a clear reason".
