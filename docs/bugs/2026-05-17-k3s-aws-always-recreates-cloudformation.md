# Bug: k3s-aws provider always recreates CloudFormation stack — should reuse when healthy

**Branch:** `k3d-manager-v1.4.6`
**Files:**
- `scripts/lib/providers/k3s-aws.sh` — line 52

---

## Before You Start

```
git pull origin k3d-manager-v1.4.6
```

Read this spec in full before touching any file.

---

## Problem

`scripts/lib/providers/k3s-aws.sh:52` hardcodes `--recreate` on every `acg_provision` call.
This tears down and rebuilds the entire 3-node CloudFormation stack every time `make up` runs,
even when the stack is healthy and reusable. A full rebuild takes several minutes unnecessarily.

The `--recreate` flag was added in `bc4485d8` to prevent `ROLLBACK_COMPLETE` stacks from
hanging. That intent is correct — but the fix is too broad. Only broken stacks need recreate.

**Healthy states** (reuse — no `--recreate`):
- `CREATE_COMPLETE`
- `UPDATE_COMPLETE`
- `UPDATE_ROLLBACK_COMPLETE`

**Broken states** (recreate required):
- `ROLLBACK_COMPLETE`
- `CREATE_FAILED`
- `ROLLBACK_FAILED`
- `UPDATE_ROLLBACK_FAILED`
- `DELETE_FAILED`
- _(missing / no stack)_ → no recreate needed; `aws cloudformation deploy` creates it

---

## Fix

### Change 1 — `scripts/lib/providers/k3s-aws.sh`: check stack status before provisioning

**Exact old block (line 51–52):**
```bash
  _info "[k3s-aws] Provisioning CloudFormation stack (server + agents)..."
  acg_provision --confirm --recreate || return 1
```

**Exact new block:**
```bash
  _info "[k3s-aws] Provisioning CloudFormation stack (server + agents)..."
  _cf_stack_status=$(_run_command --soft -- aws cloudformation describe-stacks \
    --region "${ACG_REGION}" --stack-name "${_ACG_CF_STACK_NAME}" \
    --query 'Stacks[0].StackStatus' --output text 2>/dev/null || true)
  case "${_cf_stack_status}" in
    CREATE_COMPLETE|UPDATE_COMPLETE|UPDATE_ROLLBACK_COMPLETE)
      _info "[k3s-aws] CloudFormation stack is healthy (${_cf_stack_status}) — reusing without recreate"
      acg_provision --confirm || return 1
      ;;
    ROLLBACK_COMPLETE|CREATE_FAILED|ROLLBACK_FAILED|UPDATE_ROLLBACK_FAILED|DELETE_FAILED)
      _info "[k3s-aws] CloudFormation stack is in broken state (${_cf_stack_status}) — recreating"
      acg_provision --confirm --recreate || return 1
      ;;
    *)
      _info "[k3s-aws] CloudFormation stack not found or unknown state (${_cf_stack_status:-none}) — creating"
      acg_provision --confirm || return 1
      ;;
  esac
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-aws.sh` | Replace hardcoded `--recreate` with status-aware logic |

---

## Rules

- `shellcheck -S warning scripts/lib/providers/k3s-aws.sh` — zero new warnings
- No other files modified
- `_ACG_CF_STACK_NAME` and `ACG_REGION` are already in scope when `deploy_cluster` runs —
  they are set at the top of `acg.sh` which is sourced before this provider

---

## Definition of Done

- [ ] Lines 51–52 replaced with status-aware block (exact new block above)
- [ ] `shellcheck -S warning scripts/lib/providers/k3s-aws.sh` passes with zero new warnings
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat`

**Commit message (exact):**
```
fix(k3s-aws): only recreate CloudFormation stack when broken, reuse when healthy
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/providers/k3s-aws.sh`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT remove `--recreate` from broken state cases — those states genuinely require it
