# Bug: AWS cluster-down can report success without verified sandbox deletion

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.4` (triage 2026-10-15, operator-approved placement)
**Status:** VERIFIED — 2026-10-17: part A lib-foundation v0.5.4 (subtree `cb573b61`); part B `bin/cluster-down` `d0117dbf` (cluster_down.bats 28/28); independent acceptance suite `cluster_down_acceptance.bats` 11/11 on HEAD, 11/11 red on pre-fix. E3 live (`make down` on a live sandbox and after expiry) pending
**Priority:** P2 — false-positive teardown success risks billable stale cloud resources
**Severity:** medium
**Approval:** operator explicitly requested filing P2 on 2026-10-15; fix approved 2026-10-16 "go for that green + warning" (operator) — credential-invalid stays exit 0 with an `UNVERIFIED` warning
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

## Code trace (Claude, 2026-10-16, read-only; criterion 2)

No AWS call was made. Three defects, two of them upstream in lib-foundation:

1. **`bin/cluster-down:119-123`:** a failed `sts get-caller-identity` is logged as "sandbox already
   removed" and the run ends green. That is usually true for ACG, because an expired sandbox takes
   its whole account with it. But it is unverified, and the same branch fires for a wrong profile,
   a wrong region, or a network failure.
2. **`acg_teardown` (lib-foundation `scripts/lib/acg/acg.sh:835`):** `describe-stacks` runs with
   `--soft … 2>/dev/null || true`, so any error (throttling, permission, network) leaves
   `stack_status` empty. The function then logs "No CloudFormation stack found — nothing to tear
   down" and "Teardown complete", and returns 0. A lookup failure reads as a verified absence. Only
   the AWS "does not exist" error should mean absent.
3. **Hard failure kills the whole teardown:** `delete-stack` and `wait stack-delete-complete` use
   `_run_command` without `--soft`. On failure `_run_command_handle_failure` calls `_err`, which
   runs `exit 1` (`system.sh:1893`) inside the function. The `|| _info "…continuing Hub teardown"`
   fallback in `cluster-down` therefore never runs. The script stops before the hub deregister and
   the Vault port-forward clean-up, and the exit code is non-zero. That is loud, but it is not the
   "continue local clean-up, report unverified" behaviour the fallback message promises.

`wait stack-delete-complete` itself is sound: it fails on `DELETE_FAILED` and on its own timeout.
Once 2 and 3 are fixed, a zero return from `acg_teardown` means a verified delete or a verified
absence.

Fix shape, for the spec: in lib-foundation, `acg_teardown` returns distinct codes for deleted or
absent (0), lookup failed (2) and delete failed (3), with `--soft` on the delete and wait. In
`cluster-down`, map those codes and the credential-invalid case to a terminal line,
`[acg-down] cloud teardown: verified|absent|UNVERIFIED (<reason>)`. Exit non-zero on
lookup-failed or delete-failed after the local clean-up has run. Keep exit 0 with an `UNVERIFIED`
warning for credential-invalid, which is the normal ACG-expiry case. That choice is the
operator's to confirm.

## Fix (spec, 2026-10-16)

Two repos, in order: lib-foundation first (defects 2 and 3), then a subtree pull and the
`cluster-down` change here (defect 1). Return codes for `acg_teardown`:

| rc | Meaning |
|---|---|
| 0 | stack deleted (`DELETE_COMPLETE`) or verified absent (AWS "does not exist") |
| 1 | `--confirm` missing, or `_acg_check_credentials` failed (unchanged) |
| 2 | stack lookup failed — any `describe-stacks` error other than "does not exist" |
| 3 | `delete-stack` or `wait stack-delete-complete` failed |

### A. lib-foundation `scripts/lib/acg/acg.sh`, `acg_teardown`

Branch in lib-foundation per its own release convention; PR, release, then subtree-pull here.

old:
```bash
  local stack_status
  stack_status=$(_run_command --soft -- aws cloudformation describe-stacks \
    --region "${ACG_REGION}" --stack-name "${_ACG_CF_STACK_NAME}" \
    --query 'Stacks[0].StackStatus' --output text 2>/dev/null || true)

  if [[ -z "$stack_status" || "$stack_status" == "None" ]]; then
    _info "[acg] No CloudFormation stack found — nothing to tear down"
  else
    _info "[acg] Deleting CloudFormation stack ${_ACG_CF_STACK_NAME}..."
    _run_command -- aws cloudformation delete-stack \
      --region "${ACG_REGION}" --stack-name "${_ACG_CF_STACK_NAME}"
    _run_command -- aws cloudformation wait stack-delete-complete \
      --region "${ACG_REGION}" --stack-name "${_ACG_CF_STACK_NAME}"
    _info "[acg] Stack deleted"
  fi
