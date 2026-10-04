# Bugfix: v0.4.2 (follow-up) — ACG headless session gate not wired into `acg-credential-test`

**Branch:** `feat/v0.4.2`
**Files:** `scripts/lib/acg/bin/acg-credential-test`, `scripts/lib/acg/playwright/lib/browser.js`

> Continuation of `2026-07-06-acg-session-gate-not-wired-into-browser-launch.md` (`96bea46`).
> That commit wired `_cdp_ensure_acg_session` into `_browser_launch`, which fixes the
> `make up` / `bin/cluster-up` path. This spec closes the second half of the same bug: the
> standalone `make credential-test` / `bin/acg-credential-test` path never calls
> `_browser_launch`, so it still runs against an unauthenticated CDP Chrome.

---

## Problem

`make credential-test` (→ `bin/acg-credential-test`) only probes that CDP Chrome is up on
`:9222`, then runs `node acg_credentials.js`. It **never calls `_browser_launch`**, so the
headless Pluralsight session gate (`_cdp_ensure_acg_session`, wired in `96bea46`) never fires
on this path. If the running CDP Chrome is signed out, extraction lands on the Pluralsight
sign-in page and fails:

```
WARN: Sandbox card buttons did not appear within 30s. URL: https://app.pluralsight.com/id | Buttons: ["Sign in"]
ERROR: Neither Delete Sandbox nor Open Sandbox visible. URL: https://app.pluralsight.com/id | Buttons: ["Sign in"]
ERROR: Sandbox restart failed — delete it manually and re-run.
make: *** [credential-test] Error 1
```

A second, latent defect surfaces in the same run: when `connectBrowser`
(`playwright/lib/browser.js`) reaches a CDP Chrome that exposes no usable context, it falls
back to `chromium.launchPersistentContext(AUTH_DIR, …)` on the very profile the live CDP
Chrome already holds — a guaranteed conflict:

```
ERROR: browserType.launchPersistentContext: Opening in existing browser session.
  This usually means that the profile is already in use by another instance of Chromium.
```

**Root cause:**
1. The v0.4.1 headless gate is reachable only through `_browser_launch`; `bin/acg-credential-test`
   is a standalone script that bypasses it, so `make credential-test` is not unattended.
2. `connectBrowser` treats "CDP reachable but no context" the same as "no Chrome at all" and
   attempts a persistent-context launch on the locked profile, hard-failing with a cryptic
   error instead of a clear one.

---

## Reproduction

1. A CDP Chrome is running on `:9222` (dedicated `~/.local/share/k3d-manager/profile`) but is
   **signed out** of Pluralsight.
2. From lib-foundation: `make credential-test PROVIDER=aws` (or `cd scripts/lib/acg && bin/acg-credential-test <url>`).
3. **Expected:** the tool signs into Pluralsight headlessly (Keychain `k3dm-acg-pluralsight`),
   then extracts and validates AWS credentials.
4. **Actual:** no sign-in; `launchPersistentContext` conflict, then extraction/restart fail on
   the `Sign in` page (exit 1).

---

## Fix

### Change 1 — `scripts/lib/acg/bin/acg-credential-test`: run the same gate after the CDP-alive check

Source `cdp.sh` (which self-bootstraps `system.sh` for standalone use) and invoke the existing
`_cdp_ensure_acg_session` before extraction. This reuses the exact gate from the `make up` path
— same Keychain-backed credential load, same `K3DM_ACG_SKIP_SESSION_CHECK=1` opt-out, same
`K3DM_NONINTERACTIVE`/no-TTY fast-fail — with **zero credential-handling duplication**. Verified:
sourcing `cdp.sh` standalone exposes `_cdp_ensure_acg_session`, `_secret_load_data`, `_info`,
`_err`, `_command_exist`.

**Exact old block (`bin/acg-credential-test`, lines 1–10):**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! curl -sf http://localhost:9222/json >/dev/null 2>&1; then
  printf 'ERROR: Chrome CDP not running on port 9222\n' >&2
  printf 'Start with: open -a "Google Chrome" --args --remote-debugging-port=9222\n' >&2
  exit 1
fi
```

**Exact new block:**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! curl -sf http://localhost:9222/json >/dev/null 2>&1; then
  printf 'ERROR: Chrome CDP not running on port 9222\n' >&2
  printf 'Start with: open -a "Google Chrome" --args --remote-debugging-port=9222\n' >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/cdp.sh"
_cdp_ensure_acg_session
```

**Notes for the implementer:**
- `REPO_ROOT` is `scripts/lib/acg` (the bin lives at `scripts/lib/acg/bin/`), so `${REPO_ROOT}/cdp.sh`
  resolves correctly and `_cdp_ensure_acg_session` sets `_LIB_ACG_ROOT` from `cdp.sh`'s own path.
- The `# shellcheck source=/dev/null` directive is required so shellcheck does not try to follow
  the sourced file. It is a directive, not a narrative comment.
