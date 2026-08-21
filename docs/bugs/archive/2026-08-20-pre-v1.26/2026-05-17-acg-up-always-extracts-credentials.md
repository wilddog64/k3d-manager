# Bug: acg-up always re-extracts AWS credentials — should skip when valid

**Branch:** `k3d-manager-v1.4.6`
**Files:**
- `bin/acg-up` — Step 1/12 block

---

## Before You Start

```
git pull origin k3d-manager-v1.4.6
```

Read this spec in full before touching any file.

---

## Problem

`bin/acg-up` Step 1 unconditionally calls `acg_get_credentials` on every run. This
launches Chrome via CDP and runs a Playwright script to extract credentials from the
Pluralsight sandbox page — even when `~/.aws/credentials` already contains valid,
unexpired credentials for the current sandbox session.

`_acg_check_credentials` already exists in `scripts/lib/acg/scripts/plugins/acg.sh`
and validates credentials via `aws sts get-caller-identity`. It is used inside
`acg_provision` and `acg_status` but is never called as a pre-check in `bin/acg-up`.

**Root cause:** `bin/acg-up` has no guard — it always extracts regardless of whether
current credentials are still valid.

---

## Fix

### Change 1 — `bin/acg-up`: skip credential extraction when credentials are already valid

**Exact old block (Step 1, lines ~108–116):**
```bash
_info "[acg-up] Step 1/12 — Getting ${_cluster_provider} credentials..."
case "${_cluster_provider}" in
  k3s-aws)
    acg_get_credentials ${sandbox_url:+"$sandbox_url"} || exit 1
    ;;
  k3s-gcp)
    gcp_get_credentials ${sandbox_url:+"$sandbox_url"}
    ;;
esac
```

**Exact new block:**
```bash
_info "[acg-up] Step 1/12 — Getting ${_cluster_provider} credentials..."
case "${_cluster_provider}" in
  k3s-aws)
    if _acg_check_credentials 2>/dev/null; then
      _info "[acg-up] AWS credentials are valid — skipping Playwright extraction"
    else
      acg_get_credentials ${sandbox_url:+"$sandbox_url"} || exit 1
    fi
    ;;
  k3s-gcp)
    gcp_get_credentials ${sandbox_url:+"$sandbox_url"}
    ;;
esac
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Step 1: gate `acg_get_credentials` behind `_acg_check_credentials` |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files modified
- `_acg_check_credentials` stderr is suppressed (`2>/dev/null`) — its error messages
  are not useful in this context; `acg_get_credentials` will produce its own diagnostics
  on failure

---

## Definition of Done

- [ ] `_acg_check_credentials` guard added in Step 1 `k3s-aws` case (exact new block above)
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat`

**Commit message (exact):**
```
fix(acg-up): skip credential extraction when existing AWS credentials are valid
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT modify `scripts/lib/acg/` — this fix is in `bin/acg-up` only