```
new:
```bash
  local stack_status lookup_rc=0
  stack_status=$(_run_command --soft --quiet -- aws cloudformation describe-stacks \
    --region "${ACG_REGION}" --stack-name "${_ACG_CF_STACK_NAME}" \
    --query 'Stacks[0].StackStatus' --output text 2>&1) || lookup_rc=$?

  if (( lookup_rc != 0 )); then
    if [[ "$stack_status" == *"does not exist"* ]]; then
      stack_status=""
    else
      _warn "[acg] Could not read CloudFormation stack ${_ACG_CF_STACK_NAME} in ${ACG_REGION} (rc=${lookup_rc}) — teardown UNVERIFIED"
      return 2
    fi
  fi

  if [[ -z "$stack_status" || "$stack_status" == "None" ]]; then
    _info "[acg] No CloudFormation stack found — nothing to tear down"
  else
    _info "[acg] Deleting CloudFormation stack ${_ACG_CF_STACK_NAME}..."
    if ! _run_command --soft -- aws cloudformation delete-stack \
      --region "${ACG_REGION}" --stack-name "${_ACG_CF_STACK_NAME}"; then
      _warn "[acg] delete-stack request failed for ${_ACG_CF_STACK_NAME} — teardown UNVERIFIED"
      return 3
    fi
    if ! _run_command --soft -- aws cloudformation wait stack-delete-complete \
      --region "${ACG_REGION}" --stack-name "${_ACG_CF_STACK_NAME}"; then
      _warn "[acg] ${_ACG_CF_STACK_NAME} did not reach DELETE_COMPLETE — teardown UNVERIFIED"
      return 3
    fi
    _info "[acg] Stack deleted"
  fi
```
The raw `describe-stacks` error text is matched, never printed. Update the `--help` text with the
return-code table. A failed lookup or delete returns before the kubeconfig context is removed,
because the sandbox may still be alive.

Tests (`scripts/tests/lib/acg.bats`, stubbed `aws`, no network): rc 0 on delete + wait success;
rc 0 and "nothing to tear down" on "does not exist"; **rc 2** on a throttling/AccessDenied lookup
error (the pre-fix code returns 0 — show it red on a temp copy); **rc 3** on delete-stack failure
and on wait failure, and the function *returns* rather than exiting the shell (pre-fix: `_err`
exits — show it red).

### B. k3d-manager `bin/cluster-down` (after the subtree pull)

old:
```bash
    elif aws sts get-caller-identity --region "${ACG_REGION}" --query 'Arn' --output text >/dev/null 2>&1; then
      acg_teardown --confirm || \
        _info "[acg-down] CloudFormation teardown failed — sandbox may have been recreated with new credentials. Stack cleanup skipped; continuing Hub teardown."
    else
      _info "[acg-down] AWS credentials invalid or expired — sandbox already removed. Skipping CloudFormation teardown."
    fi
```
new:
```bash
    elif aws sts get-caller-identity --region "${ACG_REGION}" --query 'Arn' --output text >/dev/null 2>&1; then
      _acg_rc=0
      acg_teardown --confirm || _acg_rc=$?
      case "${_acg_rc}" in
        0) _cloud_teardown="verified (stack ${_ACG_CF_STACK_NAME:-k3d-manager-cluster} deleted or absent in ${ACG_REGION})" ;;
        2) _cloud_teardown="UNVERIFIED (stack lookup failed in ${ACG_REGION})"; _cloud_teardown_failed=1 ;;
        3) _cloud_teardown="UNVERIFIED (stack delete failed in ${ACG_REGION})"; _cloud_teardown_failed=1 ;;
        *) _cloud_teardown="UNVERIFIED (acg_teardown rc=${_acg_rc})"; _cloud_teardown_failed=1 ;;
      esac
      [[ "${_cloud_teardown_failed}" -eq 1 ]] && _warn "[acg-down] CloudFormation teardown ${_cloud_teardown} — continuing local teardown; check the AWS console before the sandbox is reused."
    else
      _cloud_teardown="UNVERIFIED (AWS credentials invalid — sandbox presumed expired, not checked)"
      _warn "[acg-down] AWS credentials invalid or expired — CloudFormation teardown skipped and NOT verified. An expired ACG sandbox takes its account with it; a wrong profile or region does not."
    fi
