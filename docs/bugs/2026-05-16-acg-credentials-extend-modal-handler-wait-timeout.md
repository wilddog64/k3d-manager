# Bug: acg_credentials — addLocatorHandler post-handler wait loops on CSS slide-out animation

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

After the `page.addLocatorHandler()` fix (commit `4cbe3b7e`), the script times out with:

```
ERROR: locator.click: Timeout 30000ms exceeded.
Call log:
  - found locator('[role="dialog"]:has-text("Extend Your Session")'), intercepting action to run the handler
  - locator handler has finished, waiting for locator('[role="dialog"]:has-text("Extend Your Session")') to be hidden
  6 × locator resolved to visible <div role="dialog" data-open="false" data-transitioning="true" ...>
  - interception handler has finished, continuing
```

The handler IS working — Cancel is clicked and `data-open` is set to `false`. But the
"Extend Your Session" dialog is a CSS slide-over panel: after Cancel, the panel animates
off-screen via `transform: translateX(100%)` with `data-transitioning="true"`. During this
animation, Playwright considers the element still "visible" (CSS transform does not set
`display: none` or `visibility: hidden`), so `waitFor({ state: 'hidden' })` loops.

Playwright's `addLocatorHandler` default behavior waits for the registered locator to
become invisible after the handler returns. The locator `[role="dialog"]:has-text("Extend
Your Session")` keeps matching the animating-out element (6 polls), the post-handler wait
never exits cleanly, and this burns time from the 30s `startButton.click()` timeout. The
cycle repeats until the timeout expires.

**Root cause:** The locator used in `addLocatorHandler` does not include the `data-open`
attribute, so it matches the panel in all states — open, closing, and CSS-transitioning.
Adding `[data-open="true"]` makes the locator only match the truly-open state. When Cancel
changes `data-open` to `false`, the locator immediately stops matching → Playwright's
post-handler wait exits instantly without waiting for the CSS animation.

---

## Reproduction

1. Have a GCP sandbox session near expiry
2. Run `make up CLUSTER_PROVIDER=k3s-gcp`
3. "Extend Your Session" modal appears
4. Handler fires, clicks Cancel — but post-handler wait loops 6× on the animating panel
5. `startButton.click()` times out after 30s

---

## Fix

### Change 1 — `addLocatorHandler` locator: add `[data-open="true"]`

One attribute selector added to the registered locator. No other lines change.

**Exact old block:**

```javascript
    // Auto-dismiss "Extend Your Session" at any point — fires during waitForFunction, clicks, etc.
    await page.addLocatorHandler(
      page.locator('[role="dialog"]:has-text("Extend Your Session")'),
```

**Exact new block:**

```javascript
    // Auto-dismiss "Extend Your Session" at any point — fires during waitForFunction, clicks, etc.
    await page.addLocatorHandler(
      page.locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")'),
```

Only this one line changes. Do NOT modify any other lines in the file.

**Why this works:** When Cancel sets `data-open="false"`, the locator
`[data-open="true"]:has-text("Extend Your Session")` no longer matches the closing panel.
Playwright's post-handler "wait for locator to be hidden" check exits immediately because
the locator no longer resolves — no waiting for the CSS animation to finish.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Add `[data-open="true"]` to `addLocatorHandler` locator |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched

---

## Definition of Done

- [ ] `scripts/lib/acg/playwright/acg_credentials.js` `addLocatorHandler` call uses `'[role="dialog"][data-open="true"]:has-text("Extend Your Session")'`
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Commit message: `fix(acg-credentials): scope addLocatorHandler to data-open=true to avoid animation wait loop`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT add `{ noWaitAfter: true }` to `addLocatorHandler` — fixing the locator is sufficient
- Do NOT change the pre-flight check (lines ~364–377) or `_waitForCredentials` check — those use `.catch(() => {})` and are unaffected by the animation issue
