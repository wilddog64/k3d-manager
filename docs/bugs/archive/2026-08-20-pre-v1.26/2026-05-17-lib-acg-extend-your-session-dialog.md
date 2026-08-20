# Bug: lib-acg — "Extend Your Session" dialog hangs acg_credentials.js + missing test harness

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog` (create from `origin/main`)
**Files (lib-acg):**
- `playwright/acg_credentials.js` — add dialog handling
- `bin/acg-credential-test` — new file
- `bin/acg-extend-test` — new file

---

## Before You Start

```
git -C ~/src/gitrepo/personal/lib-acg fetch origin
git -C ~/src/gitrepo/personal/lib-acg checkout -b fix/acg-credentials-extend-dialog origin/main
```

Read this spec in full before touching any file.

---

## Problem

When an ACG sandbox is near expiry, Pluralsight shows a modal dialog:

> "Your sandbox is about to expire. Would you like to extend your session?
> (This can only be done once per session)"

`acg_credentials.js` has no handling for this dialog. When it appears:

1. `_waitForSandboxEntry`'s `waitForFunction` sees no Start/Open/Resume buttons (only
   Cancel and Extend Session are in the DOM from the dialog) → polls for 30 s then times out.
2. Subsequent `startButton.click()` or `openButton.click()` may land on the dialog instead
   of the sandbox controls.
3. The script hangs for minutes or fails with no useful error.

There is also no standalone test harness in `lib-acg/bin/` — every ACG fix has required
running all of k3d-manager (`make up`) to verify, causing regressions to go undetected.

**Root cause:** `acg_credentials.js` never had "Extend Your Session" dialog detection or
dismissal logic. The `waitForFunction` check does not account for the dialog's presence.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: extend `waitForFunction` to detect the dialog

The `waitForFunction` in `_waitForSandboxEntry` looks for Start/Open/Resume buttons or
populated credentials. When only the "Extend Your Session" dialog is visible, it finds
nothing and times out. Add a dialog-presence check so it exits early instead.

**Exact old block (lines 349–361):**

```javascript
      const _waitForSandboxEntry = async (timeout = 30000) => {
        // Skeleton clears before cards appear, so wait for the actual sandbox controls.
        await page.waitForFunction(() => {
          const buttons = Array.from(document.querySelectorAll('button'));
          const hasStart = buttons.some(b => b.textContent.trim().includes('Start Sandbox'));
          const hasOpen = buttons.some(b => b.textContent.trim().includes('Open Sandbox'));
          const hasResume = buttons.some(b => b.textContent.trim().includes('Resume'));
          const inputs = document.querySelectorAll('input[aria-label="Copyable input"]');
          const hasCredentials = inputs.length > 0 && inputs[0].value.trim().length > 0;
          return hasStart || hasOpen || hasResume || hasCredentials;
        }, null, { timeout });
      };
```

**Exact new block:**

```javascript
      const _waitForSandboxEntry = async (timeout = 30000) => {
        // Skeleton clears before cards appear, so wait for the actual sandbox controls.
        await page.waitForFunction(() => {
          const buttons = Array.from(document.querySelectorAll('button'));
          const hasStart = buttons.some(b => b.textContent.trim().includes('Start Sandbox'));
          const hasOpen = buttons.some(b => b.textContent.trim().includes('Open Sandbox'));
          const hasResume = buttons.some(b => b.textContent.trim().includes('Resume'));
          const inputs = document.querySelectorAll('input[aria-label="Copyable input"]');
          const hasCredentials = inputs.length > 0 && inputs[0].value.trim().length > 0;
          const hasExtendDialog = Array.from(document.querySelectorAll('[role="dialog"]'))
            .some(d => (d.innerText || '').includes('Extend Your Session'));
          return hasStart || hasOpen || hasResume || hasCredentials || hasExtendDialog;
        }, null, { timeout });
      };
```

---

### Change 2 — `playwright/acg_credentials.js`: add `_dismissExtendYourSessionDialog` helper

Insert immediately after the `_waitForSandboxEntrySoft` definition (after line 368,
before `let sandboxEntryReady`). All clicks use `page.evaluate()` — direct DOM `.click()`
bypasses Playwright's locator/overlay mechanism entirely, preventing any blocking.

**Insert this block between `_waitForSandboxEntrySoft` and `let sandboxEntryReady`:**

```javascript
      const _dismissExtendYourSessionDialog = async () => {
        const _dialogVisible = await page.evaluate(() =>
          Array.from(document.querySelectorAll('[role="dialog"]'))
            .some(d => (d.innerText || '').includes('Extend Your Session'))
        ).catch(() => false);
        if (!_dialogVisible) return;
        console.error('INFO: "Extend Your Session" dialog detected — clicking Extend Session via DOM...');
        await page.evaluate(() => {
          const dialog = Array.from(document.querySelectorAll('[role="dialog"]'))
            .find(d => (d.innerText || '').includes('Extend Your Session'));
          if (!dialog) return;
          const btn = Array.from(dialog.querySelectorAll('button'))
            .find(b => (b.textContent || '').trim().includes('Extend Session'));
          if (btn) btn.click();
        }).catch(() => {});
        await page.waitForTimeout(2000);
        await page.evaluate(() => {
          const closeBtn = document.querySelector('button[aria-label="close" i]');
          if (closeBtn) { closeBtn.click(); return; }
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          let n;
          while ((n = walker.nextNode())) {
            if ((n.nodeValue || '').includes('Your sandbox has been extended.')) {
              let el = n.parentElement;
              for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
                const bs = [...el.querySelectorAll('button')];
                if (bs.length) { bs[bs.length - 1].click(); return; }
              }
              break;
            }
          }
        }).catch(() => {});
        await page.waitForTimeout(500);
        await page.waitForFunction(
          () => !Array.from(document.querySelectorAll('[role="dialog"]'))
            .some(d => (d.innerText || '').includes('Extend Your Session')),
          { timeout: 5000 }
        ).catch(() => console.error('WARN: "Extend Your Session" dialog did not close within 5s — proceeding anyway'));
      };

