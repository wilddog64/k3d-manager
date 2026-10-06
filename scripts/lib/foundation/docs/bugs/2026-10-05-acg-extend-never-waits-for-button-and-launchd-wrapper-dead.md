# Bug: ACG sandbox extend almost never succeeds unattended — the extend script never waits for the button, and the launchd watcher has never run it

**Status:** FIXED
**Filed:** 2026-10-05
**Branch:** `fix/acg-extend-wait-for-button`
**Severity:** High. With the operator away, an ACG sandbox dies at its first shutdown unless a person
clicks Extend. Both unattended extend paths are broken.
**Files:** `scripts/lib/acg/playwright/acg_extend.js`, `scripts/lib/acg/acg.sh`,
`scripts/lib/acg/tests/providers/acg_extend.test.js`, `scripts/tests/lib/acg.bats`, `CHANGE.md`

## Symptom

Two watchers try to extend the sandbox. Both fail.

**1. The in-process watcher (`acg_watch`, started by k3d-manager `make up`).** From the operator's
pane on 2026-10-05:

```
# a wake where the button happened to be on screen — succeeds
Found extend button (immediately) with selector: [data-heap-id="Hands-on Playground - Click - AWS Sandbox - Extend Sandbox"]
Extend action complete (Immediate).

# a later wake — fails
INFO: Calculated remaining TTL: ~44 minutes
INFO: Within 1h extension window (44m remaining). Proceeding to extend...
INFO: Clicking Open Sandbox to reveal extend panel...
WARN: Could not save extend failure screenshot: page.screenshot: Timeout 30000ms exceeded.
ERROR: Extend button not found or not visible after multiple attempts (including recovery)
INFO: [acg] Extend failed — open https://app.pluralsight.com/hands-on/playground/cloud-sandboxes to extend manually
```

The operator reports this failure most of the time, and sometimes has to click Extend by hand.

**2. The launchd watcher (`com.k3d-manager.acg-watch`, installed by `acg_watch_start`).** Every
run since installation has failed before reaching Node:

```
/Users/…/.local/share/k3d-manager/acg-watch-run.sh: line 4: /Users/…/k3d-manager/scripts/lib/foundation/scripts/lib/acg/../../k3d-manager: No such file or directory
[acg-watch] Extend failed — open https://app.pluralsight.com/cloud-playground/cloud-sandboxes to extend manually
```

## Root cause

### A — `acg_extend.js` looks for the button once, for 0 ms

`_waitForVisibleExtendButton(page, extendSelectors, 0, 'immediately')` is the only check on the
page the script lands on. With a 0 ms budget it is a single snapshot. If the button, or the
"Extend Your Session" dialog Pluralsight shows near expiry, is not rendered at that instant, the
script goes on to parse the TTL. It then clicks **Open Sandbox**, whose panel has had no Extend
button since the Pluralsight redesign (`k3d-manager docs/bugs/archive/…/2026-05-15-acg-extend-button-not-found.md`).
Nothing ever waits for the button where it actually appears, and nothing reloads the page.

The selector list also lacks the dialog-scoped selectors that `lib/sandbox.js`
`_dismissExtendYourSessionDialog` already uses successfully for the same dialog during credential
extraction.

On failure, the full-page screenshot times out at 30 s, so there is no record of the page. The
90 s overall budget leaves no room for a real wait.

### B — the launchd wrapper calls a dispatcher that does not exist

`_acg_watch_write_wrapper` writes `"${_LIB_ACG_ROOT}/../../k3d-manager" acg_extend_playwright …`.
That assumed the pre-absorption layout. Inside k3d-manager, `_LIB_ACG_ROOT` is
`scripts/lib/foundation/scripts/lib/acg`, so the path resolves to
`scripts/lib/foundation/scripts/k3d-manager`, which does not exist. Even with a correct path,
launchd's `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`) has no `node`.

### C — `acg_watch` gives up for 3.5 h after one failure

A failed extend in the last hour is followed by `sleep 12600`. The sandbox is dead long before the
next attempt.

## Fix spec

### File 1 — `scripts/lib/acg/playwright/acg_extend.js`

**1a.** In `_captureExtendFailure`, replace:

```js
    await page.screenshot({ path: screenshotPath, fullPage: true });
```

with:

```js
    await page.screenshot({ path: screenshotPath, fullPage: false, timeout: 10000 });
```

**1b.** Directly after the `_captureExtendFailure` function (before `async function extendSandbox() {`),
add:

