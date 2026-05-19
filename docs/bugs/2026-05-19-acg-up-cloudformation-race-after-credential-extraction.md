# Bugfix: acg-up — CloudFormation race after fresh credential extraction

**Branch:** `k3d-manager-v1.4.9`
**Files:** `bin/acg-up`

---

## Problem

`make up` fails at the CloudFormation deploy step (`aws cloudformation deploy` exits 255)
immediately after a fresh ACG sandbox start.

**Root cause:** ACG provisions IAM credentials before the AWS CloudFormation service is
fully initialized in the new sandbox account. `aws sts get-caller-identity` succeeds
immediately (STS is available first), so `_acg_check_credentials` passes and
`acg_provision` proceeds — but `aws cloudformation deploy` fails because CloudFormation
is not yet accessible in the new account.

The window is typically 30–180 seconds after credential extraction.

---

## Reproduction

1. Start a fresh ACG AWS sandbox (click "Start Sandbox" — credentials are empty at first).
2. Run `make up` immediately after credentials appear.
3. Observe: Step 1 (credential extraction) succeeds; Step 2 (`aws cloudformation deploy`)
   fails with exit 255.

---

## Fix

### Change 1 — `bin/acg-up`: wait for CloudFormation after fresh extraction

After `acg_get_credentials` succeeds (fresh extraction only — not when cached creds are
reused), poll `aws cloudformation list-stacks` until the service responds, before
proceeding to `deploy_cluster`.

**Exact old block (lines 110–115):**
```bash
  k3s-aws)
    if _acg_check_credentials 2>/dev/null; then
      _info "[acg-up] AWS credentials are valid — skipping Playwright extraction"
    else
      acg_get_credentials ${sandbox_url:+"$sandbox_url"} || exit 1
    fi
```

**Exact new block:**
```bash
  k3s-aws)
    if _acg_check_credentials 2>/dev/null; then
      _info "[acg-up] AWS credentials are valid — skipping Playwright extraction"
    else
      acg_get_credentials ${sandbox_url:+"$sandbox_url"} || exit 1
      _info "[acg-up] Waiting for CloudFormation service to become accessible (up to 3 min)..."
      _cf_wait=0
      until _run_command --soft --quiet -- aws cloudformation list-stacks \
          --region "${ACG_REGION:-us-west-2}" >/dev/null 2>&1; do
        _cf_wait=$(( _cf_wait + 1 ))
        if (( _cf_wait > 12 )); then
          printf 'ERROR: %s\n' \
            "[acg-up] CloudFormation not accessible after $(( 12 * 15 ))s — check credentials" >&2
          exit 1
        fi
        _info "[acg-up] ... CloudFormation not yet accessible (attempt ${_cf_wait}/12) — sleeping 15s"
        sleep 15
      done
      _info "[acg-up] CloudFormation accessible."
    fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Poll `aws cloudformation list-stacks` after fresh credential extraction |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- Code change limited to `bin/acg-up`; CHANGELOG and memory-bank updates are required documentation

---

## Definition of Done

- [ ] `bin/acg-up` polls CloudFormation after `acg_get_credentials` succeeds
- [ ] `shellcheck -S warning bin/acg-up` passes
- [ ] Committed and pushed to `k3d-manager-v1.4.9`
- [ ] memory-bank updated with commit SHA

**Commit message (exact):**
```
fix(acg-up): wait for CloudFormation service after fresh credential extraction
```
