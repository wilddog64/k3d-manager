# Bug: acg-up warns a CloudFormation stack is "still running — billable" when the run failed before creating it

**Status:** OPEN
**Priority:** P3
**Severity:** low — a false alarm that tells the operator to run `make down`; no stack exists
**Approval:** operator, 2026-11-01 (session goal: finish v1.43.13 items; found in job `87c78389`)
**Filed:** 2026-11-01
**Detected by:** Claude, job `87c78389` on the M5
**Affected:** `scripts/lib/providers/k3s-aws.sh` (`_provider_k3s_aws_mark_stack_created`, called before `acg_provision`), `bin/cluster-up` (cleanup warning, ~line 237)
**Branch:** `k3d-manager-v1.43.13`

## Observed failure

Job `87c78389` failed at `ssh-keygen` (missing key), before `create-stack`, and printed
`CloudFormation stack 'k3d-manager-cluster' (us-west-2) was created by this run and is still running — billable.`
A read-only check right after: `describe-stacks` → `Stack with id k3d-manager-cluster does not exist`; 0 EC2
instances.

## Root cause

`k3s-aws.sh` writes the `cf-stack-created` marker before calling `acg_provision`, so any failure inside
`acg_provision` before `create-stack` (AMI lookup, key, template render) leaves a marker for a stack that was never
created. The cleanup in `bin/cluster-up` trusts the marker.

## Fix

Before printing the warning, `bin/cluster-up` cleanup checks `aws cloudformation describe-stacks` for the marked
stack (read-only, `--soft`). If the stack does not exist, it prints
`no CloudFormation stack was created by this run` instead. If the check itself fails (no credentials, network), it
keeps today's warning and adds `(not confirmed)`.

## Files

- `bin/cluster-up`
- `scripts/tests/bin/cluster_up.bats`
- `CHANGELOG.md`

## What NOT to do

- Do not delete the stack or call any mutating AWS API from cleanup.
- Do not drop the warning when the stack exists.
- The stub `describe-stacks` "does not exist" error is captured from the real read-only run of 2026-11-01 (M5).

## Acceptance

```yaml
must:
  M1: with the marker present and describe-stacks reporting the stack exists, cleanup prints the billable warning (paired positive control for N1)
  M2: when describe-stacks itself fails for another reason, the warning is kept with "(not confirmed)"
must_not:
  N1: with the marker present and describe-stacks reporting "does not exist", cleanup never prints "still running — billable"
  N2: cleanup never calls a mutating aws command (delete-stack, etc.)
evidence:
  E1:
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: You will see cluster_up.bats with a stub aws recording argv print the warning for an existing stack, "no CloudFormation stack was created" for a missing one (red on the pre-fix script), "(not confirmed)" on a stub failure, and log only describe-stacks.
    what: bats scripts/tests/bin/cluster_up.bats
interface:
  - bin/cluster-up cleanup (via make up CLUSTER_PROVIDER=k3s-aws failure)
  - ${_ACG_STATE_DIR}/run/cf-stack-created
  - aws cloudformation describe-stacks
```