```js
function _safeButtonLabels(labels) {
  const seen = new Set();
  const out = [];
  for (const raw of labels || []) {
    const label = String(raw || '').replace(/\s+/g, ' ').trim();
    if (!label) continue;
    if (/[A-Za-z0-9+/=]{16,}/.test(label)) continue;
    const clipped = label.length > 60 ? `${label.slice(0, 60)}…` : label;
    if (seen.has(clipped)) continue;
    seen.add(clipped);
    out.push(clipped);
    if (out.length >= 40) break;
  }
  return out;
}

async function _logVisibleButtonLabels(page) {
  const state = await page.evaluate(() => {
    const visible = (el) => {
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    };
    const labels = Array.from(document.querySelectorAll('button, [role="button"]'))
      .filter(visible)
      .map(el => el.innerText || el.getAttribute('aria-label') || '');
    const dialog = Array.from(document.querySelectorAll('[role="dialog"], [role="alertdialog"]'))
      .some(visible);
    return { labels, dialog };
  }).catch(() => ({ labels: [], dialog: false }));
  console.error(`INFO: Dialog open at failure: ${state.dialog ? 'yes' : 'no'}`);
  console.error(`INFO: Visible buttons at failure: ${JSON.stringify(_safeButtonLabels(state.labels))}`);
}

async function _findExtendButton(page, selectors, targetUrl, waitMs = 15000) {
  const onPage = await _waitForVisibleExtendButton(page, selectors, waitMs, 'on sandbox page');
  if (onPage) return onPage;
  console.error('INFO: Extend button not visible — reloading the sandbox page and retrying...');
  await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(
    (e) => console.error(`WARN: Reload failed: ${e.message}`)
  );
  await page.waitForFunction(
    () => !document.querySelector('[aria-busy="true"]'),
    { timeout: 30000 }
  ).catch(() => console.error('WARN: Skeleton loaders did not clear after reload — proceeding'));
  return _waitForVisibleExtendButton(page, selectors, waitMs, 'after reload');
}
```

`_safeButtonLabels` drops any label containing a 16+ character run of `[A-Za-z0-9+/=]`, so an
access key or secret that ever lands in a button can never reach the log.

**1c.** At the top of `extendSelectors`, insert the three dialog-scoped selectors, so the array
begins:

```js
    const extendSelectors = [
      '[data-testid="extend-sandbox-modal"] button:has-text("Extend")',
      '[role="alertdialog"] button:has-text("Extend")',
      '[role="dialog"] button:has-text("Extend")',
      '[data-heap-id="Hands-on Playground - Click - AWS Sandbox - Extend Sandbox"]',
```

The remaining entries stay as they are, in order.

**1d.** Replace:

```js
    // 3. Reveal the panel/modal if still not clicked
```

with:

```js
    // 2b. Wait for the button where it appears (listing card or "Extend Your Session" dialog),
    // reloading once — the 0 ms immediate check above is a single snapshot.
    if (!clicked && !(remainingMins !== null && remainingMins <= 0)) {
      const _waitedBtn = await _findExtendButton(page, extendSelectors, targetUrl);
      if (_waitedBtn) {
        await _waitedBtn.click({ force: true });
        clicked = true;
      }
    }

    // 3. Reveal the panel/modal if still not clicked
```

The existing `const isPanelOpen = clicked;` then skips Open Sandbox when the wait found the
button, and the Ghost State block already requires `!clicked`.

**1e.** Replace:

```js
    if (!clicked) {
      await _captureExtendFailure(page, 'missing-extend-button');
```

with:

```js
    if (!clicked) {
      await _logVisibleButtonLabels(page);
      await _captureExtendFailure(page, 'missing-extend-button');
```

**1f.** Replace `const OVERALL_TIMEOUT_MS = 90000;` with `const OVERALL_TIMEOUT_MS = 240000;`.

**1g.** Replace the `module.exports` block with:

```js
module.exports = {
  _findExtendButton,
  _isSandboxPageUrl,
  _normalizeSandboxUrl,
  _safeButtonLabels,
  _selectExtendPage,
};
```

No other change to `acg_extend.js`. The Ghost State block, the 65 m window and the TTL parsing stay
as they are.

### File 2 — `scripts/lib/acg/acg.sh`

**2a.** In `_acg_watch_write_wrapper`, replace:

```bash
_acg_watch_write_wrapper() {
  local sandbox_url="$1"
  mkdir -p "$(dirname "${_ACG_WATCH_WRAPPER}")"
  # NOTE: dispatcher path re-resolved in v0.4.0 Phase 2 (k3d-manager rewire).
  cat > "${_ACG_WATCH_WRAPPER}" <<WRAPPER
#!/usr/bin/env bash
# Auto-generated by acg_watch_start — do not edit manually
set -euo pipefail
"${_LIB_ACG_ROOT}/../../k3d-manager" acg_extend_playwright "${sandbox_url}" \\
  || printf '[acg-watch] Extend failed — open %s to extend manually\\n' "${sandbox_url}" >&2
WRAPPER
  chmod +x "${_ACG_WATCH_WRAPPER}"
}
```

