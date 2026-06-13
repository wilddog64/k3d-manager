# Copilot PR #39 Review Findings

**PR:** #39 — `fix(credentials): Azure SP validation, toast dismissal, panel re-open for AWS`
**Branch:** `feat/v0.1.4`
**Fix commit:** `fc3a7e2`

---

## Finding 1 — `sandbox.js:140`: `_dismissExtendYourSessionDialog` dialog selector misses `alertdialog` role

**Flagged:** visibility check only queried `[role="dialog"]` but button selector also covered `[role="alertdialog"]` and `[data-testid="extend-sandbox-modal"]` — inconsistent, silently missed the modal variant.

**Fix:** updated `dialogVisible` evaluate to query all three selectors.

```js
// before
Array.from(document.querySelectorAll('[role="dialog"]'))

// after
Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="alertdialog"], [role="dialog"]'))
```

---

## Finding 2 — `sandbox.js:363`: toast locator too narrow

**Flagged:** `addLocatorHandler` matched only `/sandbox has been extended/i`; "Session extended" variant would not fire the handler.

**Fix:** widened regex to `/sandbox has been extended|session extended/i`.

---

## Finding 3 — `sandbox.js:179`: stale inline comment (depth 6 / no exclusion)

**Flagged:** comment claimed "depth 6, no exclusion" but implementation walks 20 ancestors with provider-exclusion logic.

**Fix:** updated comment to describe actual behavior.

---

## Finding 4 — `azure.js:32`: dead outer `detectLabel()` function

**Flagged:** `detectLabel` defined in Node context outside `page.evaluate` was never called; label detection runs exclusively inside the evaluate closure.

**Fix:** removed the unused function.

---

## Findings 5–6 — `azure.js:63,80`: unused `value` truncation fields in evaluate return

**Flagged:** `value: inp.value.substring(0, 8) + '...'` was included in both `azureScoped` and `allScanned` mapped objects but never consumed by Node-side parsing; partial credential values increase accidental leak risk.

**Fix:** removed `value` field from both map calls; only `fieldLabel` and `fullValue` remain.

---

## Finding 7 — `CHANGELOG.md:20`: wrong file attribution for `addLocatorHandler`

**Flagged:** changelog said `playwright/acg_credentials.js` but handler lives in `playwright/lib/sandbox.js`.

**Fix:** corrected attribution and added both toast text variants to the description.

---

## Finding 8 — `CHANGELOG.md:30`: misleading `_waitForCredentials` scoping claim

**Flagged:** changelog implied the function itself is "scoped to the active provider card" but polling is global; scoping is applied only in the `credentialsAlreadyVisible` early-exit check.

**Fix:** added `credentialsAlreadyVisible` qualifier to make the scope clear.

---

## Root Cause

- Selector/comment drift from earlier refactors; inner `detectLabel` was duplicated from outer scope and the outer copy was never cleaned up.
- Changelog authored quickly during live debug sessions without re-reading the implementation.

## Process Note

Add to spec template: "CHANGELOG entries must name the exact file where the behavior lives and must match what `git show` of the implementing commit shows."
