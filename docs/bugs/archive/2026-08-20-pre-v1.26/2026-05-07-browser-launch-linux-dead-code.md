# Bugfix: v0.1.0 — _browser_launch dead Linux else-block

**Branch:** `fix/post-merge-pr9-cleanup`
**Files:** `scripts/lib/cdp.sh`

---

## Before You Start

```bash
# 1. Confirm you are in the correct repo and on the correct branch
cd ~/src/gitrepo/personal/lib-acg
git pull origin fix/post-merge-pr9-cleanup
git branch --show-current   # must print: fix/post-merge-pr9-cleanup

# 2. Read memory-bank
cat memory-bank/activeContext.md
cat memory-bank/progress.md

# 3. Read the target file
cat -n scripts/lib/cdp.sh
```

---

## Problem

`_browser_launch` contains a Linux/non-Darwin `else` block (lines 91–108) that can never
execute: the entire `cdp.sh` library is macOS-only (launchd, `launchctl bootout`,
`_cdp_stop_chrome_cdp_agent` returns 0 on non-Darwin). The dead block silently does nothing
on Linux instead of failing with a clear error.

**Root cause:** A Linux code path added during initial development was never removed when the
library became macOS-only, leaving ~18 lines of unreachable code behind the outer
`if [[ "$(uname)" == "Darwin" ]]` check.

---

## Reproduction

```bash
# The dead block is visible in the source — no runtime test needed.
# On a Linux host (or CI) calling _browser_launch would silently skip the Darwin branch,
# enter the else, try to find google-chrome, and either error on a missing binary or launch
# a headless Chrome with no launchd lifecycle — an unsupported configuration.
grep -n 'else' scripts/lib/cdp.sh   # lines 85 and 91 — the outer else at 91 is dead
```

---

## Fix

### Change 1 — `scripts/lib/cdp.sh` lines 91–108: replace dead Linux else-block with `_err`

**Exact old block (lines 91–109):**

```bash
  else
    local _chrome_bin
    _chrome_bin=$(command -v google-chrome 2>/dev/null || command -v google-chrome-stable 2>/dev/null || command -v chromium-browser 2>/dev/null || command -v chromium 2>/dev/null || true)
    if [[ -z "${_chrome_bin}" ]]; then
      _err "[gemini] Chrome/Chromium not found — install google-chrome, google-chrome-stable, chromium-browser, or chromium"
    fi
    local _extra_flags=()
    if [[ $EUID -eq 0 || "${ANTIGRAVITY_CHROME_NO_SANDBOX:-0}" == "1" ]]; then
      _extra_flags+=(--no-sandbox)
    fi
    "${_chrome_bin}" \
      --headless=new \
      "${_extra_flags[@]}" \
      --disable-dev-shm-usage \
      --remote-debugging-port=9222 \
      --password-store=basic \
      --user-data-dir="${_cdp_profile_dir}" &
  fi
```

**Exact new block:**

```bash
  else
    _err "[acg] _browser_launch is macOS-only — $(uname) is not supported"
  fi
```

No other lines in the function change.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/cdp.sh` | Replace 17-line dead Linux else-block with single `_err` call |

---

## Rules

- `shellcheck -S warning scripts/lib/cdp.sh` — zero new warnings
- Only `scripts/lib/cdp.sh` modified — memory-bank updates are the only other permitted changes

---

## Definition of Done

- [ ] Dead Linux else-block (lines 91–108) replaced with `_err` one-liner
- [ ] `shellcheck -S warning scripts/lib/cdp.sh` passes with zero new warnings
- [ ] Code diff touches only `scripts/lib/cdp.sh` (memory-bank updates expected)
- [ ] Committed and pushed to `fix/post-merge-pr9-cleanup`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(cdp): remove dead Linux else-block from _browser_launch
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/cdp.sh`
- Do NOT commit to `main` — work on `fix/post-merge-pr9-cleanup`
- Do NOT refactor the inner Darwin if/else — only the outer else-block changes
