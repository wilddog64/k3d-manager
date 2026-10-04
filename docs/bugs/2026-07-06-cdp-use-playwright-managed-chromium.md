# Bugfix: v0.4.2 (follow-up) — CDP browser must be Playwright-managed Chrome, not system Chrome

**Branch:** `feat/v0.4.2`
**Files:** `scripts/lib/acg/cdp.sh`, `scripts/lib/acg/playwright/lib/output.js`

> Third bug in the v0.4.2 ACG headless-gate line, after
> `2026-07-06-acg-session-gate-not-wired-into-browser-launch.md` (`96bea46`) and
> `2026-07-06-acg-session-gate-not-wired-into-credential-test.md`. Those wired the gate
> onto both entry paths. This spec fixes the browser the gate connects to: it hardcodes
> system `Google Chrome`, whose CDP protocol drifts out from under Playwright on every
> Chrome auto-update.

---

## Problem

`_browser_launch` launches `/Applications/Google Chrome.app` with `--remote-debugging-port`,
then every ACG node script (`acg_session_check.js`, `browser.js`) connects to it with
`chromium.connectOverCDP`. `connectOverCDP` requires the Playwright CDP client to speak the
target Chrome's DevTools protocol. System Chrome auto-updates silently and independently of
Playwright, so it routinely runs two majors ahead of what the pinned Playwright can drive.
When that gap opens, the connect fails:

```
ERROR: browserType.connectOverCDP: Protocol error (Browser.setDownloadBehavior):
  Browser context management is not supported.
```

Observed with system Chrome `150.x` against Playwright `1.60.0` (supports Chromium 148).
Upgrading Playwright does **not** durably fix it (tested `1.61.1` — same failure) because
Chrome will just update again. `make credential-test PROVIDER=aws` and `make up`
(ACG path) both dead-end here, before the headless session gate can even run.

**Root cause:** the CDP target is the user's system Chrome, whose version is uncontrolled
and drifts past the pinned Playwright's protocol support on every Chrome update.

---

## Reproduction

1. System Chrome auto-updates to a major newer than the pinned Playwright supports
   (e.g. Chrome 150 vs Playwright 1.60 → Chromium 148).
2. From lib-foundation: `make credential-test PROVIDER=aws`.
3. **Expected:** the tool connects over CDP, runs the headless Pluralsight gate, extracts creds.
4. **Actual:** `connectOverCDP: … Browser context management is not supported` (exit 1).

---

## Fix

The durable fix is to stop connecting to system Chrome. Launch **Playwright's own
version-locked Chromium** (`Google Chrome for Testing`, already installed by
`npm install` / `playwright install`) instead. Its protocol always matches the pinned
Playwright, so `connectOverCDP` cannot drift out of sync again. Resolve the binary at launch
via `require('playwright').chromium.executablePath()` — no hardcoded path, no fallback to
system Chrome (a fallback would silently reintroduce the drift).

Verified in-repo:

```
$ NODE_PATH=…/scripts/lib/acg/node_modules \
  node -e 'console.log(require("playwright").chromium.executablePath())'
/Users/…/ms-playwright/chromium-1223/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing
```

and `connectOverCDP` against that binary returns `CONNECT_OK contexts=1`.

### Change 1 — `scripts/lib/acg/cdp.sh`: launch the Playwright-managed Chromium

Replace the system-Chrome launch block with one that resolves and runs the Playwright
Chromium binary. Hard-fail if it cannot be resolved (directs the user to `npm install`).

**Exact old block (`cdp.sh`, lines 80–100):**

```bash
  if [[ "$(uname)" == "Darwin" ]]; then
    local _chrome_app_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if [[ -x "${_chrome_app_bin}" ]]; then
      local _chrome_cdp_log="${HOME}/.local/share/k3d-manager/chrome-cdp.log"
      mkdir -p "$(dirname "${_chrome_cdp_log}")"
      "${_chrome_app_bin}" \
        --remote-debugging-port="${_cdp_port}" \
        --password-store=basic \
        --user-data-dir="${_cdp_profile_dir}" \
        --no-first-run \
        --no-default-browser-check \
        >>"${_chrome_cdp_log}" 2>&1 &
    else
      open -a "Google Chrome" --args \
        --remote-debugging-port="${_cdp_port}" \
        --password-store=basic \
        --user-data-dir="${_cdp_profile_dir}"
    fi
  else
    _err "[acg] _browser_launch is macOS-only — $(uname) is not supported"
  fi
```

**Exact new block:**

```bash
  if [[ "$(uname)" == "Darwin" ]]; then
    local _pw_chrome_bin
    _pw_chrome_bin="$(NODE_PATH="${_LIB_ACG_ROOT}/node_modules" node -e 'process.stdout.write(require("playwright").chromium.executablePath())' 2>/dev/null || true)"
    if [[ -z "${_pw_chrome_bin}" || ! -x "${_pw_chrome_bin}" ]]; then
      _err "[acg] Playwright-managed Chromium not found — run 'npm install' (or 'npx playwright install chromium') in ${_LIB_ACG_ROOT}"
    fi
    local _chrome_cdp_log="${HOME}/.local/share/k3d-manager/chrome-cdp.log"
    mkdir -p "$(dirname "${_chrome_cdp_log}")"
    "${_pw_chrome_bin}" \
      --remote-debugging-port="${_cdp_port}" \
      --password-store=basic \
      --user-data-dir="${_cdp_profile_dir}" \
      --no-first-run \
      --no-default-browser-check \
      >>"${_chrome_cdp_log}" 2>&1 &
  else
    _err "[acg] _browser_launch is macOS-only — $(uname) is not supported"
  fi
```

