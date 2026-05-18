# Bug: k3s-aws — CloudFormation deploy hangs when stack is in terminal failure state

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/providers/k3s-aws.sh`

---

## Problem

`make up` fails at Step 2 (CloudFormation provisioning) with exit code 255:

```
Waiting for changeset to be created..
Waiting for stack create/update to complete
Failed to create/update the stack.
aws command failed (255): aws cloudformation deploy ...
ERROR: failed to execute aws cloudformation deploy ...: 255
```

This happens when the `k3d-manager-cluster` stack is in a terminal failure state
(`CREATE_FAILED`, `ROLLBACK_COMPLETE`, or `UPDATE_ROLLBACK_COMPLETE`) from a prior
`make up` run that did not complete. `aws cloudformation deploy` cannot update a stack
in those states and exits 255.

**Root cause:** `_provider_k3s_aws_deploy_cluster` calls `acg_provision --confirm`
without `--recreate`. The `--recreate` flag deletes any existing stack before creating
a fresh one; without it, the deploy fails when a bad stack is present.

---

## Reproduction

1. Run `make up` — it partially deploys CloudFormation and fails (any reason)
2. Stack is left in `CREATE_FAILED` or `ROLLBACK_COMPLETE`
3. Run `make up` again
4. Step 2 prints "Failed to create/update the stack" and exits 255

---

## Fix

### Change 1 — `scripts/lib/providers/k3s-aws.sh` line 52: add `--recreate`

**Exact old block:**

```bash
  _info "[k3s-aws] Provisioning CloudFormation stack (server + agents)..."
  acg_provision --confirm || return 1
```

**Exact new block:**

```bash
  _info "[k3s-aws] Provisioning CloudFormation stack (server + agents)..."
  acg_provision --confirm --recreate || return 1
```

**Why:** `make up` is documented as "use when starting from scratch". Always using
`--recreate` ensures the stack is clean regardless of previous state. The `--recreate`
path in `acg_provision` deletes the existing stack (no-op if it doesn't exist) then
creates fresh — safe for a "start from scratch" command.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-aws.sh` | Add `--recreate` to `acg_provision --confirm` call |

---

## Rules

- `shellcheck -S warning scripts/lib/providers/k3s-aws.sh` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] `acg_provision --confirm --recreate` on line 52 of `scripts/lib/providers/k3s-aws.sh`
- [ ] No other lines changed
- [ ] `shellcheck -S warning scripts/lib/providers/k3s-aws.sh` passes
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] Pushed: `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(k3s-aws): always recreate CloudFormation stack on deploy — prevents ROLLBACK_COMPLETE hang
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/providers/k3s-aws.sh`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change the `--confirm` flag
- Do NOT modify `acg_provision` in `acg.sh` — only change the call site in `k3s-aws.sh`
