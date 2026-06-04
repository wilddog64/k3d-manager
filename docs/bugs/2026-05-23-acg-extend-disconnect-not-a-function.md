# Bug: acg_extend — `_cdpBrowser.disconnect is not a function`

**Branch (lib-acg):** `fix/next-improvements-5`
**File:** `playwright/acg_extend.js`

---

## Problem

`bin/acg-extend-test` exits with:

```
ERROR: _cdpBrowser.disconnect is not a function
make: *** [extend-test] Error 1
```

**Root cause:** `chromium.connectOverCDP()` returns a Playwright `Browser` object. `Browser` has no `.disconnect()` method — the correct method to end a CDP session without closing Chrome is `.close()`. When Playwright is connected via `connectOverCDP`, calling `browser.close()` disconnects Playwright's session without terminating the underlying Chrome process.

---

## Fix

### Change — `playwright/acg_extend.js`: replace `.disconnect()` with `.close()`

**Exact old block (lines 363–365):**

```javascript
    if (_cdpBrowser) {
      // Disconnect from CDP without closing Chrome; closing would kill the entire process
      await _cdpBrowser.disconnect().catch(() => {});
```

**Exact new block:**

```javascript
    if (_cdpBrowser) {
      // close() on a connectOverCDP browser disconnects Playwright without closing Chrome
      await _cdpBrowser.close().catch(() => {});
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_extend.js` | Replace `.disconnect()` with `.close()` on line 365; update comment on line 364 |

---

## Rules

- `node --check playwright/acg_extend.js` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] Line 365: `_cdpBrowser.disconnect()` replaced with `_cdpBrowser.close()`
- [ ] Line 364 comment updated to reflect correct behavior
- [ ] No other functions or files modified
- [ ] `node --check playwright/acg_extend.js` passes
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-extend): replace .disconnect() with .close() — CDP Browser has no disconnect method
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_extend.js`
- Do NOT commit to `main`
- Do NOT change any other function in the file