```
Initialise `_cloud_teardown="not applicable (${_cluster_provider})"` and `_cloud_teardown_failed=0`
next to the other top-level defaults, and `_cloud_teardown="dry-run"` in the DRY_RUN arm.

At the end of the script, after the existing `Done.` lines:
```bash
_info "[acg-down] cloud teardown: ${_cloud_teardown}"
if [[ "${_cloud_teardown_failed}" -eq 1 ]]; then
  _warn "[acg-down] Local teardown finished, but the AWS stack was not verified deleted."
  exit 1
fi
```

Decision (operator, 2026-10-16): credential-invalid stays **exit 0** with the `UNVERIFIED`
warning and summary line; lookup and delete failures exit **1** after the local clean-up has run.

Tests (`scripts/tests/bin/cluster_down.bats`, existing stub harness): for each of `acg_teardown`
rc 0/2/3 and an `sts` failure, assert the summary line text, that the hub deregister and Vault
port-forward clean-up still ran, and the exit code (0, 1, 1, 0). Show the rc-2/rc-3 cases red
against the pre-fix script on a temp copy. Docs: the teardown section of the ACG guide gains the
summary-line meanings; `CHANGELOG.md` `### Fixed`. There is no ACG guide yet: document the summary
line and exit codes next to `make down` in `docs/howto/makefile.md`.

Out of scope here: an account-level AWS orphan inventory (criteria 3 and 6) and Slack log
excerpts (`2026-10-15-cluster-down-short-job-no-slack-output.md`).

## Acceptance

```yaml
must:
  - id: M1
    text: With CLUSTER_PROVIDER=k3s-aws, valid credentials and acg_teardown rc 0, bin/cluster-down --confirm exits 0 and prints "cloud teardown: verified" naming the stack and region.
  - id: M2
    text: When acg_teardown returns 2 (lookup failed) or 3 (delete failed), cluster-down still runs the hub deregister and Vault port-forward clean-up, prints "cloud teardown: UNVERIFIED" with the cause, and exits 1.
  - id: M3
    text: When `aws sts get-caller-identity` fails, acg_teardown is not called, a warning says the teardown was skipped and NOT verified, the summary line says UNVERIFIED (credentials invalid), and the exit code is 0.
  - id: M4
    text: A dry run prints the summary "cloud teardown: dry-run", calls no acg_teardown, and exits 0; a non-AWS provider prints "not applicable (<provider>)".
must_not:
  - id: N1
    text: An acg_teardown rc 2 or 3 never ends in exit 0 (red against the pre-fix script).
  - id: N2
    text: The word "verified" without the UN prefix never appears in the summary when acg_teardown was not called or returned non-zero.
  - id: N3
    text: No real aws or kubectl call is made by the tests (stubs only; no AWS resource touched).
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2]
    kind: offline
    text: scripts/tests/bin/cluster_down.bats cases for rc 0/2/3, sts failure, dry-run; rc 2/3 cases shown red on a temp copy of the pre-fix script.
  - id: E2
    proves: [N3]
    kind: offline
    text: Stubs on PATH log every aws/kubectl invocation; the log contains only stubbed calls.
  - id: E3
    proves: [M1, M3]
    kind: live
    text: Operator or Claude runs make down against a live ACG sandbox (and once after expiry); job output shows the summary line and the matching exit status.
interface:
  - bin/cluster-down [--confirm] [provider] [dry-run]  (env CLUSTER_PROVIDER, ACG_REGION, K3DM_DEPLOY_DRY_RUN, KEEP_LOCAL)
  - acg_teardown --confirm return codes 0/1/2/3 (lib-foundation v0.5.4)
  - aws sts get-caller-identity (credential probe)
  - stdout/stderr summary line "[acg-down] cloud teardown: ..."
```

**Implementation:** part A in lib-foundation v0.5.4; part B `d0117dbf`. No AWS resources were queried or changed as part of filing or testing.
