# Bug Fix: add headless flags to Linux CDP launch; unify profile path to `profile/`

**Branch:** `k3d-manager-v1.1.0`
**Files:** `scripts/plugins/antigravity.sh`, `scripts/etc/playwright/vars.sh`,
`scripts/playwright/acg_credentials.js`, `scripts/playwright/acg_extend.js`,
`scripts/tests/plugins/gcp.bats`

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `scripts/plugins/antigravity.sh` function `_browser_launch` (lines 64–89)
3. Read `scripts/etc/playwright/vars.sh`

---

## Problem

`make up` fails on Linux (ACG sandbox) with:
```
INFO: [acg] Chrome CDP not available on port 9222 — launching Chrome...
make: *** [up] Error 1
```

Root cause chain:
1. `acg_get_credentials` finds no CDP on port 9222 → calls `_browser_launch`
2. Linux branch launches Chrome without `--headless=new`, `--no-sandbox`, or
   `--disable-dev-shm-usage`
3. On a display-less ACG sandbox there is no `$DISPLAY` — Chrome silently exits
4. `_antigravity_browser_ready 30` polls port 9222 for 30s, finds nothing → `_err` → exit 1

Secondary issue: `_browser_launch` hardcodes `~/.config/acg-chrome-profile`.
All Playwright scripts and the launchd plist should share the same profile directory.
The canonical path is `~/.local/share/k3d-manager/profile/`.

---

## Fix

### 1. `scripts/etc/playwright/vars.sh` — change profile path (source of truth)

```bash
# current
PLAYWRIGHT_AUTH_DIR="${HOME}/.local/share/k3d-manager/playwright-auth"
```

```bash
# replacement
PLAYWRIGHT_AUTH_DIR="${HOME}/.local/share/k3d-manager/profile"
```

---

### 2. `scripts/plugins/antigravity.sh` — add headless flags; use `PLAYWRIGHT_AUTH_DIR`

```bash
# current — _browser_launch function body
  _info "Chrome not running — launching with --remote-debugging-port=9222..."
  if [[ "$(uname)" == "Darwin" ]]; then
    open -a "Google Chrome" --args \
      --remote-debugging-port=9222 \
      --password-store=basic \
      --user-data-dir="${HOME}/.config/acg-chrome-profile"
  else
    local _chrome_bin
    _chrome_bin=$(command -v google-chrome 2>/dev/null || command -v google-chrome-stable 2>/dev/null || command -v chromium-browser 2>/dev/null || command -v chromium 2>/dev/null || true)
    if [[ -z "${_chrome_bin}" ]]; then
      _err "[antigravity] Chrome/Chromium not found — install google-chrome, google-chrome-stable, chromium-browser, or chromium"
    fi
    "${_chrome_bin}" \
      --remote-debugging-port=9222 \
      --password-store=basic \
      --user-data-dir="${HOME}/.config/acg-chrome-profile" &
  fi
```

```bash
# replacement — _browser_launch function body
  _info "Chrome not running — launching with --remote-debugging-port=9222..."
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/profile}"
  if [[ "$(uname)" == "Darwin" ]]; then
    open -a "Google Chrome" --args \
      --remote-debugging-port=9222 \
      --password-store=basic \
      --user-data-dir="${_cdp_profile_dir}"
  else
    local _chrome_bin
    _chrome_bin=$(command -v google-chrome 2>/dev/null || command -v google-chrome-stable 2>/dev/null || command -v chromium-browser 2>/dev/null || command -v chromium 2>/dev/null || true)
    if [[ -z "${_chrome_bin}" ]]; then
      _err "[antigravity] Chrome/Chromium not found — install google-chrome, google-chrome-stable, chromium-browser, or chromium"
    fi
    "${_chrome_bin}" \
      --headless=new \
      --no-sandbox \
      --disable-dev-shm-usage \
      --remote-debugging-port=9222 \
      --password-store=basic \
      --user-data-dir="${_cdp_profile_dir}" &
  fi
```

---

### 3. `scripts/playwright/acg_credentials.js` — update hardcoded default and doc comment

