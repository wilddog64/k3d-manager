# Bug: ACG sandbox panel Open/Start/Resume clicks are no-ops (`force:true`)

## Symptom

`acg_get_credentials` / `acg_restart` (directly, or via the Slack `/cluster-refresh`
command → `bin/cluster-refresh` → `acg_credentials.js`) fail to open or provision the
Pluralsight cloud-sandbox panel when the sandbox is **not already Running**:

```
WARN: Scoped Start Sandbox not found for AWS — trying provider-scoped fallback...
WARN: No Start Sandbox button found for AWS after Open Sandbox — proceeding to credential wait
INFO: AWS panel closed — re-opening to retrieve credentials (attempt 1..3)...
ERROR: AWS panel stayed closed after 3 reopen attempts — aborting.
```

Extraction only ever succeeds when a human has already clicked **Open Sandbox → Start
Sandbox** and the sandbox is green — i.e. the automation is doing credential *reading*,
not panel *driving*.

## Root cause

Every "reveal / provision the sandbox panel" button in
`scripts/lib/acg/playwright/lib/sandbox.js` is clicked with Playwright's
`locator.click({ force: true })`. On the Pluralsight sandbox SPA these buttons **do not
respond to a synthetic Playwright click** — `force:true` only skips actionability checks;
it still issues the same click the SPA ignores. This is the exact failure recorded in the
k3d-manager reference note *"Playwright viewport click"*: the fix is
`el.scrollIntoView({block:'center'})` + a dispatched DOM `MouseEvent`, and `force:true`
does **not** work.

`acg_restart.js` already contains the working helper (`_robustClick`, lines 96–101) and
uses it for the Start-Sandbox and delete-dialog clicks — but its one panel-*reveal* click
(`openBtn.click({ force: true })`) regressed to the broken form, and `lib/sandbox.js` never
adopted the helper at all.

## Fix

1. Add a `_robustClick(locator)` helper to `lib/sandbox.js`, identical technique to
   `acg_restart.js`:
   ```js
   async function _robustClick(locator) {
     await locator.evaluate(el => {
       el.scrollIntoView({ block: 'center', inline: 'center' });
       el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
     }).catch(() => {});
   }
   ```
2. Route every **Open Sandbox / Start Sandbox / Resume / reopen** click in
   `lib/sandbox.js` through `_robustClick` (the reveal/provision class that fails).
   Leave the alertdialog **confirm-delete** clicks (`[role="alertdialog"]` buttons) on
   `force:true` — they operate inside an already-rendered dialog and are not the observed
   failure; converting them is out of scope for this bug.
   Sites: `startSandbox` — reopen-after-toast, startButton, retryStart, openButton,
   conflict Open, retryOpen, startButton2, resumeButton; `_waitForCredentials` — Azure
   startAfterDelete, panelStartBtn, reopenBtn; `_deleteConflictingSandbox` — conflict-cleanup
   Open Sandbox (reveals the conflicting panel's Delete button). Redundant
   `scrollIntoViewIfNeeded()` lines preceding a converted click are removed (the helper scrolls).
3. Fix `acg_restart.js` panel-reveal click: `openBtn.click({ force: true })` →
   `_robustClick(openBtn)`.

## Definition of Done

- [ ] `_robustClick` added to `lib/sandbox.js`.
- [ ] All Open/Start/Resume/reopen clicks in `lib/sandbox.js` use `_robustClick`.
- [ ] `acg_restart.js` panel-reveal click uses `_robustClick`.
- [ ] `npm run check` (node --check) passes for all playwright JS.
- [ ] `npm test` (jest provider tests) passes.
- [ ] Live gate (manual, in consumer): `acg_restart` opens the panel and starts a
      down sandbox without human clicks; `acg_get_credentials` then populates and
      `aws sts get-caller-identity` succeeds.

## What NOT to do

- Do NOT convert the alertdialog confirm-delete clicks (out of scope).
- Do NOT edit the `scripts/lib/foundation/` copy inside a consumer — this is the source
  repo; consumers pull via subtree.
- Do NOT skip pre-commit hooks.
