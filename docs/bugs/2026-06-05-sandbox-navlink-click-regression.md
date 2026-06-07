# Bugfix: v0.1.1 — sandbox navigateToSandbox navLink.click() regression

**Branch:** `feat/v0.1.1`
**Files:** `playwright/lib/sandbox.js`

---

## Problem

`acg-up` fails immediately with `CLUSTER_FAILURE PERMANENT — failed to extract AWS credentials`.
The browser navigates to `s2.pluralsight.com/404.html` instead of the cloud-sandboxes page.

**Root cause:** The `cloud-sandboxes` SPA navigation path in `navigateToSandbox()` (lines 44–53)
uses `navLink.click()` when the nav link is visible. The link's href resolves to `s2.pluralsight.com`
(Pluralsight's skills domain), causing a 404. The original `acg_credentials.js` (pre-refactor,
SHA `1e32e157`) explicitly removed this path with the comment:
"navLink.click() times out if the dialog reappears between dismiss and click" — Codex re-introduced
it during the provider pattern refactor (PR #35).

---

## Reproduction

```bash
bin/acg-up --no-login-prompt
# Expected: extracts AWS credentials and provisions cluster
# Actual: browser opens s2.pluralsight.com/404.html; script exits with
#   CLUSTER_FAILURE PERMANENT — failed to extract AWS credentials
```

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: remove navLink.click() path, always use window.location.assign()

**Exact old block (lines 44–53):**

```js
  } else if (targetPathname.includes('cloud-sandboxes')) {
    console.error(`INFO: SPA-navigating to cloud-sandboxes from ${currentUrl}...`);
    const navLink = page.locator('a[href*="cloud-sandboxes"]').first();
    const navVisible = await navLink.isVisible({ timeout: 5000 }).catch(() => false);
    if (navVisible) {
      await navLink.click();
    } else {
      await page.evaluate(url => window.location.assign(url), targetUrl);
      await page.waitForLoadState('domcontentloaded', { timeout: 60000 }).catch(() => {});
    }
```

**Exact new block:**

```js
  } else if (targetPathname.includes('cloud-sandboxes')) {
    console.error(`INFO: SPA-navigating to cloud-sandboxes from ${currentUrl}...`);
    // navLink.click() follows href to s2.pluralsight.com (404); also times out if
    // the Extend Your Session dialog reappears between dismiss and click.
    await page.evaluate(url => window.location.assign(url), targetUrl);
    await page.waitForLoadState('domcontentloaded', { timeout: 60000 }).catch(() => {});
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Remove `navLink.click()` conditional; always use `window.location.assign()` |

---

## Rules

- `node --check playwright/lib/sandbox.js` — must pass with zero errors
- Code change limited to `playwright/lib/sandbox.js`; this bug spec doc and memory-bank updates are also expected

---

## Definition of Done

- [ ] `playwright/lib/sandbox.js` lines 44–53 match the exact new block above
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] Committed and pushed to `feat/v0.1.1`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(sandbox): remove navLink.click() path — always use window.location.assign()
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js`
- Do NOT commit to `main` — work on `feat/v0.1.1`
