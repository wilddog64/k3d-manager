# Bugfix: bin/acg-up aborts on expired sandbox instead of auto-restarting

**Branch:** `k3d-manager-v1.4.9`
**Files:** `bin/acg-up`

---

## Before You Start

1. `git pull origin k3d-manager-v1.4.9` in the k3d-manager repo
2. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`
3. Read `bin/acg-up` lines 127–141 to confirm the exact old block matches the spec

---

## Problem

When a sandbox has expired, `bin/acg-up` calls `_err` (exits non-zero) instead of
deleting the expired sandbox and starting a new one automatically.

**Root cause:** The fix in `5962c514` calls `_err` when TTL ≤ 0. The correct behaviour
is to invoke `acg_extend_playwright`, which triggers the existing Ghost State Recovery
path in `acg_extend.js` (Delete Sandbox → Confirm → Start Sandbox → click extend modal),
then re-extract credentials for the new sandbox.

The Ghost State Recovery fires because:
- `remainingMins` is negative (e.g. -228), which is `< 15` — the guard condition
- No extend button is visible for an expired sandbox — `!clicked` is true
- `acg_extend_playwright` already handles this; no changes to `acg_extend.js` needed

---

## Reproduction

```
sandbox Auto Shutdown: 2:02PM (expired ~4 hours ago)
make up
# expected: [acg-up] Sandbox has expired — deleting and starting a new one...
#           [acg-up] New sandbox started — re-extracting credentials...
# actual:   ERROR: [acg-up] Sandbox has expired (TTL: -228m). Delete it and create...
#           make: *** [up] Error 1
```

---

## Fix

### Change 1 — `bin/acg-up`: replace `_err` with `acg_extend_playwright` + re-extract

**Exact old block (lines 128–137):**

```bash
    else
      acg_get_credentials ${sandbox_url:+"$sandbox_url"} || exit 1
      _acg_sandbox_ref="${sandbox_url:-${_ACG_SANDBOX_URL:-}}"
      if [[ -n "${_acg_sandbox_ref}" ]]; then
        _acg_ttl_mins=$(acg_check_ttl "${_acg_sandbox_ref}" 2>/dev/null || true)
        if [[ -n "${_acg_ttl_mins}" ]] && (( _acg_ttl_mins <= 0 )); then
          _err "[acg-up] Sandbox has expired (TTL: ${_acg_ttl_mins}m). Delete it and create a new sandbox at ${_ACG_SANDBOX_URL}, then re-run make up."
        fi
      fi
      _info "[acg-up] Waiting for CloudFormation service to become accessible (up to 3 min)..."
```

**Exact new block:**

```bash
    else
      acg_get_credentials ${sandbox_url:+"$sandbox_url"} || exit 1
      _acg_sandbox_ref="${sandbox_url:-${_ACG_SANDBOX_URL:-}}"
      if [[ -n "${_acg_sandbox_ref}" ]]; then
        _acg_ttl_mins=$(acg_check_ttl "${_acg_sandbox_ref}" 2>/dev/null || true)
        if [[ -n "${_acg_ttl_mins}" ]] && (( _acg_ttl_mins <= 0 )); then
          _info "[acg-up] Sandbox has expired (TTL: ${_acg_ttl_mins}m) — deleting and starting a new one..."
          acg_extend_playwright "${_acg_sandbox_ref}" || \
            _err "[acg-up] Failed to restart expired sandbox — delete it manually and re-run make up."
          _info "[acg-up] New sandbox started — re-extracting credentials..."
          acg_get_credentials ${sandbox_url:+"$sandbox_url"} || exit 1
        fi
      fi
      _info "[acg-up] Waiting for CloudFormation service to become accessible (up to 3 min)..."
```

Notes:
- `acg_extend_playwright` invokes `acg_extend.js` which has Ghost State Recovery:
  TTL < 15 + no extend button → Delete Sandbox → Confirm → Start Sandbox → click extend modal
- If Ghost State recovery fails, `_err` exits with a clear manual-action message
- After recovery, `acg_get_credentials` re-extracts credentials for the new sandbox
  (it waits up to 420s for provisioning — no explicit sleep needed)
- No changes to `acg_extend.js` or `acg.sh` required

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Replace `_err` on expired TTL with `acg_extend_playwright` + re-extract |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- Code change limited to `bin/acg-up`; CHANGELOG and memory-bank updates are required documentation

---

## Definition of Done

- [ ] `shellcheck -S warning bin/acg-up` passes
- [ ] Committed to `k3d-manager-v1.4.9` and pushed to `origin/k3d-manager-v1.4.9`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(acg-up): auto-restart expired sandbox via Ghost State Recovery instead of aborting
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
- Do NOT add a `sleep` between `acg_extend_playwright` and `acg_get_credentials` — `acg_get_credentials` has its own 420s provisioning wait
