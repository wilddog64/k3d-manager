# Bug: Start Sandbox Button Disabled Timeout (ACG AWS/GCP)

**Date:** 2026-04-23
**Status:** OPEN
**Severity:** CRITICAL (Blocker)

## Summary

The `acg-up` automation fails with a 30000ms timeout when attempting to click the "Start Sandbox" button. Playwright correctly identifies the button, but it is in a `disabled` state in the DOM.

## Terminal Output

```text
ERROR: locator.click: Timeout 30000ms exceeded.
Call log:
  - waiting for locator('button:has-text("Start Sandbox")').first()
    - locator resolved to <button disabled data-heap-id="Hands-on Playground - Click - AWS Sandbox - Start Sandbox" class="pando-w_[100%] pando-flex-g_1 sm:pando-w_fit lg:pando-flex-g_0 pando-button pando-button--palette_action pando-button--size_lg pando-button--usage_filled">…</button>
  - attempting click action
    2 × waiting for element to be visible, enabled and stable
      - element is not enabled
    - retrying click action
    - waiting 20ms
    2 × waiting for element to be visible, enabled and stable
      - element is not enabled
    - retrying click action
      - waiting 100ms
    56 × waiting for element to be visible, enabled and stable
       - element is not enabled
     - retrying click action
       - waiting 500ms

make: *** [up] Error 1
```

## Root Cause Analysis (RCA)

1. **State Machine Deadlock:** The automation script assumes the sandbox needs to be started and attempts to click the "Start Sandbox" button.
2. **Element State:** The button is found but has the `disabled` attribute. 
3. **Trigger Scenarios:**
   - **Sandbox Already Provisioned:** The sandbox is already running, and the "Start Sandbox" button is disabled by the ACG application in favor of "Open Console" or "Clear Sandbox".
   - **Provisioning Lag:** The UI is in a transient state where the button is visible but not yet interactable.
   - **Latching Failure:** `acg_credentials.js` or `acg_extend.js` does not check if the sandbox is already active before trying to start it.

## Recommended Fix

Update the automation to check for an already-active sandbox state before attempting to click "Start Sandbox". If the button is disabled, the script should look for "Open Console" or "Clear Sandbox" to confirm the environment is ready for latching.

## Files Implicated
- `scripts/playwright/acg_credentials.js` (primary — this is where the timeout occurs)
- `scripts/playwright/acg_extend.js` (not in scope — its Ghost State recovery uses `force: true` and is a different flow)

---

## Fix

One hunk — `scripts/playwright/acg_credentials.js` only.

**Location:** lines 352–355 inside the `else` block of `credentialsAlreadyVisible`.

**Old:**
```js
      if (await startButton.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Clicking Start Sandbox...');
        await startButton.click();
        await _waitForCredentials();
```

**New:**
```js
      if (await startButton.isVisible({ timeout: 5000 }).catch(() => false)) {
        const _startEnabled = await startButton.isEnabled({ timeout: 1000 }).catch(() => false);
        if (_startEnabled) {
          console.error('INFO: Clicking Start Sandbox...');
          await startButton.click();
        } else {
          console.error('INFO: Start Sandbox button is disabled — sandbox already running; waiting for credentials...');
        }
        await _waitForCredentials();
```

The `} else if (await openButton...` line that follows is unchanged.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `scripts/playwright/acg_credentials.js` lines 311–373 in full (the Start/Open flow block).
3. Read `memory-bank/activeContext.md`.
4. Run `node --check scripts/playwright/acg_credentials.js` — must exit 0 before and after.
5. Do NOT touch `acg_extend.js`.

---

## Rules

- `node --check scripts/playwright/acg_credentials.js` must exit 0.
- Only `scripts/playwright/acg_credentials.js` may be touched.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `scripts/playwright/acg_credentials.js` lines 352–355 match the **New** block above exactly.
2. The `} else if (await openButton...` continuation is unchanged.
3. `node --check scripts/playwright/acg_credentials.js` exits 0.
4. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(acg-credentials): skip disabled Start Sandbox button; wait for credentials instead
   ```
5. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
6. `memory-bank/activeContext.md`: update "Start Sandbox Disabled Timeout" from OPEN → COMPLETE with real commit SHA.
7. `memory-bank/progress.md`: add `[x] **Start Sandbox Disabled Timeout** — COMPLETE (<sha>)` under Known Bugs / Gaps.
8. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `scripts/playwright/acg_credentials.js`.
- Do NOT commit to `main`.
- Do NOT touch `acg_extend.js`.
- Do NOT add `force: true` to the startButton click — that bypasses the disabled check and hangs anyway.
- Do NOT restructure the Start/Open/Resume if-else chain — only modify the `startButton` branch.
