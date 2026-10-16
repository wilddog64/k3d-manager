# Bug: e2e-sandbox stops at missing kubecontext instead of provisioning disposable ACG cluster

**Status:** OPEN — reproduced in Slack job output; implementation not changed
**Priority:** P2
**Filed:** 2026-10-13
**Detected by:** human
**Affected:** `make e2e-sandbox`, Slack dispatch, ACG/k3s-aws Tier 2 E2E
**Branch:** `k3d-manager-v1.43.4` (triage 2026-10-15, operator-approved placement)

## Observed failure

Slack `make e2e-sandbox` was accepted and started, then failed during cluster preflight (Slack wrapper reported rc 2; E2E summary reported `exit_code=1`):

```text
INFO: [e2e] ACG preflight: service=k3dm-acg-pluralsight credentials_loadable=true K3DM_ACG_REQUIRE_CREDENTIALS=1
ERROR: [e2e] sandbox preflight: kubecontext ubuntu-k3s is absent, so every later phase would fail on 'context was not found'; the sandbox k3s cluster is not provisioned in this kubeconfig — bring it up with the k3s-aws provider (make up) and confirm with 'kubectl --context ubuntu-k3s get nodes' before rerunning Tier 2
```

Example log from the operator screenshot: `/Users/cliang/.k3dm/e2e/make-e2e-sandbox-20261013T213728Z.log`. This is a **preflight failure**, not an application/Playwright test failure.

## Source-level cause

In `scripts/plugins/e2e.sh`, `_e2e_sandbox_preflight_cluster()` immediately returns failure when `kubectl config get-contexts -o name` does not include `ubuntu-k3s`, or when `/readyz` is unavailable. It does not invoke the existing ACG sandbox lifecycle and `k3s-aws` provisioning capabilities. Existing `scripts/tests/plugins/e2e_sandbox_preflight.bats` explicitly tests this failure behavior. A missing kubecontext alone does not prove the AWS cluster is absent; compare actual provider/sandbox state first.

## Expected operator contract

One authorized `make e2e-sandbox` request should prepare the **disposable ACG E2E environment**, if missing, and then execute Tier 2 verification. A separate manual sandbox-up/`make up` should not be required for this workflow. Preserve existing read-only diagnostics and fail-closed handling for unavailable credentials or unsafe states.

## Proposed behavior

1. Check credentials, ACG session expiration, approved `k3s-aws` provider, and remote cluster/instance state; do not infer cloud state solely from local kubeconfig.
2. If the correct sandbox cluster is already healthy, reuse it.
3. If the disposable cluster is absent and provisioning is expressly authorized for this operation, use the existing tightly scoped ACG sandbox-up and `k3s-aws` lifecycle logic, then wait for a ready `ubuntu-k3s` context and API.
4. If context is stale, distinguish sandbox expiration, unavailable kubeconfig and dead endpoint before safely restoring/recreating anything.
5. Continue the existing app deployment, E2E testing, result publication and scoped cleanup. On provisioning or readiness failure, stop with meaningful logs and a separate `environment_setup_failed` classification.
6. Do not change persistent hub/Hostinger clusters, use unspecified providers, expose general-purpose cluster creation to cloud agents, or quietly expand cloud-bridge privileges. Authorization and sandbox cost/time bounds must be explicit; if not authorized, fail with an approval-needed error instead of provisioning.

## Acceptance criteria

- [ ] No `ubuntu-k3s` kubecontext, disposable sandbox absent: one **authorized** `make e2e-sandbox` provisions the required environment and reaches E2E.
- [ ] Existing healthy sandbox: workflow reuses it without duplicate provisioning.
- [ ] Stale kubecontext / expired ACG session: identifies actual state and either recovers safely under authorization or fails explicitly without affecting other clusters.
- [ ] Missing/locked credentials, absent approval, and invalid provider: fail closed **before** side effects.
- [ ] Slack dispatch follows the same lifecycle contract and captures separate provisioning / readiness / application-test outcomes.
- [ ] BATS tests mock provider lifecycle and Kubernetes readiness, verifying correct ordering, idempotency, absence of destructive side effects and no fallback to a persistent cluster.
- [ ] Operator-approved real ACG dry-run/verification records cluster creation/reuse, actual E2E results, cleanup and running-cost implications.

## Related design

`docs/plans/v1.41.0-cloud-bridge-sandbox-lifecycle.md` intentionally excluded `e2e-sandbox` from new sandbox-up/down permissions; do not bypass those boundaries. This bug records the newly clarified operator intent for the **single E2E workflow**; implementation must reconcile lifecycle authorization with that intent. No live provisioning or executable code changes were made when this bug was filed.
