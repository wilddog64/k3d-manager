# Issue: CDP Probe Skipped on Non-First-Run — Script Navigates to 404

**Date**: 2026-04-03
**Branch**: k3d-manager-v1.0.2
**Fixed in**: (see spec `docs/plans/v1.0.4-fix-cdp-probe-always-run.md`)

## Symptom

`acg_get_credentials` navigates to `https://app.pluralsight.com/cloud-playground/cloud-sandboxes`
and gets a 404 error, even when the user already has Chrome open on the AWS sandbox page.

## Root Cause

Two bugs combine:

**Bug 1 — CDP probe is gated behind `IS_FIRST_RUN`**

The CDP probe that detects an existing Chrome session runs only when the playwright-auth dir is
empty. Once the user has bootstrapped (dir is populated), `IS_FIRST_RUN = false` and the probe
is skipped entirely. The script goes straight to `launchPersistentContext`, opening a new Chrome
instance instead of reusing the existing session.

**Bug 2 — Navigation destroys the existing sandbox page**

Even when the CDP probe runs and finds the existing page, the navigation logic compares
`currentPathname` to `targetPathname`. Since the actual sandbox URL
(`/hands-on/playground/cloud-sandboxes`) doesn't match the target URL
(`/cloud-playground/cloud-sandboxes`), the script navigates away — replacing the live sandbox
page with a 404.

## Impact

- Script always opens a new Chrome window after the first run
- If Chrome is already on the AWS sandbox page, that page is destroyed by a 404 navigation
- Credential extraction always fails on subsequent runs without manual re-navigation

## Fix

1. Remove `IS_FIRST_RUN` gate from the CDP probe — always probe first
2. Add sandbox-ready check before navigation — if the page already shows the sandbox panel
   (Start Sandbox button or populated credential inputs), skip all navigation entirely
