# Issue: _agent_audit awk user-defined function fails on macOS BSD awk

**Date:** 2026-03-07
**File:** `scripts/lib/agent_rigor.sh` — `_agent_audit` function, lines 112–132
**Symptom:** Pre-commit hook prints awk syntax error on every commit on macOS
**Assigned to:** Codex

---

## Symptom

Every commit on macOS M-series triggers this error from the pre-commit hook:

```
awk: syntax error at source line 2 in function emit
 context is
            function >>> emit(func <<< ,count){
        2 missing )'s
awk: bailing out at source line 2 in function emit
```

The commit still succeeds — the hook does not block — but the error is noisy and
masks real audit warnings.

---

## Root Cause

macOS ships **BSD one-true-awk** (version 20200816). This awk implementation does not
support multi-parameter user-defined functions in multi-line heredoc format when the
`function` keyword is indented with leading whitespace.

The failing awk in `_agent_audit` (lines 112–132):

```awk
offenders=$(awk -v max_if="$max_if" '
   function emit(func,count){          ← indented, 2 params → BSD awk fails here
     if(func != "" && count > max_if){ ... }
   }
   ...
' "$file")
```

**Confirmed behaviors on macOS awk 20200816:**
- `function f(x){return x}` — single param, inline → **works** ✅
- `function emit(func,count){...}` — two params, any formatting → **fails** ❌

**gawk** (GNU Awk 5.4.0, available at `/opt/homebrew/bin/gawk`) supports
this syntax correctly but is not the system default `awk`.

---

## Fix Options

**Option A (preferred) — rewrite without user-defined function (POSIX portable):**

Inline the `emit()` logic directly. Works on BSD awk, mawk, gawk, and every POSIX awk.
No dependency on gawk, no Homebrew requirement, no detection logic needed.

```bash
offenders=$(awk -v max_if="$max_if" '
   /^[ \t]*function[ \t]+/ {
     if (current_func != "" && if_count > max_if) {
       printf "%s:%d\n", current_func, if_count
     }
     line = $0
     gsub(/^[ \t]*function[ \t]+/, "", line)
     current_func = line
     gsub(/\(.*/, "", current_func)
     if_count = 0
     next
   }
   /^[[:space:]]*if[[:space:](]/ { if_count++ }
   END {
     if (current_func != "" && if_count > max_if) {
       printf "%s:%d\n", current_func, if_count
     }
   }
' "$file")
```

Works on:
- macOS BSD awk (no Homebrew) ✅
- macOS with Homebrew gawk ✅
- Linux mawk / GNU awk ✅
- Any POSIX awk ✅

**Option B — gawk detection with fallback:**

```bash
local awk_cmd
awk_cmd="$(command -v gawk || command -v awk)"
offenders=$("$awk_cmd" -v max_if="$max_if" '...' "$file")
```

Only helps if `gawk` is installed. macOS without Homebrew still fails.
**Not recommended** — partial fix, hides the real portability gap.

**Option C — extract to `.awk` file:**
Adds a file dependency. Not recommended for a single-use internal script.

**Recommendation: Option A** — truly portable, no dependencies, minimal code change.

---

## Verification

```bash
# Before fix — should print awk error
echo "dummy" | awk -v max_if="8" '
   function emit(func,count){
     if(func != "" && count > max_if){printf "%s:%d\n", func, count}
   }
   END { emit("test", 10) }
' /dev/null

# After fix — should print no awk error, and cyclomatic check still works
# Stage a .sh file with >8 if blocks and confirm audit flags it
```

Also run the full BATS suite after the fix:
```bash
env -i HOME="$HOME" PATH="$PATH" ./scripts/k3d-manager test agent_rigor 2>&1 | tail -10
```

---

## Scope

- Edit only `scripts/lib/agent_rigor.sh` lines 112–132 (the awk block inside `_agent_audit`)
- Replace the entire awk heredoc with the Option A rewrite — no other changes
- Run `shellcheck scripts/lib/agent_rigor.sh` and confirm PASS
- Verify pre-commit hook no longer prints awk error on a test commit
- Verify the if-count check still flags functions with > 8 if blocks
