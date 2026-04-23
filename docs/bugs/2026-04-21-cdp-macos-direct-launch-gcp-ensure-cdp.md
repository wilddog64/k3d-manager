# Bug Fix: macOS CDP launch broken + GCP has no auto-launch

**Date:** 2026-04-21
**Branch:** `k3d-manager-v1.1.0`
**Files:** `scripts/plugins/antigravity.sh`, `scripts/plugins/gcp.sh`

## Problem

Two related bugs block GCP `make up` on macOS:

1. **`_browser_launch` macOS branch uses `open -a "Google Chrome"`.**
   If Chrome is already running without `--remote-debugging-port=9222`, macOS passes
   the `--args` flags to the existing process, which ignores them. CDP never becomes
   reachable. Fix: launch a new process via the direct binary, same pattern as the
   Linux branch.

2. **`gcp_get_credentials` hard-errors when CDP is not reachable.**
   It prints an error and returns 1 instead of auto-launching Chrome. Fix: add a
   self-contained `_gcp_ensure_cdp` function and call it before the CDP check.

AWS is unaffected by both changes:
- Change 1 is guarded by `curl -sf http://localhost:9222/json` at line 68 — if Chrome
  is already running with CDP (as AWS leaves it), `_browser_launch` returns early.
- Change 2 is GCP-only code.

**Do NOT change** `PLAYWRIGHT_AUTH_DIR`, `vars.sh`, or any profile directory path.
The `--user-data-dir` value (`${HOME}/.config/acg-chrome-profile`) must stay unchanged.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read this spec in full before touching any file.
3. Read `scripts/plugins/antigravity.sh` lines 64–89.
4. Read `scripts/plugins/gcp.sh` lines 38–82.
5. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.

**Branch:** `k3d-manager-v1.1.0` — commit directly here, do NOT create a new branch.

---

## Change 1 — `scripts/plugins/antigravity.sh`

Replace the macOS branch inside `_browser_launch` (lines 72–76).

### Old

```bash
  if [[ "$(uname)" == "Darwin" ]]; then
    open -a "Google Chrome" --args \
      --remote-debugging-port=9222 \
      --password-store=basic \
      --user-data-dir="${HOME}/.config/acg-chrome-profile"
  else
```

### New

```bash
  if [[ "$(uname)" == "Darwin" ]]; then
    local _chrome_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if [[ ! -x "${_chrome_bin}" ]]; then
      _err "[antigravity] Google Chrome not found at ${_chrome_bin} — install Google Chrome"
    fi
    "${_chrome_bin}" \
      --remote-debugging-port=9222 \
      --password-store=basic \
      --user-data-dir="${HOME}/.config/acg-chrome-profile" \
      --no-first-run \
      --no-default-browser-check >>/tmp/k3d-manager-chrome-cdp.err 2>&1 &
  else
```

**Nothing else in `antigravity.sh` changes.**

---

## Change 2 — `scripts/plugins/gcp.sh`

### 2a — Add `_gcp_ensure_cdp` before `gcp_get_credentials`

Insert the following block immediately before the `function gcp_get_credentials()` line
(i.e., before line 45, after line 44 which is blank).

```bash
function _gcp_ensure_cdp() {
  if curl -sf "http://${PLAYWRIGHT_CDP_HOST}:${PLAYWRIGHT_CDP_PORT}/json" >/dev/null 2>&1; then
    return 0
  fi
  _info "[gcp] Chrome CDP not reachable — launching Chrome..."
  local _chrome_bin
  if [[ "$(uname)" == "Darwin" ]]; then
    _chrome_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if [[ ! -x "${_chrome_bin}" ]]; then
      printf 'ERROR: %s\n' "[gcp] Google Chrome not found at ${_chrome_bin} — install Google Chrome" >&2
      return 1
    fi
  else
    _chrome_bin=$(command -v google-chrome 2>/dev/null \
      || command -v google-chrome-stable 2>/dev/null \
      || command -v chromium-browser 2>/dev/null \
      || command -v chromium 2>/dev/null \
      || true)
    if [[ -z "${_chrome_bin}" ]]; then
      printf 'ERROR: %s\n' "[gcp] Chrome/Chromium not found — install google-chrome or chromium" >&2
      return 1
    fi
  fi
  "${_chrome_bin}" \
    --remote-debugging-port=9222 \
    --password-store=basic \
    --user-data-dir="${HOME}/.config/acg-chrome-profile" \
    --no-first-run \
    --no-default-browser-check >>/tmp/k3d-manager-chrome-cdp.err 2>&1 &
  local _waited=0
  while ! curl -sf "http://${PLAYWRIGHT_CDP_HOST}:${PLAYWRIGHT_CDP_PORT}/json" >/dev/null 2>&1; do
    sleep 1
    (( _waited++ )) || true
    if (( _waited >= 30 )); then
      printf 'ERROR: %s\n' "[gcp] Chrome CDP did not become reachable after 30s" >&2
      return 1
    fi
  done
}

```

### 2b — Replace the hard-error CDP check in `gcp_get_credentials`

### Old

```bash
  if ! curl -sf "http://${PLAYWRIGHT_CDP_HOST}:${PLAYWRIGHT_CDP_PORT}/json" >/dev/null 2>&1; then
    printf 'ERROR: %s\n' "[gcp] Chrome CDP not reachable on ${PLAYWRIGHT_CDP_HOST}:${PLAYWRIGHT_CDP_PORT}." >&2
    printf 'ERROR: %s\n' "[gcp] Run: ./scripts/k3d-manager acg_chrome_cdp_install" >&2
    printf 'ERROR: %s\n' "[gcp] Then sign in to Pluralsight once in that Chrome window." >&2
    return 1
  fi
```

### New

```bash
  _gcp_ensure_cdp || return 1
```

**Nothing else in `gcp.sh` changes.**

---

## Rules

- `shellcheck -S warning scripts/plugins/antigravity.sh` — zero new warnings
- `shellcheck -S warning scripts/plugins/gcp.sh` — zero new warnings
- Do NOT run BATS — `_browser_launch` and `_gcp_ensure_cdp` require a real browser; no unit tests exist for them and none are required by this spec.
- Do NOT modify any file not listed above.

---

## Definition of Done

- [ ] `scripts/plugins/antigravity.sh` — macOS branch replaced with direct binary launch
- [ ] `scripts/plugins/gcp.sh` — `_gcp_ensure_cdp` added, hard-error block replaced with one-liner
- [ ] `shellcheck -S warning` passes on both files with zero new warnings
- [ ] Committed on `k3d-manager-v1.1.0` with message:
      `fix(antigravity,gcp): macOS direct Chrome binary launch + gcp auto-start CDP`
- [ ] Pushed to `origin k3d-manager-v1.1.0` — do NOT report done until push succeeds
- [ ] `memory-bank/activeContext.md` updated: mark this task COMPLETE with commit SHA
- [ ] `memory-bank/progress.md` updated: GCP CDP fix row marked COMPLETE with commit SHA
- [ ] Report back: commit SHA + paste the memory-bank lines you updated

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside `scripts/plugins/antigravity.sh` and `scripts/plugins/gcp.sh`
- Do NOT commit to `main`
- Do NOT change `PLAYWRIGHT_AUTH_DIR`, `vars.sh`, or any profile directory path
- Do NOT rename or move `--user-data-dir="${HOME}/.config/acg-chrome-profile"` — this value must be identical in both files
