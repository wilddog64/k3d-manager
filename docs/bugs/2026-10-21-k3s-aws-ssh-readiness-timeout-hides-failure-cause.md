# Bug: k3s-aws provisioning SSH readiness timeout hides connection failure cause

**Filed:** 2026-10-21 (operator Slack failure-analysis screenshot)
**Status:** VERIFIED — offline diagnostics fix landed in `293b6d76`; EC2-side root cause unknown; live verification pending
**Priority:** P3 — intermittent sandbox readiness and poor diagnostics; reclassify P2 if reproducibly blocks provisioning
**Severity:** low pending recurrence/impact evidence
**Approval:** operator explicitly requested dispatch/implementation on 2026-10-21 after a second live reproduction; offline code/tests authorized, no additional live provisioning or teardown authorized
**Release:** v1.43.5 (bug; exempt from plan cap)
**Branch:** `k3d-manager-v1.43.5`
**Found by:** operator, Slack failure analysis job `aeeeb11f` on 2026-10-21 around 13:36 PDT
**Component:** `scripts/plugins/shopping_cart.sh` (`_ubuntu_k3s_wait_ssh_ready`, `deploy_app_cluster`), provider's AWS/CloudFormation provisioning path and relevant BATS tests
**Related:** `docs/issues/2026-08-20-k3s-aws-ssm-fallback-provisioning.md`, `docs/bugs/2026-08-14-k3s-aws-ssm-agent-cannot-register.md`, `docs/bugs/2026-08-15-cluster-up-failure-orphans-cloudformation-stack.md`

## Symptom

Slack failure analysis for job `aeeeb11f` reports:

```text
CLUSTER_FAILURE
TRANSIENT
The k3s server EC2 instance (ubuntu at 34.214.127.151) did not finish booting and
initializing its SSH service within the 180-second timeout following CloudFormation
provisioning.
Retry the provisioning by running make up CLUSTER_PROVIDER=k3s-aws now that
the EC2 instances are online and ready to accept SSH connections.
```

The analyzer's assertions about boot completion, SSH service initialization, and
subsequent instance readiness are **inferences**, not yet corroborated by EC2 status
checks, SSH stderr, or console/cloud-init output. The instance could instead have been
unreachable due to connectivity, security group, SSH authentication, or an incorrect
address/key. A retry is not proven safe or useful until current stack state is checked.

## Source-level finding

At `k3d-manager-v1.43.5`, `scripts/plugins/shopping_cart.sh` defines:

```bash
function _ubuntu_k3s_wait_ssh_ready() {
  local host="$1" ssh_user="$2" ssh_key="$3"
  local budget="${K3DM_SSH_READY_TIMEOUT:-180}" waited=0
  until ssh -i "${ssh_key}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o BatchMode=yes -o ConnectTimeout=10 "${ssh_user}@${host}" true >/dev/null 2>&1; do
    if (( waited >= budget )); then
      _err "[shopping_cart] ${ssh_user}@${host} did not answer SSH within ${budget}s — node unresponsive; not starting k3sup"
      return 1
    fi
    sleep 10
    (( waited += 10 ))
  done
}
```

`deploy_app_cluster` calls the readiness helper before `k3sup install`, correctly
preventing installation while the server is unreachable. However:

1. The SSH probe discards stderr and exit classification, so operators cannot
   distinguish timeout/refusal, authentication rejection, DNS/address errors, or
   other failures.
2. The `waited` counter increases only on the 10-second sleep, excluding time
   spent in each SSH attempt (up to `ConnectTimeout=10` or more), so the reported
   `180s` is not a precise wall-clock readiness deadline.
3. The post-failure AI analysis can overstate the cause ("did not finish booting")
   and readiness ("now ... online and ready") without independent evidence.
4. The existing CloudFormation stack and instance state must be considered before
   suggesting a full `make up` retry.

The older SSM-registration/fallback issues concern a different transport phase;
they do not establish the cause of this SSH probe failure.

## Second live reproduction (2026-10-21)

During the operator's `make up CLUSTER_PROVIDER=k3s-aws` attempt, the tmux pane showed:

```text
INFO: [shopping_cart] Installing k3s on ubuntu@ubuntu via k3sup...
WARN: [shopping_cart] ssh-keyscan ubuntu not ready after 120s — k3sup may prompt
ERROR: [shopping_cart] ubuntu@ubuntu did not answer SSH within 180s — node unresponsive; not starting k3sup
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
```

The existing fail-closed readiness guard worked: `k3sup` was not started. The warning and error still do not identify why SSH failed because keyscan/SSH diagnostics are not surfaced. The subsequent explicitly chained `make down` completed CloudFormation deletion and hub deregistration; this confirms teardown, not the EC2-side cause. Do not infer that the node was booting, that SSH later recovered, or that authentication/networking was the cause. Exact full output is preserved in `docs/issues/2026-10-21-acg-live-verification-node-ssh-timeout.md`.

## Expected behavior

- When the SSH readiness window is exhausted, surface a short, redacted,
  actionable classification of the *last observed* connection failure with
  actual elapsed time and configured budget.
- Distinguish EC2 running/status-check success from successful SSH readiness;
  do not claim successful boot, open port 22, or SSH authentication without proof.
