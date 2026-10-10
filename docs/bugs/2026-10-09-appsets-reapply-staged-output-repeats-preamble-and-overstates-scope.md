# Bug: staged `appsets-reapply` output repeats the preamble per stage and says "All Applications" for one stage

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.43.0`
**Status:** OPEN — spec ready for Codex
**Priority:** P3 — cosmetic; the rollout and both confirmations are correct
**Severity:** low
**Origin:** operator's first staged `make appsets-reapply` after `b90a15f1`, 2026-10-09.

## Symptom

The run was correct: hub 5/5 applied, 9 references confirmed, then app-cluster 8/8 applied, 12
references confirmed. The output is misleading in two places:

1. Each stage repeats the whole preamble, so the app-cluster stage reads like the run started over:
   ```
   INFO: [argocd] Deploying sample ApplicationSets
   INFO: [argocd] app-cluster role label set on 'ubuntu-hostinger' (additive: other app-clusters keep their role)
   INFO: [argocd] Found 13 ApplicationSet file(s)
   ```
   The role label is also written twice. That is harmless because the write is idempotent, but it
   is wasted work.
2. Each stage's confirmation ends with
   `All Applications reference values branch k3d-manager-v1.43.0`, but only that stage's
   Applications were checked.

## Cause

- `deploy_argocd_applicationsets` calls `_argocd_deploy_applicationsets STAGE` once per stage. The
  preamble lives inside that function: the info line, the `K3D_MANAGER_BRANCH` default, the
  directory check, `_argocd_validate_appset_rollout_stages`, the active app-cluster resolution with
  `_argocd_set_active_app_cluster`, and the file listing.
- `argocd_check_values_branch` prints the same success line whether or not `OWNERS` narrowed the
  check.

## Fix

All in `scripts/plugins/argocd.sh`.

1. **Move the preamble into a new `_argocd_prepare_applicationsets`.**
   - It takes everything from the start of `_argocd_deploy_applicationsets` up to, but not
     including, the file listing: the branch default and export, the directory check, the stage
     validation, and the active app-cluster resolution and label.
   - It prints `[argocd] Preparing ApplicationSets (branch <branch>, app-cluster <name>)` once.
2. **Make the preamble optional in `_argocd_deploy_applicationsets [STAGE] [prepared]`.**
   - It calls `_argocd_prepare_applicationsets` unless its second argument is `prepared`.
   - Its caller in `deploy_argocd_bootstrap` (no arguments) therefore behaves as before.
   - Its info line becomes `[argocd] Deploying <stage> ApplicationSets`, with `all` when no stage
     is given. Drop the word `sample`.
   - The count line becomes `Found <N> ApplicationSet file(s), <M> in stage <stage>`. For `all`,
     keep `Found <N> ApplicationSet file(s)`.
3. **`deploy_argocd_applicationsets` prepares once.**
   - It calls `_argocd_prepare_applicationsets` once, before the first stage, and returns 1 if that
     fails. This happens before any apply, so an unlabelled set still aborts before anything is
     applied.
   - `_argocd_apply_and_confirm_appset_stage` passes `prepared` through to
     `_argocd_deploy_applicationsets`.
4. **Fix the success line in `argocd_check_values_branch`.**
   - When `OWNERS` is non-empty, it prints
     `[argocd] All Applications of ApplicationSets <OWNERS> reference values branch <branch>`.
   - Without `OWNERS`, the line is unchanged, so `make appsets-check` and `cluster-status` output
     stay the same.
5. **Rules.** Every function stays at 8 `if`s or fewer. The agent audit runs in pre-commit, and
   Claude will run it; a self-reported pass is not accepted.

## Files

| File | Change |
|---|---|
| `scripts/plugins/argocd.sh` | items 1–4 |
| `scripts/tests/plugins/argocd_appset_rollout_stage.bats` | regression tests |
| `scripts/tests/plugins/argocd.bats` | adjust only if an existing test asserts the old info lines |
| `scripts/tests/plugins/argocd_values_branch_drift.bats` | owners success-line test |

## Tests

1. With `K3DM_APPSETS_STAGE=all`, the stubbed `_kubectl` and a stub
   `_argocd_set_active_app_cluster` that counts its calls:
   - the stub is called exactly once;
   - `Preparing ApplicationSets` appears exactly once in the output;
   - hub sets are still applied before app-cluster sets.
2. An unlabelled fixture set with `K3DM_APPSETS_STAGE=all` still aborts with zero applies.
3. `_argocd_deploy_applicationsets` with no arguments still prepares: the stub is called once and
   every set is applied. This is the `deploy_argocd_bootstrap` path.
4. `argocd_check_values_branch <branch> k3d-k3d-cluster hub-set`, on a passing fixture, prints
   `All Applications of ApplicationSets hub-set`. Without owners, it prints
   `All Applications reference values branch`.

Mutation checks. Paste the red output for each:
- Call `_argocd_prepare_applicationsets` unconditionally inside `_argocd_deploy_applicationsets`.
  Test 1 must fail.
- Drop the owners branch of the success line. Test 4 must fail.

## Rules

- `shellcheck scripts/plugins/argocd.sh`: no new warnings.
- Run the following and paste the output. All must be green:
  `bats scripts/tests/plugins/argocd_appset_rollout_stage.bats scripts/tests/plugins/argocd_appset_reapply_confirm_wait.bats scripts/tests/plugins/argocd.bats scripts/tests/plugins/argocd_values_branch_drift.bats scripts/tests/bin/makefile_appsets.bats scripts/tests/bin/cluster_status_values_branch.bats`
- Do not commit. `.git` is read-only in the sandbox.