```js
// current
/**
 * scripts/playwright/acg_credentials.js
 *
 * Static Playwright script to extract AWS credentials from Pluralsight Cloud Sandbox.
 * Launches a persistent Chrome context — session persists across runs via auth dir.
 * Auth dir: ~/.local/share/k3d-manager/playwright-auth
 */

const AUTH_DIR = AUTH_DIR_OVERRIDE ||
  path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'playwright-auth');
```

```js
// replacement
/**
 * scripts/playwright/acg_credentials.js
 *
 * Static Playwright script to extract AWS credentials from Pluralsight Cloud Sandbox.
 * Launches a persistent Chrome context — session persists across runs via auth dir.
 * Auth dir: ~/.local/share/k3d-manager/profile
 */

const AUTH_DIR = AUTH_DIR_OVERRIDE ||
  path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'profile');
```

---

### 4. `scripts/playwright/acg_extend.js` — update hardcoded default and doc comment

```js
// current
/**
 * scripts/playwright/acg_extend.js
 *
 * Static Playwright script to extend the ACG sandbox TTL by 4 hours.
 * Launches a persistent Chrome context — session persists across runs via auth dir.
 * Auth dir: ~/.local/share/k3d-manager/playwright-auth
 *
 * Usage: node acg_extend.js <sandbox-url>
 */

const AUTH_DIR = path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'playwright-auth');
```

```js
// replacement
/**
 * scripts/playwright/acg_extend.js
 *
 * Static Playwright script to extend the ACG sandbox TTL by 4 hours.
 * Launches a persistent Chrome context — session persists across runs via auth dir.
 * Auth dir: ~/.local/share/k3d-manager/profile
 *
 * Usage: node acg_extend.js <sandbox-url>
 */

const AUTH_DIR = path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'profile');
```

---

### 5. `scripts/tests/plugins/gcp.bats` — update test fixture

```bash
# current
PLAYWRIGHT_AUTH_DIR="${HOME}/.local/share/k3d-manager/playwright-auth"
```

```bash
# replacement
PLAYWRIGHT_AUTH_DIR="${HOME}/.local/share/k3d-manager/profile"
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/playwright/vars.sh` | `playwright-auth` → `profile` |
| `scripts/plugins/antigravity.sh` | Add `--headless=new --no-sandbox --disable-dev-shm-usage`; use `PLAYWRIGHT_AUTH_DIR` |
| `scripts/playwright/acg_credentials.js` | Hardcoded default + doc comment: `playwright-auth` → `profile` |
| `scripts/playwright/acg_extend.js` | Hardcoded default + doc comment: `playwright-auth` → `profile` |
| `scripts/tests/plugins/gcp.bats` | Fixture: `playwright-auth` → `profile` |

---

## Rules

- Only the five files listed above may be touched
- `shellcheck scripts/plugins/antigravity.sh` must pass with zero new warnings
- `node --check scripts/playwright/acg_credentials.js && node --check scripts/playwright/acg_extend.js` must pass

---

## E2E Verification

### Test D1 — shellcheck
```bash
shellcheck scripts/plugins/antigravity.sh
```
Expected: exit 0, no new warnings.

### Test D2 — node syntax check
```bash
node --check scripts/playwright/acg_credentials.js && echo "credentials OK"
node --check scripts/playwright/acg_extend.js && echo "extend OK"
```
Expected: both print `OK`.

### Test D3 — grep confirm
```bash
grep -rn 'playwright-auth' scripts/
```
Expected: zero matches.

### Test D4 — live smoke test (run from ACG sandbox)
```bash
make up
```
Expected: Chrome CDP starts on port 9222; `make up` proceeds past the
"Chrome CDP not available" message without `Error 1`.

---

## Definition of Done

- [ ] All five files updated with exact content above
- [ ] Tests D1, D2, D3 pass — paste actual outputs
- [ ] Test D4 — paste log lines showing `make up` proceeds past Chrome CDP startup
- [ ] Committed and pushed to `k3d-manager-v1.1.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(antigravity): headless Linux CDP launch + unify profile path to profile/
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file not listed above
- Do NOT commit to `main`
- Do NOT change the macOS (`open -a "Google Chrome"`) launch flags — only the profile dir changes there
