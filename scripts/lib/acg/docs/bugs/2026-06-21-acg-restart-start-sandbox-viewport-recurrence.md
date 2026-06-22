# Bugfix: v0.1.9 — acg_restart Start Sandbox click "outside of viewport" recurrence

**Branch:** `feat/v0.1.9`
**Files:** `playwright/acg_restart.js`, `CHANGELOG.md`

---

## Problem

`acg_restart.js` fails with `locator.click: Element is outside of the viewport` when clicking
the provider-scoped **Start Sandbox** button. Observed 2026-06-21 via `make credential-test`
(k3d-manager, default `URL=.../cloud-playground/cloud-sandboxes`) with no AWS sandbox running:

```
INFO: Clicking Start Sandbox...
ERROR: locator.click: Element is outside of the viewport
  - waiting for locator('button:has-text("Start Sandbox")').first()
    - locator resolved to <button data-heap-id="Hands-on Playground - Click - AWS Sandbox - Start Sandbox" …>
    - attempting click action
      - scrolling into view if needed
      - done scrolling
```

**Root cause:** this is a **recurrence**. The v0.1.3 fix
([2026-06-05-acg-restart-start-sandbox-outside-viewport.md](2026-06-05-acg-restart-start-sandbox-outside-viewport.md))
added `scrollIntoViewIfNeeded()` before the Start Sandbox clicks, but that is insufficient:
Playwright's `scrollIntoViewIfNeeded()` can report "done scrolling" while the computed click
point is still outside the viewport, and `{ force: true }` bypasses *actionability* checks but
**not** the viewport requirement — so the click still throws. The **Delete** button in the same
file already avoids this by dispatching a DOM `MouseEvent` via `page.evaluate` (the confirm-delete
path), which is viewport-independent; the three Start Sandbox sites never adopted that pattern.

---

## Reproduction

```bash
make credential-test   # default URL = cloud-playground landing page, no AWS sandbox running
# Expected: Start Sandbox clicked; credentials extracted
# Actual:   ERROR: locator.click: Element is outside of the viewport  → restart fails, exit 1
```

---

## Fix

Add a viewport-independent click helper and use it for all three Start Sandbox click sites.
The helper centers the element and dispatches a bubbling DOM `MouseEvent` in-page — the same
technique already proven for the Delete-confirmation click in this file.

### Change 1 — `playwright/acg_restart.js`: add `_robustClick` helper

Insert before `_findScopedButton`:

```js
async function _robustClick(locator) {
  await locator.evaluate(el => {
    el.scrollIntoView({ block: 'center', inline: 'center' });
    el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
  });
}
```

### Change 2 — fast-path Start Sandbox (`_startBtnEarly`)

Replace:
```js
      await _startBtnEarly.scrollIntoViewIfNeeded().catch(() => {});
      await _startBtnEarly.click({ force: true });
```
with:
```js
      await _robustClick(_startBtnEarly);
```

### Change 3 — panel-open Start Sandbox (`_startBtnPanelScoped`)

Replace:
```js
        await _startBtnPanelScoped.scrollIntoViewIfNeeded().catch(() => {});
        await _startBtnPanelScoped.click({ force: true });
```
with:
```js
        await _robustClick(_startBtnPanelScoped);
```

### Change 4 — post-delete Start Sandbox (`startBtn`)

Replace:
```js
    await startBtn.click({ force: true });
```
with:
```js
    await _robustClick(startBtn);
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_restart.js` | add `_robustClick`; use it for all three Start Sandbox clicks |
| `CHANGELOG.md` | `[Unreleased]` → `### Fixed` entry |

---

## Rules

- `node --check playwright/acg_restart.js` — zero errors
- Code change limited to `playwright/acg_restart.js` (+ CHANGELOG, this doc)

---

## Definition of Done

- [ ] `node --check playwright/acg_restart.js` passes
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] Committed and pushed to `feat/v0.1.9`
- [ ] k3d-manager `scripts/lib/acg` subtree re-synced

**Commit message (exact):**
```
fix(acg_restart): viewport-independent Start Sandbox click via DOM dispatch
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any code file other than `playwright/acg_restart.js`
- Do NOT commit to `main` — work on `feat/v0.1.9`
