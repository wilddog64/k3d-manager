# Bugfix: acg_extend.js — CDP browser disconnect hang

**Branch:** `docs/next-improvements`
**Files:** `playwright/acg_extend.js`

---

## Problem

`make up` hangs indefinitely at the pre-flight sandbox TTL extension step when Chrome is already running with CDP on port 9222.

**Root cause:** `acg_extend.js` connects to Chrome via `chromium.connectOverCDP()` when Chrome is open. After the extension succeeds, the `finally` block skips `browserContext.close()` (correct — closing would kill Chrome), but never calls `_cdpBrowser.disconnect()`. The open CDP WebSocket keeps the Node event loop alive. The process never exits, so the calling script (`make up`) hangs until Ctrl-C.

The 90-second `OVERALL_TIMEOUT_MS` race resolves (not rejects) when `extendSandbox()` returns successfully, so the timeout branch never fires. The setTimeout callback continues running in the background, and the open CDP WebSocket keeps the event loop alive — Node does not exit until both are released.

---

## Reproduction

1. Run `make up` (or `bin/acg-up`) when Chrome is already open from a previous credential extraction session (Chrome running with `--remote-debugging-port=9222`).
2. Observe: the process prints `INFO: [acg] Extending ACG sandbox TTL at ...` and then hangs. The browser shows "Session extended" (extension succeeded), but the node process never exits.

---

## Fix

### Change 1 — `playwright/acg_extend.js`: disconnect CDP browser on exit

**Exact old block (lines 329–335):**
```javascript
  } finally {
    // Only close if we launched a persistent context (not if we attached via CDP — closing a CDP
    // browser shuts down the entire Chrome process, disrupting other sessions)
    if (!_cdpBrowser && browserContext) {
      await browserContext.close().catch(() => {});
    }
  }
```

**Exact new block:**
```javascript
  } finally {
    if (_cdpBrowser) {
      // Disconnect from CDP without closing Chrome — closing would kill the entire process
      await _cdpBrowser.disconnect().catch(() => {});
    } else if (browserContext) {
      await browserContext.close().catch(() => {});
    }
  }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_extend.js` | Replace `finally` block to call `disconnect()` when using CDP |

---

## Rules

- `node --check playwright/acg_extend.js` — must pass (syntax check)
- Code change limited to `playwright/acg_extend.js`; CHANGELOG and memory-bank updates are required documentation

---

## Definition of Done

- [ ] `playwright/acg_extend.js` `finally` block calls `_cdpBrowser.disconnect()` when `_cdpBrowser` is set
- [ ] `node --check playwright/acg_extend.js` passes
- [ ] Committed and pushed to `docs/next-improvements`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-extend): disconnect CDP browser on exit to prevent node process hang
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify code files other than `playwright/acg_extend.js`
- Do NOT commit to `main` — work on `docs/next-improvements`
- Do NOT add a `_cdpBrowser.close()` call — that kills Chrome; only `disconnect()` is safe here
