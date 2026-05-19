# Bugfix: bin/acg-up hangs 3 min on expired sandbox instead of failing fast

**Branch:** `k3d-manager-v1.4.9`
**Files:** `bin/acg-up`

**Prerequisite:** lib-acg `fix/acg-extend-midnight-wrap` merged and subtree pulled into
`scripts/lib/acg/` before this spec is implemented. The midnight-wrap fix makes
`acg_check_ttl` return a negative/zero value for expired sandboxes; without it this
spec's check is ineffective.

---

## Problem

When a sandbox has expired, `bin/acg-up` spends 3 minutes waiting for CloudFormation
to become accessible before failing, with no indication that the sandbox itself is gone.

**Root cause:** The TTL check added in `a89cc2e5` only runs in the skip-extraction path
(`if _acg_check_credentials`). When credentials are stale (the `else` branch),
`acg_get_credentials` extracts credentials from the still-visible ACG page, but the
underlying AWS account is already deprovisioned. `bin/acg-up` then waits 3 minutes on
CloudFormation and fails without explaining why.

---

## Reproduction

```
sandbox Auto Shutdown: 2:02PM (expired 2 hours ago)
make up
# expected: immediate clear error "Sandbox has expired — delete and create a new one"
# actual:   [acg-up] Waiting for CloudFormation service to become accessible (up to 3 min)
#           [acg-up] ... CloudFormation not yet accessible (attempt N/12) — sleeping 15s  × 12
```

---

## Fix

### Change 1 — `bin/acg-up`: add TTL check in the credential-extraction `else` branch

Insert immediately after `acg_get_credentials` succeeds (line 129), before the
CloudFormation wait block.

**Exact old block (lines 128–131):**

```bash
    else
      acg_get_credentials ${sandbox_url:+"$sandbox_url"} || exit 1
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
          _err "[acg-up] Sandbox has expired (TTL: ${_acg_ttl_mins}m). Delete it and create a new sandbox at ${_ACG_SANDBOX_URL}, then re-run make up."
        fi
      fi
      _info "[acg-up] Waiting for CloudFormation service to become accessible (up to 3 min)..."
```

Notes:
- `_err` exits with a non-zero code — no further steps run
- If `acg_check_ttl` fails (returns empty), the check is skipped and the existing
  CloudFormation wait runs as before (safe fallback)
- Any value ≤ 0 means expired (negative after midnight-wrap fix, -1 for parse failure)

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Add TTL expiry check in the credential-extraction else branch |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] `shellcheck -S warning bin/acg-up` passes
- [ ] Committed to `k3d-manager-v1.4.9` and pushed to `origin/k3d-manager-v1.4.9`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(acg-up): detect expired sandbox after credential extraction; fail fast with clear message
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
- Do NOT run the subtree pull — it is already done (`036167f4`)
