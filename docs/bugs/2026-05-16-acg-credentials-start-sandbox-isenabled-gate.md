# Bug: acg-credentials — isEnabled() gate skips Start Sandbox click when button appears active

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

In `extractCredentials()` Pattern 1 (lines 499–507), when "Start Sandbox" is visible the
code calls `startButton.isEnabled()` before deciding whether to click. If `isEnabled()`
returns `false` (React state not fully settled, or button in a transient disabled state
even though it visually appears active), the click is skipped. The code then calls
`_waitForCredentials()` on an unstarted sandbox — credentials never populate, the 420s
wait exhausts, and `acg_get_credentials` returns 1.

**Root cause:** `isEnabled()` is used to distinguish "sandbox already running (button
disabled)" from "sandbox needs starting (button enabled)". But a freshly-rendered button
can transiently return `isEnabled() = false` before React finishes hydration. The check
creates a false-negative that silently skips the click.

**Safe fix:** Remove the `isEnabled()` gate. If the button is visible, always try to click
it. Clicking a running sandbox's Start button is a no-op. `_waitForCredentials()` handles
both cases (started and already-running).

---

## Reproduction

1. Navigate to ACG sandbox page with unstarted sandbox
2. "Start Sandbox" button is visible and appears active (purple)
3. `isEnabled()` returns `false` during React hydration window (1s timeout)
4. Code logs "Start Sandbox button is disabled — sandbox already running; waiting for credentials..."
5. `_waitForCredentials()` times out after 420s — sandbox was never started
6. `acg_get_credentials` returns 1

---

## Fix

### Change 1 — `acg_credentials.js` lines 499–507: remove isEnabled() gate

**Exact old block:**
```javascript
      if (await startButton.isVisible({ timeout: 5000 }).catch(() => false)) {
        const _startEnabled = await startButton.isEnabled({ timeout: 1000 }).catch(() => false);
        if (_startEnabled) {
          console.error('INFO: Clicking Start Sandbox...');
          await _clickStartSandbox(page, startButton);
        } else {
          console.error('INFO: Start Sandbox button is disabled — sandbox already running; waiting for credentials...');
        }
        await _waitForCredentials();
```

**Exact new block:**
```javascript
      if (await startButton.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Clicking Start Sandbox...');
        await _clickStartSandbox(page, startButton);
        await _waitForCredentials();
```

**Why:** Removing the gate means we always click when the button is visible. If the sandbox
is already running, the click is a no-op (the button is inert or the page ignores it) and
`_waitForCredentials()` succeeds because credentials are already present. If the sandbox
needs starting, the click starts it and `_waitForCredentials()` waits for population.
`{ force: true }` in `_clickStartSandbox` ensures the click lands regardless of overlay.

---

## Files Changed

| File | Changes |
|------|---------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Change 1 — remove 3-line `isEnabled()` check, always click when visible |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass
- No other files touched
- The change is exactly the Pattern 1 `if (await startButton.isVisible...)` block — nothing else changes
- Pattern 2 (`openButton`) and Pattern 3 (`resumeButton`) are unchanged

---

## Definition of Done

- [ ] Lines 499–507 changed: 9-line block → 4-line block (remove `isEnabled()` check entirely)
- [ ] `_waitForCredentials()` call position unchanged (immediately after `_clickStartSandbox`)
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg-credentials): remove isEnabled() gate — always click Start Sandbox when visible
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change Pattern 2 (`openButton` block, lines 508–543) — it does not have this bug
- Do NOT change Pattern 3 (`resumeButton` block) — it does not have this bug
- Do NOT change `_clickStartSandbox` function — it stays as-is
- Do NOT change `_waitForCredentials` function — it stays as-is