with:

```bash
_acg_watch_write_wrapper() {
  local sandbox_url="$1"
  local node_bin
  node_bin="$(command -v node 2>/dev/null || true)"
  if [[ -z "${node_bin}" ]]; then
    _err "[acg] node is required for the launchd watcher — install Node.js"
    return 1
  fi
  mkdir -p "$(dirname "${_ACG_WATCH_WRAPPER}")"
  cat > "${_ACG_WATCH_WRAPPER}" <<WRAPPER
#!/usr/bin/env bash
# Auto-generated by acg_watch_start — do not edit manually
set -euo pipefail
export PATH="$(dirname "${node_bin}"):\${PATH}"
printf '[acg-watch] %s extend run\\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" >&2
"${node_bin}" "${_LIB_ACG_ROOT}/playwright/acg_extend.js" "${sandbox_url}" \\
  || printf '[acg-watch] Extend failed — open %s to extend manually\\n' "${sandbox_url}" >&2
WRAPPER
  chmod +x "${_ACG_WATCH_WRAPPER}"
}
```

Check `acg_watch_start`'s call site: `_acg_watch_write_wrapper "$sandbox_url"` must stop the
install when it returns 1. If the caller does not already fail on it, change that one line to
`_acg_watch_write_wrapper "$sandbox_url" || return 1`.

**2b.** In `acg_watch`, replace:

```bash
  local interval="${1:-12600}"
  _info "[acg] Sandbox watcher started (PID $$, extending every $((interval / 3600))h)"

  while true; do
    sleep "$interval"
    if [[ -z "$(_acg_get_instance_id 2>/dev/null)" ]]; then
      _info "[acg] Instance gone — watcher stopping."
      return 0
    fi
    _info "[acg] Extending sandbox TTL..."
    _acg_extend_playwright "${_ACG_SANDBOX_URL}" \
      || _info "[acg] Extend failed — open ${_ACG_SANDBOX_URL} to extend manually"
  done
```

with:

```bash
  local interval="${1:-12600}"
  local retry_interval="${ACG_WATCH_RETRY_INTERVAL:-600}"
  local attempt
  _info "[acg] Sandbox watcher started (PID $$, extending every $((interval / 3600))h)"

  while true; do
    sleep "$interval"
    if [[ -z "$(_acg_get_instance_id 2>/dev/null)" ]]; then
      _info "[acg] Instance gone — watcher stopping."
      return 0
    fi
    _info "[acg] Extending sandbox TTL..."
    attempt=1
    until _acg_extend_playwright "${_ACG_SANDBOX_URL}"; do
      if (( attempt >= 3 )); then
        _info "[acg] Extend failed ${attempt} times — open ${_ACG_SANDBOX_URL} to extend manually"
        break
      fi
      _info "[acg] Extend failed (attempt ${attempt}/3) — retrying in ${retry_interval}s"
      sleep "${retry_interval}"
      attempt=$((attempt + 1))
    done
  done
```

Also add one line to the `acg_watch` HELP heredoc, after `Default interval: 12600 seconds (3.5 hours).`:

```
A failed extend is retried up to 3 times, ACG_WATCH_RETRY_INTERVAL seconds apart (default 600).
```

### File 3 — `scripts/lib/acg/tests/providers/acg_extend.test.js`

Add `_findExtendButton` and `_safeButtonLabels` to the `require` destructure, and add a second
`describe('acg_extend button wait', …)` block. Build a fake page:

- `locator(selector)` returns `{ first: () => ({ isVisible: async () => <rule>, click: async () => {} }) }`,
  where the rule is driven by test state.
- `waitForTimeout: async () => {}`, `waitForFunction: async () => {}`,
  `goto: jest.fn(async () => { state.reloaded = true; })`.

Pass `waitMs` of 50 or less so tests stay fast. Silence `console.error` with `jest.spyOn`.

1. **finds a button that renders after the first poll, without reloading:** the selector
   `'button:has-text("Extend")'` becomes visible on its 3rd `isVisible` call. Expect a non-null
   result and `goto` not called.
2. **reloads once when the button never appears on the first page:** visible only after
   `state.reloaded` is true. Expect a non-null result and `goto` called exactly once with the
   target URL.
3. **returns null when the button never appears:** never visible. Expect `null` and `goto` called
   once.
