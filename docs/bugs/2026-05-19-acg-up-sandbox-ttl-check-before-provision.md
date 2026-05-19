# Bugfix: acg-up — check sandbox TTL before provisioning; extend if below threshold

**Branch:** `k3d-manager-v1.4.9`
**Files:** `bin/acg-up`

---

## Problem

When `make up` is run against a running ACG sandbox whose credentials are still valid,
`_acg_check_credentials` passes and provisioning starts immediately — even if the sandbox
is 20 minutes from auto-shutdown. The 30–45 minute provisioning run is then cut off mid-
way when the sandbox is destroyed.

**Root cause:** The skip-extraction path (lines 111–113 of `bin/acg-up`) does not check
the remaining sandbox TTL before proceeding to `deploy_cluster`.

---

## Reproduction

1. Start `make up` when ACG sandbox shows "Auto Shutdown at 2:02PM" and current time
   is 1:45PM (17 min remaining).
2. Credentials are valid → `_acg_check_credentials` passes → provisioning starts.
3. At 2:02PM the sandbox is destroyed → CloudFormation stack wiped → `make up` fails.

---

## Prerequisite

**This spec depends on lib-acg `fix/acg-sandbox-ttl-check` being merged to lib-acg main
and subtree-pulled into k3d-manager BEFORE implementing this spec.**

The lib-acg change adds `acg_check_ttl()` to `scripts/plugins/acg.sh` and `--check` to
`playwright/acg_extend.js`. The subtree pull brings that function into
`scripts/lib/acg/scripts/plugins/acg.sh` in k3d-manager so `bin/acg-up` can call it.

**Subtree pull command (run in k3d-manager repo, after lib-acg main is updated):**
```bash
git subtree pull --prefix=scripts/lib/acg \
  https://github.com/wilddog64/lib-acg.git main --squash
```

After the subtree pull, implement the change below.

---

## Fix

### Change 1 — `bin/acg-up`: check TTL in skip-extraction path; extend if below threshold

**Exact old block (lines 111–113):**
```bash
    if _acg_check_credentials 2>/dev/null; then
      _info "[acg-up] AWS credentials are valid — skipping Playwright extraction"
    else
```

**Exact new block:**
```bash
    if _acg_check_credentials 2>/dev/null; then
      _info "[acg-up] AWS credentials are valid — skipping Playwright extraction"
      _acg_sandbox_ref="${sandbox_url:-${_ACG_SANDBOX_URL:-}}"
      if [[ -n "${_acg_sandbox_ref}" ]]; then
        _acg_ttl_mins=$(acg_check_ttl "${_acg_sandbox_ref}" 2>/dev/null || true)
        _acg_min_mins="${ACG_MIN_REMAINING_MINUTES:-120}"
        if [[ -n "${_acg_ttl_mins}" ]] && [[ "${_acg_ttl_mins}" != "-1" ]] && \
            (( _acg_ttl_mins < _acg_min_mins )); then
          _info "[acg-up] Sandbox TTL: ${_acg_ttl_mins}m remaining (< ${_acg_min_mins}m threshold) — extending..."
          acg_extend_playwright "${_acg_sandbox_ref}" || \
            _warn "[acg-up] Sandbox extension failed — proceeding anyway"
        elif [[ -n "${_acg_ttl_mins}" ]] && [[ "${_acg_ttl_mins}" != "-1" ]]; then
          _info "[acg-up] Sandbox TTL: ${_acg_ttl_mins}m remaining — OK"
        else
          _warn "[acg-up] Could not read sandbox TTL — proceeding without TTL check"
        fi
      fi
    else
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Check sandbox TTL via `acg_check_ttl` after credentials validated; extend if < `ACG_MIN_REMAINING_MINUTES` (default: 120) |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- Code change limited to `bin/acg-up`; CHANGELOG and memory-bank updates are required documentation
- Do NOT implement until the lib-acg subtree pull is committed

---

## Definition of Done

- [ ] lib-acg subtree pull committed first (prerequisite)
- [ ] `bin/acg-up` calls `acg_check_ttl` in the skip-extraction path
- [ ] If TTL < `ACG_MIN_REMAINING_MINUTES` (default 120), calls `acg_extend_playwright`
- [ ] If TTL unreadable, logs a warning and continues
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.4.9`
- [ ] memory-bank updated with commit SHA

**Commit message (exact):**
```
fix(acg-up): check sandbox TTL before provisioning; extend if below threshold
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
- Do NOT implement the bin/acg-up change before the lib-acg subtree pull
