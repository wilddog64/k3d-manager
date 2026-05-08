# Bugfix Correction: CDP empty-contexts — missing guard on disconnect

**Date:** 2026-05-02
**Branch:** `fix/acg-credentials-cdp-empty-contexts`
**File:** `playwright/acg_credentials.js`

---

## Before You Start

1. `git pull origin fix/acg-credentials-cdp-empty-contexts` in the lib-acg repo
2. Read `playwright/acg_credentials.js` lines 186–212 — understand the existing blank-tab block before touching anything

---

## Problem

Commit `b5327fb` added the blank-tab logic but dropped the `if (!browserContext)` guard
before the disconnect lines. As a result, `_cdpBrowser` is disconnected even when the
blank-tab succeeded and `browserContext` was set. Playwright then throws trying to use a
context from a disconnected browser — the fix does not work.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: add missing guard before disconnect

**Exact old block (lines 205–208):**

```javascript
        } catch { /* fall through if blank tab fails */ }
        try { await _cdpBrowser.disconnect(); } catch {}
        _cdpBrowser = null;
      }
```

**Exact new block:**

```javascript
        } catch { /* fall through if blank tab fails */ }
        if (!browserContext) {
          try { await _cdpBrowser.disconnect(); } catch {}
          _cdpBrowser = null;
        }
      }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Add `if (!browserContext)` guard before disconnect (3-line change) |

---

## Rules

- `node --check playwright/acg_credentials.js` — zero errors
- Code change: `playwright/acg_credentials.js` only; memory-bank updates are also required (see DoD)

---

## Definition of Done

- [ ] `if (!browserContext)` guard wraps the disconnect lines
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] Committed and pushed to `fix/acg-credentials-cdp-empty-contexts`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(acg): guard CDP disconnect behind missing browserContext check
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any code file other than `playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `fix/acg-credentials-cdp-empty-contexts`
- Do NOT change any other part of the file — this is a 3-line insertion only
