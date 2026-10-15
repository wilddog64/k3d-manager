# Bug: AWS cluster-down can report success without verified sandbox deletion

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.4` (triage 2026-10-15, operator-approved placement)
**Status:** OPEN — confirmed control-flow risk; AWS resources not independently checked
**Priority:** P2 — false-positive teardown success risks billable stale cloud resources
**Severity:** medium
**Approval:** operator explicitly requested filing P2 on 2026-10-15; no implementation authorization
**Evidence:** ACG AWS teardown webhook job `b0e9616d` showed `cluster-down (aws) — success in 1m` in Slack, without a teardown log excerpt. **This is not evidence that resources remain**; no account-level AWS inventory was available.

## Verified control-flow defect

`bin/cluster-down` in the AWS provider branch includes:

```bash
elif aws sts get-caller-identity --region "${ACG_REGION}" --query 'Arn' --output text >/dev/null 2>&1; then
  acg_teardown --confirm || \
    _info "[acg-down] CloudFormation teardown failed — sandbox may have been recreated with new credentials. Stack cleanup skipped; continuing Hub teardown."
else
  _info "[acg-down] AWS credentials invalid or expired — sandbox already removed. Skipping CloudFormation teardown."
fi
```

This **swallows `acg_teardown` failure** and **assumes expired credentials mean the sandbox has already been removed**, despite those states being logically independent. Remaining local/hub cleanup can finish successfully and the webhook reports the top-level Make exit code, which therefore does not guarantee AWS stack deletion. A fast job with no Slack log excerpt (tracked separately in `docs/bugs/2026-10-15-cluster-down-short-job-no-slack-output.md`) obscures whether this occurred for this particular run.

Prior CloudFormation stack name observed for the corresponding bring-up job `5f5cff23`: `k3d-manager-cluster`. Region should be read from the job's resolved `ACG_REGION` (default documented in script as `us-west-2`), not assumed for every execution.

## Expected behavior

A cluster teardown must distinguish **verified AWS teardown**, **local-only cleanup**, and **AWS teardown unverified/failed**. Unavailable credentials or failure to delete the stack must never be asserted as proof that the sandbox is gone. Any remaining potentially billable resources require an explicit, actionable warning and retained job evidence.

## Investigation and remediation criteria

1. Review the actual job `b0e9616d` output from the job-status endpoint/retained output file for `acg_teardown`, credentials, stack name/region, and warnings. Do not infer the outcome solely from its green Slack status.
2. Trace `acg_teardown --confirm` into its actual AWS-provider implementation and verify whether it waits for `DELETE_COMPLETE`, handles `DELETE_FAILED`, and checks for stack absence. Record the real return-value semantics before choosing a fix.
3. Perform **read-only**, scoped inventory in the correct ACG account and region: CloudFormation stack status/existence; sandbox-owned EC2 instances, EBS volumes/snapshots, EIPs, load balancers, networking and other stack-related resources. Attribute each resource using CloudFormation physical IDs/tags before treating it as an orphan; do not claim unrelated resources are stale.
4. Treat nonzero `acg_teardown`, unavailable/expired credentials, lookup errors, and uncertain stack existence as **unverified cloud cleanup**, not normal success. Preserve the option to finish safe local cleanup, but retain non-success or partial-success state and a high-visibility operator warning; define behavior for AWS sandbox auto-expiration separately.
5. Emit a bounded, redacted terminal teardown summary (or link to authorized job output), containing stack identifier, region, credential-validation result, CloudFormation delete request/result, final observed state and follow-up action. Keep secrets and sensitive response URLs out of logs and alerts.
6. Consider a narrowly scoped, read-only post-teardown verification action in the cloud bridge for remote operators; do not enable arbitrary AWS CLI, shell commands, or broaden cloud-runner privileges to accomplish this.
7. Add negative, deterministic tests with mocked AWS calls for delete success, delete failure, invalid/expired credentials, stack not found, timeout, partial deletion, and unexpected resources. Confirm cleanup warnings survive to job terminal status and Slack.
8. Validate any change against the existing teardown and lifecycle test suites, preserving non-destructive defaults and avoiding real deletion in automated tests.

## Acceptance criteria

- A green `cluster-down` result cannot silently mean CloudFormation delete failed, was skipped on an unsupported assumption, or was never verified.
- Genuine deletion is supported by a scoped, read-only AWS outcome; when no AWS verification is possible, status says **unverified** rather than **deleted**.
- Remaining stack-related resources or inconclusive credential/region scope produce an actionable non-green/partial state; cleanup of local resources can proceed safely without hiding cloud failures.
- The operator can distinguish command exit 0, actual CloudFormation deletion, and absence of orphaned AWS resources.
- Automated tests prove failure paths do not accidentally return a fully successful terminal status.

## Related

- `docs/bugs/2026-10-15-cluster-down-short-job-no-slack-output.md` — no output in short-job Slack completion.
- `docs/bugs/2026-10-15-acg-up-prometheus-forward-missing-after-success.md` — related pattern of an unqualified green lifecycle result despite an unavailable operational component.

**Implementation:** not started. No AWS resources were queried or changed as part of filing.
