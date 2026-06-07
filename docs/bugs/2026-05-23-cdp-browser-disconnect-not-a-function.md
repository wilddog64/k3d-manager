# Bug: acg_credentials + acg_restart — `_cdpBrowser.disconnect is not a function`

**Branch (lib-acg):** `fix/next-improvements-5`
**Files:** `playwright/acg_credentials.js`, `playwright/acg_restart.js`

---

## Problem

`_cdpBrowser.disconnect()` is called in both `acg_credentials.js` (3 occurrences) and
`acg_restart.js` (3 occurrences), but Playwright's `Browser` object has no `.disconnect()`
method. The correct API for ending a CDP session without closing Chrome is `.close()`.

Currently caught by `try {} catch {}` so the error is silently swallowed — cleanup
does not actually run, leaving the CDP session dangling.

`acg_extend.js` was already fixed (uses `.close()`). These two files were missed.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: replace all 3 `.disconnect()` calls with `.close()`

**Exact old block (line 201):**

```javascript
          try { await _cdpBrowser.disconnect(); } catch {}
          _cdpBrowser = await chromium.connectOverCDP(CDP_URL);
```

**Exact new block:**

```javascript
          try { await _cdpBrowser.close(); } catch {}
          _cdpBrowser = await chromium.connectOverCDP(CDP_URL);
```

---

**Exact old block (line 210):**

```javascript
          try { await _cdpBrowser.disconnect(); } catch {}
          _cdpBrowser = null;
```

**Exact new block:**

```javascript
          try { await _cdpBrowser.close(); } catch {}
          _cdpBrowser = null;
```

---

**Exact old block (lines 567–569):**

```javascript
      // CDP attach: detach only — leave the user's Chrome running with tabs intact.
      try { await _cdpBrowser.disconnect(); } catch {}
      console.error('INFO: Detached from Chrome CDP session.');
```

**Exact new block:**

```javascript
      // close() on a connectOverCDP browser detaches Playwright without closing Chrome.
      try { await _cdpBrowser.close(); } catch {}
      console.error('INFO: Detached from Chrome CDP session.');
```

---

### Change 2 — `playwright/acg_restart.js`: replace all 3 `.disconnect()` calls with `.close()`

**Exact old block (line 160):**

```javascript
        try { await _cdpBrowser.disconnect(); } catch {}
        _cdpBrowser = await chromium.connectOverCDP(CDP_URL);
```

**Exact new block:**

```javascript
        try { await _cdpBrowser.close(); } catch {}
        _cdpBrowser = await chromium.connectOverCDP(CDP_URL);
```

---

**Exact old block (line 168):**

```javascript
        try { await _cdpBrowser.disconnect(); } catch {}
        _cdpBrowser = null;
```

**Exact new block:**

```javascript
        try { await _cdpBrowser.close(); } catch {}
        _cdpBrowser = null;
```

---

**Exact old block (line 418):**

```javascript
      try { await _cdpBrowser.disconnect(); } catch {}
```

**Exact new block:**

```javascript
      try { await _cdpBrowser.close(); } catch {}
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Replace `.disconnect()` with `.close()` at lines 201, 210, 568; update comment at line 567 |
| `playwright/acg_restart.js` | Replace `.disconnect()` with `.close()` at lines 160, 168, 418 |

---

## Rules

- `node --check playwright/acg_credentials.js` must pass
- `node --check playwright/acg_restart.js` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] `acg_credentials.js` lines 201, 210, 568: `.disconnect()` replaced with `.close()`
- [ ] `acg_credentials.js` line 567: comment updated
- [ ] `acg_restart.js` lines 160, 168, 418: `.disconnect()` replaced with `.close()`
- [ ] No other functions or files modified
- [ ] `node --check` passes on both files
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-credentials,acg-restart): replace .disconnect() with .close() — CDP Browser has no disconnect method
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js` and `playwright/acg_restart.js`
- Do NOT commit to `main`
- Do NOT change any other function in either file
