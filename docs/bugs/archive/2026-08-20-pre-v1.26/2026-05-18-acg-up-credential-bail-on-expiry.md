# Bug: acg-up bails immediately when AWS credentials are expired instead of attempting refresh

**Branch:** `k3d-manager-v1.4.7`
**File:** `bin/acg-up`

---

## Problem

`make up` with expired credentials exits hard after printing instructions to run
`acg_get_credentials` manually. If `acg_get_credentials` fails (no Playwright/Chrome),
there is no fallback — the user must re-run `make up` from scratch.

Expected: try Playwright extraction automatically; if that fails, pause so the user can
paste credentials manually, then verify before proceeding.

---

## Fix

**File:** `bin/acg-up` — Step 1 `k3s-aws` case

**Exact old block:**
```bash
  k3s-aws)
    if _acg_check_credentials 2>/dev/null; then
      _info "[acg-up] AWS credentials are valid — skipping Playwright extraction"
    else
      acg_get_credentials ${sandbox_url:+"$sandbox_url"} || exit 1
    fi
    ;;
```

**Exact new block:**
```bash
  k3s-aws)
    if _acg_check_credentials 2>/dev/null; then
      _info "[acg-up] AWS credentials are valid — skipping Playwright extraction"
    else
      _info "[acg-up] AWS credentials expired — attempting automatic extraction..."
      if ! acg_get_credentials ${sandbox_url:+"$sandbox_url"} 2>/dev/null; then
        _warn "[acg-up] Automatic extraction failed (Playwright/Chrome unavailable)"
        _info "[acg-up] Update ~/.aws/credentials from the Pluralsight sandbox console, then press Enter to continue (or Ctrl+C to abort)..."
        read -r
      fi
      if ! _acg_check_credentials 2>/dev/null; then
        _acg_fail "AWS credentials still invalid after refresh — run 'make creds URL=<sandbox-url>' to extract manually"
      fi
    fi
    ;;
```

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] Step 1 `k3s-aws` block updated as above
- [ ] `shellcheck -S warning bin/acg-up` passes
- [ ] Committed to `k3d-manager-v1.4.7`

**Commit message (exact):**
```
fix(acg-up): retry credential refresh instead of bailing on expiry
```
