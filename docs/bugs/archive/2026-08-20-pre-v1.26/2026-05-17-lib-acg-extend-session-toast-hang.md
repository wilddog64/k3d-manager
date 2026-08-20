# Bug: lib-acg — `acg_extend.js` hangs when "Session extended" toast already visible at startup

**Branch (lib-acg work):** `feat/acg-multi-provider`
**Files (lib-acg):**
- `playwright/acg_extend.js` — add early-exit when "Your sandbox has been extended." toast is already visible

---

## Before You Start

```
git -C ~/src/gitrepo/personal/lib-acg fetch origin
git -C ~/src/gitrepo/personal/lib-acg checkout feat/acg-multi-provider
git -C ~/src/gitrepo/personal/lib-acg pull origin feat/acg-multi-provider
```

Read this spec in full before touching any file.

---

## Problem

`acg_extend.js` hangs indefinitely when the "Your sandbox has been extended." confirmation
toast is already visible when the script starts (left over from an earlier extend in the
same browser session — e.g. from `acg_credentials.js`'s Extend Your Session dialog path).

**Root cause:** `addLocatorHandler` on line 139 registers a handler for
`text="Your sandbox has been extended."`. When the toast is already visible:
1. Playwright fires the handler before each locator action.
2. The handler calls `page.mouse.click()` to dismiss the toast.
3. `page.mouse.click()` silently fails — CDP-attached sessions require Chrome to be the
   active OS app; the visor-mode iTerm2 setup means Chrome is never in OS foreground.
4. The toast remains visible, Playwright fires the handler again on the next locator
   action, creating an infinite loop that holds the event loop indefinitely.
5. The 90s `Promise.race` timeout does not fire because the event loop never yields.

**Key insight:** "Your sandbox has been extended." is the SUCCESS confirmation. If it is
visible when the script starts, the extension already happened. The correct response is to
log and exit 0 — not to attempt a dismissal loop.

---

## Fix

### Change 1 — `playwright/acg_extend.js`: early-exit when success toast already visible

**Location:** After line 137 (`isOnSandboxPage` block ends) and before line 139
(`addLocatorHandler`). Insert the early-exit block between them.

**Exact old block (lines 138–139):**

```javascript
    // Try to connect via CDP first to catch already-open modals
    await page.addLocatorHandler(
```

Wait — the insertion point is BETWEEN the `isOnSandboxPage` block and the `addLocatorHandler`
call. Specifically, insert after the closing brace of the `isOnSandboxPage` if/else block
(line ~137) and before `await page.addLocatorHandler(` (line 139).

**Exact old text to replace (lines 137–139, the transition from nav to handler):**

```javascript
    }

    await page.addLocatorHandler(
```

**Exact new text:**

```javascript
    }

    // If the "Session extended" toast is already visible, extension already succeeded — exit immediately.
    if (await page.locator('text="Your sandbox has been extended."').first().isVisible({ timeout: 2000 }).catch(() => false)) {
      console.error('INFO: "Session extended" toast already visible — extension already succeeded. Exiting.');
      process.exit(0);
    }

    await page.addLocatorHandler(
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_extend.js` | Add early-exit after nav block: if success toast visible → exit 0 |

---

## Rules

- `node --check playwright/acg_extend.js` — zero errors
- No other files modified

---

## Definition of Done

- [ ] Early-exit block inserted between the `isOnSandboxPage` nav block and `addLocatorHandler`
- [ ] Early-exit uses `page.locator('text="Your sandbox has been extended."').first().isVisible({ timeout: 2000 }).catch(() => false)`
- [ ] On match: logs `INFO: "Session extended" toast already visible — extension already succeeded. Exiting.` and calls `process.exit(0)`
- [ ] `addLocatorHandler` call is unchanged and still present immediately after the new block
- [ ] `node --check playwright/acg_extend.js` passes
- [ ] No other files modified
- [ ] Committed to `feat/acg-multi-provider` in lib-acg
- [ ] `git push origin feat/acg-multi-provider` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat` output

**Commit message (exact):**
```
fix(acg): exit 0 when Session extended toast visible at startup in acg_extend.js
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_extend.js`
- Do NOT commit to `main` — work on `feat/acg-multi-provider`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT remove or modify the `addLocatorHandler` block
- Do NOT touch `acg_credentials.js`
