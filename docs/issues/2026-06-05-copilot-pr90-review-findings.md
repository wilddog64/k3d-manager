# Copilot PR #90 Review Findings — 2026-06-05

**PR:** #90 — fix(acg-refresh/up): self-heal LaunchAgent plists + ACG observability fixes
**Branch:** `k3d-manager-v1.6.1`

---

## Finding 1 — `which kubectl` in install-vault-port-forward Makefile target

**File:** `Makefile:171`
**Copilot comment ID:** 3363065100

### What Copilot flagged

`which` is not guaranteed to exist or behave consistently across shells. If kubectl is
missing, it silently renders an invalid plist path with an empty string.

### Fix applied

**Before:**
```makefile
-e "s|{{KUBECTL_PATH}}|$$(which kubectl)|g" \
```

**After:**
```makefile
-e "s|{{KUBECTL_PATH}}|$$(command -v kubectl)|g" \
```

**Fix commit:** `90c1bbca`

### Root cause

`which` was used as a quick substitute during initial implementation. `command -v` is
the POSIX-compliant equivalent and is always available in bash/sh.

### Process note

Add to spec template: "Use `command -v` (not `which`) for binary path resolution in
Makefile targets and shell scripts."