- Preserve fail-closed behavior: do not invoke `k3sup` before a successful SSH probe.
- Recommend read-only instance/stack inspection before retriggering provisioning.
- Preserve existing sandbox security boundaries; never print keys, tokens, or
  raw credential-bearing command lines.

## Offline implementation status

The source change captures SSH stderr locally and emits only an allowlisted failure class with
elapsed wait and budget. The success probe remains the gate before `k3sup`; failure-analysis
guidance now distinguishes observations from hypotheses and directs operators to inspect current
CloudFormation and EC2 state before retrying. The 2026-10-21 EC2-side cause remains **unknown**.
No AWS/EC2 query or live verification was performed for this change.

**Offline verification (2026-10-21):** `bats scripts/tests/plugins/shopping_cart.bats` passed 38/38; `python3 -m pytest -q -p no:cacheprovider scripts/tests/bin/test_webhook_ssh_failure_analysis.py` passed 1/1. ShellCheck (`-x -S warning`), Python AST parse, `git diff --check`, `_agent_lint`, `_agent_audit`, and `make check-doc-links` (2294 files) passed. Dispatcher landing gate passed. The 2026-10-21 EC2-side cause remains unknown; neither offline results nor the prior timed-out/deleted instance constitute live verification.

## Proposed fix scope

1. In the readiness helper, capture bounded/redacted SSH diagnostic evidence and
   failure type while retaining successful `ssh ... true` as the gate. Prefer a
   monotonic or real elapsed-time deadline over sleep-counting; evaluate the existing
   `K3DM_SSH_READY_TIMEOUT` contract before changing timing.
2. On failure, include concise EC2/CloudFormation context when safely available,
   such as state, status checks, known instance address and stack status; if no data
   can be read, explicitly report `unknown`.
3. Update failure-analysis response logic to separate observed facts from possible
   explanations, and avoid claiming the instance is online/SSH-ready based only on
   an expired timeout.
4. Add focused offline BATS/unit fixtures for refused/timeout/auth failure,
   delayed success, actual elapsed timeout, redaction, and preservation of the
   no-`k3sup`-before-SSH guard.
5. Consider existing-stack idempotency and safe retry guidance; do not automatically
   destroy or reprovision a still-running sandbox.

## Acceptance

```yaml
must:
  - id: M1
    text: SSH readiness failures expose a bounded, redacted error classification and actual elapsed wait, rather than only "did not answer SSH".
  - id: M2
    text: The reported timeout is consistent with the implemented wall-clock budget, including time spent in connection attempts.
  - id: M3
    text: Failure analysis distinguishes proven EC2/SSH state from hypotheses and does not assert an instance is ready without verification.
  - id: M4
    text: Successful SSH remains a prerequisite for k3sup, and delayed SSH readiness can succeed without premature abort.
  - id: M5
    text: Retry instructions account for an existing CloudFormation stack and do not suggest unsafe duplicate provisioning.
must_not:
  - id: N1
    text: SSH credentials, tokens or sensitive diagnostic output are disclosed to Slack or permanent metrics.
  - id: N2
    text: A timeout triggers automatic teardown, stack recreation, or a bypass of SSH readiness.
  - id: N3
    text: Failure analysis asserts cloud-init or sshd caused the timeout without direct evidence.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, M5, N1, N2, N3]
    text: Stubbed AWS/SSH tests cover connection refused, timeout, auth failure, late readiness, elapsed-deadline accounting, redaction and pre-k3sup guard; demonstrate the pre-fix diagnostic shortcoming.
  - id: E2
    kind: live
    proves: [M1, M2, M3, M4, M5]
    text: On a disposable authorized ACG sandbox, capture read-only CloudFormation and EC2 status plus SSH probe classification for a delayed or failed bring-up; establish actual cause before marking live verified.
interface:
  - scripts/plugins/shopping_cart.sh (_ubuntu_k3s_wait_ssh_ready and k3sup caller)
  - scripts/lib/providers/k3s-aws.sh (AWS provider integration)
  - bin/k3dm-webhook (failure analysis output, if required)
  - relevant BATS tests and docs/howto/acg.md
```

## Definition of Done

- [ ] Root cause of the reported job verified from EC2/CloudFormation and SSH evidence, or recorded as unknown.
- [ ] Focused regression tests red on original behavior and green with the fix.
- [ ] Relevant offline test suite passes without contacting real cloud hosts.
- [x] Operator explicitly authorized offline implementation/dispatch on 2026-10-21; E2 remains pending and requires a future operator-approved live run before LIVE-VERIFIED.
- [ ] Record fix SHA, verification evidence, and final status in this bug document.

## What NOT to Do

- Do NOT create a PR or merge to `main`.
- Do NOT modify implementation code or provision/tear down AWS infrastructure while filing.
- Do NOT assume the 180-second timeout proves cloud-init or sshd was late.
- Do NOT bypass SSH readiness or print secrets to improve diagnostics.

## Files

- `scripts/plugins/shopping_cart.sh`
- `scripts/lib/providers/k3s-aws.sh`
- `bin/k3dm-webhook`
- `scripts/tests/plugins/shopping_cart.bats`
- `scripts/tests/bin/`
- `docs/howto/acg.md`
- `docs/bugs/2026-10-21-k3s-aws-ssh-readiness-timeout-hides-failure-cause.md`
- `docs/issues/2026-10-21-k3s-aws-ssh-readiness-dispatch-spec.md`
