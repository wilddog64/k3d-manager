# Issue: Pluralsight 'Oops! Something went wrong' in Antigravity

**Date:** 2026-03-28
**Branch:** `k3d-manager-v0.9.19`

## Problem
During the implementation of the static Playwright script for `acg_get_credentials`, the Antigravity browser consistently showed an error message: "Oops! Something went wrong. We could not fetch your user information." This occurred on all Pluralsight pages (`/`, `/hands-on`, `/hands-on/playground/cloud-sandboxes`).

## Analysis
- **CDP Connection:** Successfully established via `chromium.connectOverCDP('http://localhost:9222')`.
- **Browser Context:** Cookies for `app.pluralsight.com` and `.pluralsight.com` were present in the context.
- **Error Behavior:** The page shell loads, but the `#root` content renders an error component. Network logs showed aborted requests to `https://labs.pluralsight.com/graphql`.
- **Session state:** Clearing cookies and re-logging in via the Antigravity window (per user confirmation) did not resolve the issue for the Playwright-controlled page.
- **Impact:** Real DOM selectors for the "Start Sandbox" button and the AWS credentials panel could not be verified against a live page.

## Action Taken
- Implemented `scripts/playwright/acg_credentials.js` with dual-path selectors (`input[aria-label="Copyable input"]` confirmed live) and positional fallback.
- Updated `scripts/plugins/acg.sh` to call the static script via `node "$playwright_script" "$sandbox_url"`.
- **Root cause of CDP issue:** Chrome was launched without `--password-store=basic`, causing macOS Keychain `errSecInteractionNotAllowed` to block the debug port from binding. Chrome relaunched with the flag resolved the CDP connection.
- **Live verification:** After relaunching Chrome with `--password-store=basic` and signing in to Pluralsight manually, `acg_get_credentials` successfully extracted AWS credentials and wrote them to `~/.aws/credentials`. `aws sts get-caller-identity` returned a valid account ID, confirming end-to-end success.
- All BATS tests passed.

## Resolution
Issue resolved. The "Oops" error and CDP binding failure were both caused by Chrome running without `--password-store=basic`. Once relaunched with that flag and after manual Pluralsight login, the static Playwright script extracted live credentials successfully.