4. **`_safeButtonLabels` drops credential-shaped labels:** input
   `['Open Sandbox', '  Extend\n Sandbox ', 'AKIAABCDEFGHIJKLMNOP', 'x'.repeat(80), 'Open Sandbox', '']`.
   Expect `['Open Sandbox', 'Extend Sandbox']`. The 80-char label is a 16+ run, so it is dropped
   too.

### File 4 — `scripts/tests/lib/acg.bats`

Use the file's existing `setup`. Stub in-shell, after sourcing. Use `[[ … ]] || false` or `run !`
for negatives; never a bare `! [[ … ]]`.

1. **acg_watch retries a failed extend and stops retrying on success:** `sleep() { :; }`;
   `_acg_get_instance_id` returns `i-a` on its first call and `""` after (counter file under
   `${BATS_TEST_TMPDIR}`); `_acg_extend_playwright` fails on its first 2 calls and succeeds on the
   3rd (attempt counter file). `run acg_watch 1`. Expect status 0, exactly **3** attempts, output
   contains `attempt 1/3` and `attempt 2/3`, and does not contain `extend manually`.
2. **acg_watch gives up after 3 failed attempts:** same, but the extend stub always fails. Expect
   status 0, exactly **3** attempts, output contains `Extend failed 3 times`.
3. **the launchd wrapper runs acg_extend.js with node found under a launchd PATH:** make
   `${BATS_TEST_TMPDIR}/nodebin/node` a stub script that writes `"$@"` to
   `${BATS_TEST_TMPDIR}/node-args` and exits 0. With `PATH="${BATS_TEST_TMPDIR}/nodebin:${PATH}"`,
   call `_acg_watch_write_wrapper 'https://example.test/sandbox'`. Then
   `run env PATH=/usr/bin:/bin bash "${_ACG_WATCH_WRAPPER}"`. Expect status 0, the args file
   contains `playwright/acg_extend.js` and `https://example.test/sandbox`, and the wrapper text does
   not contain `../../k3d-manager`.
4. **the wrapper writer refuses when node is absent:** `run env PATH=/usr/bin:/bin bash -c
   'source "<path to acg.sh>"; _acg_watch_write_wrapper https://example.test/sandbox'`, with
   `HOME` set to the test home so no real wrapper is touched. Expect a non-zero status. Skip this
   test with `skip` if `/usr/bin/node` or `/bin/node` exists on the runner.

`_ACG_WATCH_WRAPPER` derives from `HOME`, which `setup` points at the test dir. Confirm this
before writing, so no test can overwrite the operator's real wrapper.

### File 5 — `CHANGE.md`

Under `## [Unreleased]` → `### Fixed` (create the subsection if absent), add a prose entry. It
covers three points:

- `acg_extend.js` now waits up to 15 s for the Extend button, including the "Extend Your Session"
  dialog, reloads the sandbox page once, and only then falls back to Open Sandbox. Previously the
  only check was a 0 ms snapshot, followed by an Open Sandbox panel that has no Extend button.
- On failure it logs the visible button labels (credential-shaped labels are filtered) and takes a
  viewport screenshot with a 10 s timeout.
- The launchd watcher wrapper called a dispatcher path that does not exist inside k3d-manager and
  could not find `node` under launchd. It now runs `acg_extend.js` directly with an absolute node
  path. `acg_watch` retries a failed extend up to 3 times, 10 minutes apart, instead of waiting
  3.5 h.

Flip this file's **Status** to FIXED.

## Definition of Done

- [ ] Pre-fix proof: jest tests 1–3 and BATS tests 1 and 3 are RED against `origin/main` (paste
      the output). Jest test 4 and BATS tests 2 and 4 may be red only because the function is
      missing; state which.
- [ ] Mutation 1: remove the `page.goto` reload from `_findExtendButton`; jest test 2 goes red.
- [ ] Mutation 2: change `attempt >= 3` to `attempt >= 1`; BATS test 1 goes red.
- [ ] For each mutation, restore from a `$TMPDIR` snapshot and prove the restore with `cmp`.
- [ ] `cd scripts/lib/acg && npm run check && npm test` green; paste the counts.
- [ ] `bats scripts/tests/lib/acg.bats` green; paste the counts.
- [ ] `shellcheck scripts/lib/acg/acg.sh` shows no new findings vs `HEAD`.
- [ ] Changes are left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT change the Ghost State delete/restart block, the 65 m window, TTL parsing, the 12600 s
  interval, or any existing selector (only prepend the three dialog selectors).
- Do NOT run node against Pluralsight, `acg_watch_start`, `launchctl`, `make up`, or anything
  live. No AWS or browser access. Never write to the real `~/.local/share/k3d-manager` or
  `~/Library/LaunchAgents`.
- Do NOT touch k3d-manager or files outside those listed. No commit, push, PR or `--no-verify`.