- On the `make up` path the gate also runs inside `_browser_launch`; running it again here is
  idempotent (an already-authenticated session returns `ACG_SESSION_OK` immediately).
- Do **not** duplicate the Keychain read or the node invocation — call `_cdp_ensure_acg_session`.

### Change 2 — `scripts/lib/acg/playwright/lib/browser.js`: don't launch a persistent context on a locked profile

When `connectOverCDP` reached a live Chrome but no usable context could be exposed, fail with a
clear, actionable error instead of a doomed `launchPersistentContext` against the in-use profile.
The persistent-context fallback stays valid only when **no** CDP Chrome is reachable.

**Exact old block (`browser.js`, lines 7–9):**

```javascript
async function connectBrowser() {
  let browserContext;
  let cdpBrowser = null;
```

**Exact new block:**

```javascript
async function connectBrowser() {
  let browserContext;
  let cdpBrowser = null;
  let cdpReachable = false;
```

**Exact old block (`browser.js`, the `connectOverCDP` call):**

```javascript
      cdpBrowser = await chromium.connectOverCDP(CDP_URL);
      const cdpContexts = cdpBrowser.contexts();
```

**Exact new block:**

```javascript
      cdpBrowser = await chromium.connectOverCDP(CDP_URL);
      cdpReachable = true;
      const cdpContexts = cdpBrowser.contexts();
```

**Exact old block (`browser.js`, the fallback):**

```javascript
    if (!browserContext) {
      browserContext = await chromium.launchPersistentContext(AUTH_DIR, {
        headless: false,
        channel: 'chrome',
        args: ['--password-store=basic'],
      });
    }
```

**Exact new block:**

```javascript
    if (!browserContext) {
      if (cdpReachable) {
        throw new Error(
          'CDP Chrome is running but exposes no usable browser context — the profile is ' +
          'locked by the live CDP instance, so launchPersistentContext cannot open it. ' +
          'Ensure the CDP Chrome is signed into Pluralsight (run the session gate) and retry.'
        );
      }
      browserContext = await chromium.launchPersistentContext(AUTH_DIR, {
        headless: false,
        channel: 'chrome',
        args: ['--password-store=basic'],
      });
    }
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/bin/acg-credential-test` | Source `cdp.sh` and call `_cdp_ensure_acg_session` after the CDP-alive check |
| `scripts/lib/acg/playwright/lib/browser.js` | Guard the `launchPersistentContext` fallback so it never runs against a locked CDP profile |
| `CHANGE.md` | `[Unreleased] ### Fixed` entry |

---

## Rules

- `shellcheck -S warning scripts/lib/acg/bin/acg-credential-test` — zero new warnings
- `node --check scripts/lib/acg/playwright/lib/browser.js` — clean (covered by `npm run check`)
- In `scripts/lib/acg/`: `npm run check` and `npm test` (jest) stay green
- Sourcing probe: `bash -c 'source scripts/lib/acg/cdp.sh; declare -f _cdp_ensure_acg_session'` exits 0
- No files touched other than the three listed

---

## Definition of Done

- [ ] `bin/acg-credential-test` sources `cdp.sh` and calls `_cdp_ensure_acg_session` after the CDP-alive check
- [ ] Gate opt-out (`K3DM_ACG_SKIP_SESSION_CHECK=1`) and fast-fail behavior inherited unchanged
- [ ] `connectBrowser` throws a clear error (no `launchPersistentContext`) when CDP is reachable but context-less
- [ ] `shellcheck -S warning scripts/lib/acg/bin/acg-credential-test` clean
- [ ] `npm run check` + `npm test` green in `scripts/lib/acg/`
- [ ] Sourcing probe exits 0
- [ ] `CHANGE.md` `[Unreleased] ### Fixed` entry added
- [ ] Committed and pushed to `feat/v0.4.2`
- [ ] lib-foundation memory-bank updated with commit SHA and task status
- [ ] **USER acceptance gate (NOT Codex — needs live browser + AWS sandbox + Keychain creds):**
      `make credential-test PROVIDER=aws` in **lib-foundation** signs in headlessly and extracts
      creds without manual login. This must pass in lib-foundation before any subtree-pull.
- [ ] Follow-up (after the lib-foundation gate passes + v0.4.2 tag): subtree-pull into k3d-manager,
      then confirm `CLUSTER_PROVIDER=k3s-aws make up`.

**Commit message (exact):**
```
fix(acg): wire _cdp_ensure_acg_session into acg-credential-test + guard connectBrowser CDP fallback
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the three listed targets
- Do NOT edit `cdp.sh`, `acg_session_check.js`, `acg_credentials.js`, or `playwright/lib/sandbox.js`
  (`handleSignIn`) — the gate is reused, not re-implemented
- Do NOT run the live `make credential-test` yourself and report it as passed — that gate is the
  user's to run in lib-foundation
- Do NOT commit to `main` — work on `feat/v0.4.2`
- Do NOT edit the k3d-manager `scripts/lib/foundation/` copy — upstream-first; the consumer picks
  it up via subtree pull after the v0.4.2 tag
