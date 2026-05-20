# Bugfix: acg_extend.js midnight-wrap masks expired sandbox TTL

**Branch:** `fix/acg-extend-midnight-wrap`
**Files:** `playwright/acg_extend.js`

---

## Problem

`acg_check_ttl` returns a large positive number (~22 hours) when the sandbox has already
expired hours ago today. The caller cannot tell the sandbox is expired.

**Root cause:** The midnight-wrap guard unconditionally adds 24 hours whenever
`shutdownTime < now`:

```javascript
if (shutdownTime < now) {
  shutdownTime.setDate(shutdownTime.getDate() + 1);
}
```

A sandbox that shut down at 2:02PM and is checked at 4:02PM is 120 minutes past expiry.
The guard fires, wraps to tomorrow 2:02PM, and reports ~1320 minutes remaining.

The guard exists for a legitimate edge case: a sandbox set to shut down at 12:30AM when
the current time is 11:59PM — the display time appears to be "in the past" by one minute
but is actually tomorrow. That scenario involves a gap of ≤ 60 minutes.

---

## Reproduction

```
sandbox Auto Shutdown: 2:02PM
current time: 4:02PM (2 hours later)
node acg_extend.js <url> --check
# expected: REMAINING_MINS:-1  (or 0)
# actual:   REMAINING_MINS:1320
```

---

## Fix

### Change 1 — `playwright/acg_extend.js`: narrow midnight-wrap to ≤ 60 min

**Exact old block (lines 203–206):**

```javascript
          // Midnight/Date-wrap fix: Handle case where shutdown is tomorrow morning
          if (shutdownTime < now) {
             shutdownTime.setDate(shutdownTime.getDate() + 1);
          }
```

**Exact new block:**

```javascript
          // Midnight/Date-wrap fix: only wrap when the time just ticked past midnight
          // (gap ≤ 60 min). Larger gaps mean the sandbox truly expired today.
          if (shutdownTime < now && (now.getTime() - shutdownTime.getTime()) < 60 * 60 * 1000) {
            shutdownTime.setDate(shutdownTime.getDate() + 1);
          }
```

After this change `remainingMins` will be negative (e.g. -120) when the sandbox expired
hours ago. The existing `--check` path already emits `REMAINING_MINS:-1` for `null`, but
a negative `remainingMins` will now be emitted as `REMAINING_MINS:-120`, which callers
can treat as expired (any value ≤ 0 means expired).

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_extend.js` | Narrow midnight-wrap guard from unconditional to ≤ 60 min |

---

## Rules

- `node --check playwright/acg_extend.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] `node --check playwright/acg_extend.js` passes
- [ ] Committed to `fix/acg-extend-midnight-wrap` and pushed to `origin/fix/acg-extend-midnight-wrap`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(acg-extend): narrow midnight-wrap guard to 60 min so expired sandboxes report negative TTL
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_extend.js`
- Do NOT commit to `main` — work on `fix/acg-extend-midnight-wrap`
