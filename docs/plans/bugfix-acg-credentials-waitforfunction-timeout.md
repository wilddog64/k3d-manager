# Bugfix: acg_credentials — waitForFunction timeout not applied

**Branch:** `fix/acg-credentials-waitforfunction-timeout`
**Files:** `playwright/acg_credentials.js`

---

## Problem

`acg_get_credentials` times out with "Timeout 30000ms exceeded" after clicking "Start Sandbox",
even though `_waitForCredentials` logs "Waiting for credentials to populate (up to 60s)...".
The intended 60-second wait never takes effect — the call always exits after the Playwright
default of 30000ms.

**Root cause:** `page.waitForFunction(fn, { timeout: 60000 })` passes `{ timeout: 60000 }`
as the `arg` slot (second positional parameter), not as the `options` slot. Playwright's
signature is `waitForFunction(fn, arg?, options?)` — it does not auto-promote a plain object
from the arg slot to options when only two arguments are given. The `options` slot remains
undefined, so Playwright uses its built-in default timeout of 30000ms.

---

## Reproduction

```bash
# From k3d-manager root with a sandbox in a slow-start state:
make up
# Expected: credentials extracted after sandbox start (up to 60s wait)
# Actual:   ERROR: page.waitForFunction: Timeout 30000ms exceeded.
#           (fires at 30s instead of the intended 60s)
```

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: pass `null` as arg so `{ timeout: 60000 }` reaches the options slot

**Exact old block (lines 367–376):**

```js
      const _waitForCredentials = async () => {
        console.error('INFO: Waiting for credentials to populate (up to 60s)...');
        await page.waitForFunction(
          () => {
            const inputs = document.querySelectorAll('input[aria-label="Copyable input"]');
            return inputs.length > 0 && inputs[0].value.trim().length > 0;
          },
          { timeout: 60000 }
        );
      };
```

**Exact new block:**

```js
      const _waitForCredentials = async () => {
        console.error('INFO: Waiting for credentials to populate (up to 60s)...');
        await page.waitForFunction(
          () => {
            const inputs = document.querySelectorAll('input[aria-label="Copyable input"]');
            return inputs.length > 0 && inputs[0].value.trim().length > 0;
          },
          null,
          { timeout: 60000 }
        );
      };
```

---

## Files Changed

This branch also carries `fix(cdp): correct foundation path — remove extra ../` (`369ef9f`),
which fixes `scripts/lib/cdp.sh` sourcing `../foundation/...` one level too high. That fix
predates this spec and is intentionally included in the same PR.

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Insert `null,` between the page function and `{ timeout: 60000 }` in `_waitForCredentials` |
| `scripts/lib/cdp.sh` | Remove extra `../` from `_CDP_FOUNDATION` path (pre-existing fix, commit `369ef9f`) |

---

## Rules (fix commit scope)

The rules below apply to the **fix commit** (`076f65d`) only — not to surrounding documentation,
CHANGELOG, or memory-bank updates which are expected companion commits on this branch.

- `node --check playwright/acg_credentials.js` — zero errors
- Fix commit touches only `playwright/acg_credentials.js`
- No `npm install` or dependency changes

---

## Definition of Done

- [x] `node --check playwright/acg_credentials.js` passes
- [x] Fix commit (`076f65d`) touches only `playwright/acg_credentials.js`
- [x] Committed and pushed to `fix/acg-credentials-waitforfunction-timeout`
- [x] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg): pass null arg to waitForFunction so 60s credential timeout is applied
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any `waitForFunction` call other than `_waitForCredentials`
- Do NOT commit to `main` — work on `fix/acg-credentials-waitforfunction-timeout`