```

---

### Change 3 — `playwright/acg_credentials.js`: call `_dismissExtendYourSessionDialog` at three sites

**Site A — before first `_waitForSandboxEntrySoft` call (line 371):**

Old:
```javascript
      let sandboxEntryReady = await _waitForSandboxEntrySoft(30000);
```

New:
```javascript
      await _dismissExtendYourSessionDialog();
      let sandboxEntryReady = await _waitForSandboxEntrySoft(30000);
```

---

**Site B — after all `_waitForSandboxEntrySoft` calls, before the `if (!sandboxEntryReady)` warn (line 386):**

Old:
```javascript
      if (!sandboxEntryReady) {
        // The sandbox button/credentials did not appear — proceed anyway and let the
        // button-click block below surface the real failure with more context.
        console.error('WARN: Timed out waiting for sandbox buttons or credentials — proceeding anyway');
      }
```

New:
```javascript
      await _dismissExtendYourSessionDialog();
      if (!sandboxEntryReady) {
        // The sandbox button/credentials did not appear — proceed anyway and let the
        // button-click block below surface the real failure with more context.
        console.error('WARN: Timed out waiting for sandbox buttons or credentials — proceeding anyway');
      }
```

---

**Site C — inside `_waitForCredentials` polling loop, at the top of each iteration (line 394):**

Old:
```javascript
      const _waitForCredentials = async () => {
        console.error('INFO: Waiting for credentials to populate (up to 420s)...');
        const deadline = Date.now() + 420000;
        while (Date.now() < deadline) {
          const inputs = page.locator('input[aria-label="Copyable input"]');
```

New:
```javascript
      const _waitForCredentials = async () => {
        console.error('INFO: Waiting for credentials to populate (up to 420s)...');
        const deadline = Date.now() + 420000;
        while (Date.now() < deadline) {
          await _dismissExtendYourSessionDialog();
          const inputs = page.locator('input[aria-label="Copyable input"]');
```

---

### Change 4 — `bin/acg-credential-test`: new file

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! curl -sf http://localhost:9222/json >/dev/null 2>&1; then
  printf 'ERROR: Chrome CDP not running on port 9222\n' >&2
  printf 'Start with: open -a "Google Chrome" --args --remote-debugging-port=9222\n' >&2
  exit 1
fi
sandbox_url="${1:?Usage: $0 <sandbox-url> [--provider aws|gcp]}"
shift
exec node "$REPO_ROOT/playwright/acg_credentials.js" "$sandbox_url" "$@"
```

Make executable: `chmod +x bin/acg-credential-test`

---

### Change 5 — `bin/acg-extend-test`: new file

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! curl -sf http://localhost:9222/json >/dev/null 2>&1; then
  printf 'ERROR: Chrome CDP not running on port 9222\n' >&2
  printf 'Start with: open -a "Google Chrome" --args --remote-debugging-port=9222\n' >&2
  exit 1
fi
exec node "$REPO_ROOT/playwright/acg_extend.js" "${1:?Usage: $0 <sandbox-url>}"
```

Make executable: `chmod +x bin/acg-extend-test`

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Add `hasExtendDialog` to `waitForFunction`; add `_dismissExtendYourSessionDialog`; call at 3 sites |
| `bin/acg-credential-test` | New file — CDP check + invoke `acg_credentials.js` |
| `bin/acg-extend-test` | New file — CDP check + invoke `acg_extend.js` |

---

## Rules

- `node --check playwright/acg_credentials.js` — must pass (zero errors)
- `shellcheck -S warning bin/acg-credential-test` — zero new warnings
- `shellcheck -S warning bin/acg-extend-test` — zero new warnings
- No other files modified
- Do NOT touch `acg_extend.js` — it is not part of this fix
- Do NOT add `addLocatorHandler` anywhere — all dialog interaction uses `page.evaluate()`

---

## Definition of Done

- [ ] `waitForFunction` in `_waitForSandboxEntry` includes `hasExtendDialog` check (Change 1)
- [ ] `_dismissExtendYourSessionDialog` helper added (Change 2)
- [ ] `_dismissExtendYourSessionDialog` called at all three sites (Change 3)
- [ ] `bin/acg-credential-test` created and executable (Change 4)
- [ ] `bin/acg-extend-test` created and executable (Change 5)
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] `shellcheck -S warning bin/acg-credential-test` passes
- [ ] `shellcheck -S warning bin/acg-extend-test` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in lib-acg with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg-credentials): handle Extend Your Session dialog + add bin test harness
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the three listed above
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT add `addLocatorHandler` — the fix intentionally avoids it
- Do NOT touch `acg_extend.js`
- Do NOT modify k3d-manager — this spec is lib-acg only
