# Bug: acg_credentials — startButton.click times out due to React re-render after modal close

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

After the `[data-open="true"]` selector fix (commit `1026389c`), the post-handler wait exits
cleanly. But `startButton.click()` still times out with:

```
- locator handler has finished, waiting for locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")') to be hidden
- interception handler has finished, continuing
- locator resolved to <button data-heap-id="Hands-on Playground - Click - AWS Sandbox - Start Sandbox" ...>
- attempting click action
  2 × waiting for element to be visible, enabled and stable
    - element is not stable
  - retrying click action, waiting 20ms
  - element is not stable
  - retrying click action, waiting 100ms
  - element is visible, enabled and stable
  - scrolling into view if needed
  - done scrolling
  - element is outside of the viewport
  - retrying click action, waiting 100ms
  - element was detached from the DOM, retrying
```

The handler fires, clicks Cancel, and returns immediately. The CSS slide-out animation
(~400ms, `transform: translateX(100%)`) is still in progress. When Playwright resumes
`startButton.click()`, the page layout is mid-animation:

1. Button is "not stable" (layout shifting during modal animation)
2. After brief stability, it goes outside the viewport (page re-renders/scrolls as modal closes)
3. Element detaches entirely (React unmounts/remounts the modal component)
4. Playwright retries but the cycle repeats until the 30s timeout expires

**Root cause:** The handler returns before the modal close animation (~400ms) completes.
Playwright resumes the intercepted `startButton.click()` while the page is still doing
a React re-render triggered by the modal closing.

---

## Reproduction

1. Have a GCP sandbox session near expiry
2. Run `make up CLUSTER_PROVIDER=k3s-gcp`
3. "Extend Your Session" modal appears while Playwright waits for `startButton`
4. Handler fires, clicks Cancel — post-handler wait exits cleanly
5. `startButton.click()` sees not-stable → outside-viewport → detached cycle
6. Times out after 30s

---

## Fix

### Change 1 — Add `page.waitForTimeout(1000)` at the end of the handler callback

One line added inside the handler `async () => { ... }` body, after the if/else block.
No other lines change.

**Exact old block:**

```javascript
        if (await _handlerCancelBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await _handlerCancelBtn.click({ force: true }).catch(() => {});
        } else {
          await page.keyboard.press('Escape').catch(() => {});
        }
      }
    );
```

**Exact new block:**

```javascript
        if (await _handlerCancelBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await _handlerCancelBtn.click({ force: true }).catch(() => {});
        } else {
          await page.keyboard.press('Escape').catch(() => {});
        }
        await page.waitForTimeout(1000).catch(() => {});
      }
    );
```

Only this one line changes (adding `await page.waitForTimeout(1000).catch(() => {});`
between the closing `}` of the if/else and the closing `}` of the async handler).
Do NOT modify any other lines in the file.

**Why this works:** The 1000ms wait inside the handler lets the ~400ms CSS slide-out
animation complete and the React component unmount/remount finish before the handler
returns. When Playwright resumes `startButton.click()`, the page is fully settled —
no more layout shifts, viewport jumps, or DOM detachments.

The 1000ms is consumed from `startButton.click()`'s 30000ms timeout. With a single
handler invocation, 29s remains — ample for the button click.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Add `await page.waitForTimeout(1000).catch(() => {})` at end of handler callback |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched

---

## Definition of Done

- [ ] `scripts/lib/acg/playwright/acg_credentials.js` handler callback ends with `await page.waitForTimeout(1000).catch(() => {});` before the closing `}`
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Commit message: `fix(acg-credentials): wait 1s in handler for modal animation to settle before resuming click`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT remove the `[data-open="true"]` selector from the `addLocatorHandler` locator — it is still needed to avoid the post-handler animation wait loop
- Do NOT change the pre-flight check (lines ~378–389) or `_waitForCredentials` check — those are belt-and-suspenders and harmless
- Do NOT add `{ noWaitAfter: true }` to `addLocatorHandler` — fixing the handler is sufficient
