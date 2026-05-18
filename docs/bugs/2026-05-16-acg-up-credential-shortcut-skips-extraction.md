# Bug: acg-up — aws sts shortcut skips credential extraction — proceeds to CloudFormation with stale credentials

**Branch:** `k3d-manager-v1.4.6`
**Files:** `bin/acg-up`

---

## Problem

Step 1 of `bin/acg-up` checks `aws sts get-caller-identity` before calling `acg_get_credentials`.
If old credentials from a previous sandbox session are still valid per AWS STS (session token
not yet expired), the check passes and `acg_get_credentials` is skipped entirely — the
Playwright script never runs, "Start Sandbox" is never clicked, and the sandbox stays
unstarted with empty credential fields.

Step 2 then calls `acg_provision --confirm --recreate`, which calls `_acg_check_credentials`
with the stale credentials. If STS still accepts them, CloudFormation runs under the wrong
account and fails with exit 255.

**Root cause:** The shortcut at line 111 (`if aws sts get-caller-identity ...`) treats
stale-but-technically-valid credentials as sufficient for a fresh `make up` run. ACG
sandboxes are per-session; `make up` must always extract fresh credentials and start the
sandbox — there is no safe shortcut.

---

## Reproduction

1. Run `make up` once — credentials written to `~/.aws/credentials`
2. Sandbox expires or is reset (new session)
3. Run `make up` again
4. Step 1: `aws sts get-caller-identity` passes with old session token
5. `acg_get_credentials` is skipped — Start Sandbox never clicked
6. Step 2: CloudFormation runs with stale credentials — fails 255

---

## Fix

### Change 1 — `bin/acg-up` lines 110–115: remove shortcut, always extract, fail hard

**Exact old block:**
```bash
  k3s-aws)
    if aws sts get-caller-identity >/dev/null 2>&1; then
      _info "[acg-up] Existing AWS credentials valid — skipping extraction"
    else
      acg_get_credentials ${sandbox_url:+"$sandbox_url"}
    fi
    ;;
```

**Exact new block:**
```bash
  k3s-aws)
    acg_get_credentials ${sandbox_url:+"$sandbox_url"} || return 1
    ;;
```

**Why:** `acg_credentials.js` already handles the "already running, credentials already
populated" case gracefully (lines 401–406 — it checks `input[aria-label="Copyable input"]`
value and skips the Start/Open flow if credentials are present). Removing the shortcut
is safe — the Playwright script is idempotent. Adding `|| return 1` ensures `bin/acg-up`
fails fast if extraction fails instead of proceeding to CloudFormation with invalid creds.

---

## Files Changed

| File | Changes |
|------|---------|
| `bin/acg-up` | Change 1 — replace 5-line shortcut block with single `acg_get_credentials || return 1` line |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files touched
- The change is exactly the `k3s-aws)` case block — nothing else changes

---

## Definition of Done

- [ ] `bin/acg-up` lines 110–115 changed to `acg_get_credentials ${sandbox_url:+"$sandbox_url"} || return 1`
- [ ] The `k3s-gcp)` case block unchanged
- [ ] `shellcheck -S warning bin/acg-up` passes
- [ ] No other files modified
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg-up): always extract credentials — remove aws sts shortcut that skipped Start Sandbox
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change the `k3s-gcp)` case block
- Do NOT add back any `aws sts get-caller-identity` check — the shortcut is the bug
- Do NOT change anything above line 108 or below line 120
