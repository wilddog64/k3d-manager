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

**Option A (preferred) — local gawk detection with transparent fallback:**

Detect `gawk` (available via Homebrew on macOS, default on most Linux) and use it
transparently. The awk script stays unchanged — only the interpreter selection changes.
Add a local `awk_cmd` variable inside `_agent_audit` before the awk call (line 112):

```bash
local awk_cmd
awk_cmd="$(command -v gawk || command -v awk)"
offenders=$("$awk_cmd" -v max_if="$max_if" '
   function emit(func,count){
     if(func != "" && count > max_if){printf "%s:%d\n", func, count}
   }
   ...
' "$file")
```

- macOS + Homebrew: uses `/opt/homebrew/bin/gawk` → works ✅
- Linux (Ubuntu): uses system `gawk` or `awk` (GNU awk) → works ✅
- macOS without Homebrew: falls back to BSD awk → same problem, but this is
  an unsupported config (Homebrew required for k3d, bats, etc.)

**Option B — rewrite without user-defined function:**
Replace the `emit()` function with inline awk logic. The function only prints
when count exceeds threshold — this is expressible without a named function:

```awk
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

**Option C — use `awk` file instead of heredoc:**
Extract the awk script to `scripts/lib/agent_audit_ifcount.awk` and call
`awk -v max_if="$max_if" -f scripts/lib/agent_audit_ifcount.awk "$file"`.
This avoids the heredoc indentation issue but adds a file dependency.

**Recommendation: Option A** — transparent gawk detection, minimal change, awk script unchanged.

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
- Add `local awk_cmd` + `awk_cmd="$(command -v gawk || command -v awk)"` before the awk call
- Replace `awk` with `"$awk_cmd"` on the awk invocation line — no other changes
- Run `shellcheck scripts/lib/agent_rigor.sh` and confirm PASS
- Verify pre-commit hook no longer prints awk error on a test commit
