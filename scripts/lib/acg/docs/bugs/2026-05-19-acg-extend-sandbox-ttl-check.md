# Bugfix: lib-acg — expose sandbox TTL check via `--check` flag

**Branch:** `fix/acg-sandbox-ttl-check`
**Files:** `playwright/acg_extend.js`, `scripts/plugins/acg.sh`

---

## Problem

`acg_extend.js` already parses the ACG sandbox auto-shutdown timestamp but does not
expose it to callers — it only decides internally whether to skip or proceed with
extension. There is no way for `bin/acg-up` to read the remaining TTL and proactively
extend before starting a long provisioning run.

**Root cause:** No `--check` flag exists on `acg_extend.js`, and no `acg_check_ttl`
shell function wraps it.

---

## Reproduction

```bash
# No way to get remaining TTL — this does not exist yet:
node playwright/acg_extend.js "$ACG_SANDBOX_URL" --check
# Expected: REMAINING_MINS:87
# Actual: command works but prints nothing useful and may start extending
```

---

## Fix

### Change 1 — `playwright/acg_extend.js`: emit `REMAINING_MINS:<n>` and exit when `--check` passed

Insert a check-only early exit immediately after the TTL is calculated, and add a
fallback for the case where the shutdown text is not visible.

**Exact old block (lines 211–223):**
```javascript
          console.error(`INFO: Calculated remaining TTL: ~${remainingMins} minutes`);
          
          if (remainingMins > 65) {
            console.log(`INFO: Extension window not open yet (${remainingMins}m remaining). Skipping extension.`);
            process.exit(0);
          } else {
            console.error(`INFO: Within 1h extension window (${remainingMins}m remaining). Proceeding to extend...`);
          }
        }
      }
    } else {
      console.error(`WARN: Auto Shutdown text not found. Proceeding anyway.`);
    }
```

**Exact new block:**
```javascript
          console.error(`INFO: Calculated remaining TTL: ~${remainingMins} minutes`);

          if (process.argv[3] === '--check') {
            console.log(`REMAINING_MINS:${remainingMins}`);
            process.exit(0);
          }
          if (remainingMins > 65) {
            console.log(`INFO: Extension window not open yet (${remainingMins}m remaining). Skipping extension.`);
            process.exit(0);
          } else {
            console.error(`INFO: Within 1h extension window (${remainingMins}m remaining). Proceeding to extend...`);
          }
        }
      }
    } else {
      console.error(`WARN: Auto Shutdown text not found. Proceeding anyway.`);
    }
    if (process.argv[3] === '--check') {
      console.log(`REMAINING_MINS:${remainingMins !== null ? remainingMins : -1}`);
      process.exit(0);
    }
```

### Change 2 — `scripts/plugins/acg.sh`: add `acg_check_ttl()` function

Insert after `_acg_extend_playwright()` (after line 429, before `function acg_extend_playwright`):

**Exact old block (line 431):**
```bash
function acg_extend_playwright() {
```

**Exact new block:**
```bash
function acg_check_ttl() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: acg_check_ttl <sandbox_url>

Read the ACG sandbox auto-shutdown timestamp via Playwright and print the
remaining minutes to stdout. Prints REMAINING_MINS:<n>; -1 if unparseable.
HELP
    return 0
  fi
  local sandbox_url="${1:?usage: acg_check_ttl <sandbox_url>}"
  local playwright_script="${_LIB_ACG_ROOT}/playwright/acg_extend.js"
  if ! command -v node >/dev/null 2>&1; then
    _err "[acg] node is required — install Node.js"
  fi
  local output exit_code
  output=$(node "$playwright_script" "$sandbox_url" --check 2>/dev/null)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    _warn "[acg] acg_check_ttl: node exited $exit_code"
    return 1
  fi
  printf '%s\n' "$output" | grep '^REMAINING_MINS:' | cut -d: -f2
}

function acg_extend_playwright() {
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_extend.js` | Add `--check` flag: print `REMAINING_MINS:<n>` and exit 0 without extending |
| `scripts/plugins/acg.sh` | Add `acg_check_ttl()` public function |

---

## Rules

- `node --check playwright/acg_extend.js` — zero syntax errors
- `shellcheck -S warning scripts/plugins/acg.sh` — zero new warnings
- Code change limited to `playwright/acg_extend.js` and `scripts/plugins/acg.sh`; CHANGELOG and memory-bank updates are required documentation

---

## Definition of Done

- [ ] `node playwright/acg_extend.js <url> --check` prints `REMAINING_MINS:<n>` to stdout and exits 0
- [ ] `acg_check_ttl <url>` prints the integer minute count to stdout
- [ ] `node --check playwright/acg_extend.js` passes
- [ ] `shellcheck -S warning scripts/plugins/acg.sh` passes with zero new warnings
- [ ] Committed and pushed to `fix/acg-sandbox-ttl-check`
- [ ] memory-bank updated with commit SHA

**Commit message (exact):**
```
feat(acg): expose sandbox TTL via --check flag on acg_extend.js; add acg_check_ttl()
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the listed targets
- Do NOT commit to `main` — work on `fix/acg-sandbox-ttl-check`