### Change 2 — dedicated profile dir for the managed browser (avoid version-downgrade refusal)

The existing profile (`~/.local/share/k3d-manager/profile`) was written by the newer system
Chrome. Chrome refuses to open a profile from a *newer* version than the running binary
("Your Chrome profile cannot be opened … from a newer version"), so the older
Chrome-for-Testing would reject it on first launch. Point the managed browser at its own
dedicated profile dir so the transition is clean: first run creates it fresh and the headless
gate signs in from Keychain (`k3dm-acg-pluralsight`); every run after is version-consistent
(Playwright and its Chromium bump together, controlled by `package.json`), so the refusal can
never recur. The default is still overridable via `PLAYWRIGHT_AUTH_DIR`.

The profile-dir default string appears **4 times** — 3 in `cdp.sh`, 1 in `output.js`. All four
must change together so the launch, the in-use/lock checks, and the node-side `AUTH_DIR`
agree.

**`cdp.sh` — replace all three occurrences of:**

```bash
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/profile}"
```

**with:**

```bash
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/pw-profile}"
```

(Occurrences: `_cdp_profile_in_use` line 23, `_cdp_remove_stale_singleton_lock` line 51,
`_browser_launch` line 79. `sed`-style global replace of that exact literal is correct —
there are no other uses of the old path in `cdp.sh`.)

**`scripts/lib/acg/playwright/lib/output.js` — exact old block:**

```javascript
const AUTH_DIR = AUTH_DIR_OVERRIDE ||
  path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'profile');
```

**Exact new block:**

```javascript
const AUTH_DIR = AUTH_DIR_OVERRIDE ||
  path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'pw-profile');
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/cdp.sh` | Launch Playwright-managed Chromium (`chromium.executablePath()`) instead of system Chrome; hard-fail if absent; repoint profile default to `pw-profile` (3×) |
| `scripts/lib/acg/playwright/lib/output.js` | Repoint `AUTH_DIR` default to `pw-profile` to match `cdp.sh` |
| `CHANGE.md` | `[Unreleased] ### Fixed` entry |

---

## Rules

- `shellcheck -S warning scripts/lib/acg/cdp.sh` — zero new warnings
- `node --check scripts/lib/acg/playwright/lib/output.js` — clean (covered by `npm run check`)
- In `scripts/lib/acg/`: `npm run check` and `npm test` (jest) stay green
- Sourcing probe: `bash -c 'source scripts/lib/acg/cdp.sh; declare -f _browser_launch'` exits 0
- No `open -a "Google Chrome"` reference remains in the launch block; no `/Applications/Google Chrome.app` path remains in `cdp.sh`
- No files touched other than the three listed

---

## Definition of Done

- [ ] `_browser_launch` resolves the binary via `require('playwright').chromium.executablePath()` and launches it with the existing CDP flags
- [ ] Hard-fails with a clear `npm install` message when the Playwright Chromium is missing (no system-Chrome fallback)
- [ ] Profile default is `pw-profile` in all 3 `cdp.sh` sites and in `output.js` `AUTH_DIR`
- [ ] `shellcheck -S warning scripts/lib/acg/cdp.sh` clean
- [ ] `npm run check` + `npm test` green in `scripts/lib/acg/`
- [ ] Sourcing probe exits 0
- [ ] `CHANGE.md` `[Unreleased] ### Fixed` entry added
- [ ] Committed and pushed to `feat/v0.4.2`
- [ ] lib-foundation memory-bank updated with commit SHA and task status
- [ ] **USER acceptance gate (NOT Codex — needs live browser + AWS sandbox + Keychain creds):**
      In lib-foundation, quit any stale system Chrome holding `:9222`, then
      `make credential-test PROVIDER=aws` launches Chrome-for-Testing, signs in headlessly,
      and extracts creds without manual login. Must pass before any subtree-pull.
- [ ] Follow-up (after the lib-foundation gate passes + v0.4.2 tag): subtree-pull into
      k3d-manager, then confirm `CLUSTER_PROVIDER=k3s-aws make up`.

**Commit message (exact):**
```
fix(acg): launch Playwright-managed Chromium for CDP instead of system Chrome
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the three listed targets
- Do NOT keep or add a fallback to system Chrome (`/Applications/Google Chrome.app` or
  `open -a "Google Chrome"`) — that is exactly the drift this fix removes
- Do NOT edit `acg_session_check.js`, `browser.js`, `pluralsight_login.js`, or `sandbox.js`
  — the connect logic is reused, only the launched binary and profile path change
- Do NOT run the live `make credential-test` yourself and report it as passed — that gate is
  the user's to run in lib-foundation
- Do NOT commit to `main` — work on `feat/v0.4.2`
- Do NOT edit the k3d-manager `scripts/lib/foundation/` copy — upstream-first; the consumer
  picks it up via subtree pull after the v0.4.2 tag
