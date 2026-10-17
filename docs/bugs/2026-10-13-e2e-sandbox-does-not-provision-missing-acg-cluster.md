# Bug: e2e-sandbox stops at missing kubecontext instead of provisioning disposable ACG cluster

**Status:** LIVE-VERIFIED — 2026-10-17: fixes `b264e1cc`, `a09701f7`. Operator `make e2e-sandbox-provision` with no sandbox: CloudFormation stack created, `make up` finished, Tier 2 run `1792267442-14483` 4/4. Second run: preflight `readyz=ok`, no provisioning, Tier 2 run `1792268856-27928` 4/4
**Approval:** explicit 2026-10-17 "let also those to codex's queue and execute one at a time" (operator)
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

## Acceptance

Approval: operator "go ahead" 2026-10-17, including N1 as written (only the explicit
`e2e-sandbox-provision` command may provision; plain `e2e-sandbox` never does).
Every `must_not` needs a test shown red against the pre-fix code. The independent verifier is given
this section only.

```yaml
acceptance:
  must:
    M1: "ubuntu-k3s absent or failing /readyz, run authorized: the sandbox is provisioned, then the normal Tier 2 run continues"
    M2: "ubuntu-k3s healthy: it is reused and nothing is provisioned"
    M3: "a provisioning failure is recorded as phase provisioning-sandbox, separate from preflight and test failures"
  must_not:
    N1: "provision without explicit authorization: plain make e2e-sandbox, or the Slack operator role"
    N2: "provision before the credential preflight and the hub preflight have passed"
    N3: "provision on any CLUSTER_PROVIDER other than k3s-aws"
    N4: "report success when the provisioning step failed"
  evidence:
    E1: {proves: [M2, M3, N1, N2, N3, N4], kind: offline, how: "stubbed BATS from Codex and, separately, from the verifier; both green"}
    E2: {proves: [N1], kind: offline, how: "pytest: Slack e2e-sandbox-provision is admin + confirm, absent from the cloud-runner set and the cloud-bridge"}
    E3: {proves: [M1, M2], kind: live, how: "with no ubuntu-k3s, make e2e-sandbox-provision reaches running-playwright; a second run does not call make up"}
  interface:
    entry: "e2e_verify_sandbox in scripts/plugins/e2e.sh (via ./scripts/k3d-manager)"
    authorize: "E2E_SANDBOX_PROVISION=1 (set by make e2e-sandbox-provision)"
    provision_command: "make up CLUSTER_PROVIDER=k3s-aws"
    phase_variable: "_E2E_ACTIVE_PHASE"
    context: "ubuntu-k3s"
```

## Fix (spec, 2026-10-17)

**Authorization model.** Provisioning is a separate, explicit command, never a side effect of the
existing one. Slack's `up` is `admin`, and `e2e-sandbox` is `operator`. A flag on `e2e-sandbox`
would let an operator create an AWS sandbox, so instead:

- `make e2e-sandbox` keeps its current behaviour exactly: a missing or dead `ubuntu-k3s` fails
  preflight, with no side effects.
- New `make e2e-sandbox-provision` sets `E2E_SANDBOX_PROVISION=1`. If `ubuntu-k3s` is absent or not
  answering `/readyz`, it runs the same `make up CLUSTER_PROVIDER=k3s-aws` that Slack `up` runs, then
  continues into the normal Tier 2 run. A healthy sandbox is reused with no provisioning.
- In Slack, `e2e-sandbox-provision` is `admin` with `confirm`, the same bar as `up`. It is not added to
  the cloud-runner capability set, which stays `{"e2e-remote", "e2e"}` plus the aws lifecycle.
- Order of side effects: credentials (`_e2e_sandbox_preflight_auth`) and the hub preflight both run
  **before** any provisioning. Provisioning refuses any `CLUSTER_PROVIDER` other than `k3s-aws`.
- No teardown is added. The run's existing scoped cleanup is unchanged, and the ACG sandbox expires
  on its own (4h). Stale-session recovery is whatever `make up` already does (auto-login, then
  `acg_restart`); this fix does not add a second recovery path.

### F1. `scripts/plugins/e2e.sh` — two new functions, directly after `_e2e_sandbox_preflight_cluster`

```bash
function _e2e_sandbox_cluster_ready() {
  local ctx="ubuntu-k3s" timeout="${E2E_SANDBOX_PROBE_TIMEOUT:-15}"
  kubectl config get-contexts -o name 2>/dev/null | grep -qx -- "$ctx" || return 1
  kubectl --context "$ctx" get --raw=/readyz --request-timeout="${timeout}s" >/dev/null 2>&1
}

function _e2e_sandbox_provision_cluster() {
  local provider="${CLUSTER_PROVIDER:-k3s-aws}"
  if [[ "$provider" != "k3s-aws" ]]; then
    _err "[e2e] sandbox provisioning: refusing CLUSTER_PROVIDER=${provider}; only k3s-aws provisions the disposable ACG sandbox"
  fi
  _info "[e2e] sandbox provisioning: ubuntu-k3s is absent or not answering /readyz; running make up CLUSTER_PROVIDER=k3s-aws"
  if ! _run_command --soft -- make -C "${SCRIPT_DIR}/.." --no-print-directory up CLUSTER_PROVIDER=k3s-aws; then
    _err "[e2e] sandbox provisioning: make up CLUSTER_PROVIDER=k3s-aws failed; see its output above"
  fi
  _info "[e2e] sandbox provisioning: make up finished; rechecking ubuntu-k3s"
}
```

### F2. `scripts/plugins/e2e.sh`, `e2e_verify_sandbox`

old:
```bash
  _e2e_sandbox_preflight_auth
  _E2E_ACTIVE_PHASE="preflight-cluster"
  _e2e_sandbox_preflight_cluster
```
new:
```bash
  _e2e_sandbox_preflight_auth
  if [[ "${E2E_SANDBOX_PROVISION:-0}" == "1" ]] && ! _e2e_sandbox_cluster_ready; then
    _E2E_ACTIVE_PHASE="preflight-hub"
    _e2e_sandbox_preflight_hub
    _E2E_ACTIVE_PHASE="provisioning-sandbox"
    _e2e_sandbox_provision_cluster
  fi
  _E2E_ACTIVE_PHASE="preflight-cluster"
  _e2e_sandbox_preflight_cluster
```
A provisioning failure is recorded with phase `provisioning-sandbox` by the existing exit trap, so it
is separate from both preflight and test failures.

### F3. `scripts/plugins/e2e.sh`, `_e2e_sandbox_preflight_cluster` — point at the new command

In the absent-context `_err` message, replace `bring it up with the k3s-aws provider (make up) and confirm`
with `bring it up with the k3s-aws provider (make up), or run make e2e-sandbox-provision to provision it as part of the run, and confirm`.
No other change to that function.

### F4. `Makefile` — directly after the `e2e-sandbox` target

```make
## Tier 2 e2e that first provisions the ACG sandbox (make up CLUSTER_PROVIDER=k3s-aws) if ubuntu-k3s is absent or dead. DIGEST optional.
e2e-sandbox-provision:
	@$(call _e2e_recorded,e2e-sandbox-provision,env E2E_SANDBOX_PROVISION=1 ./scripts/k3d-manager e2e_verify_sandbox $(DIGEST))
```

### F5. `scripts/lib/webhook/make_targets.py` — directly after the `e2e-sandbox` entry

```python
    "e2e-sandbox-provision": {"min_role": "admin", "confirm": True, "optional": ("DIGEST",), "timeout": 7200, "summary": "Tier 2 e2e; provisions the ACG sandbox first if it is missing"},
```
7200s covers `make up` (3300s lifecycle default) plus a Tier 2 run (3600s).

### F6. Tests

- `scripts/tests/plugins/e2e_sandbox_preflight.bats` (stub `kubectl`, `make`, `_e2e_sandbox_preflight_auth`,
  `_e2e_sandbox_preflight_hub`; nothing real runs). Use a call log file and assert on it:
  1. Without `E2E_SANDBOX_PROVISION`, absent context: fails, `make` is never called, and the message
     names `make e2e-sandbox-provision`.
  2. `E2E_SANDBOX_PROVISION=1`, healthy context: `make` is never called.
  3. `E2E_SANDBOX_PROVISION=1`, absent context: the hub preflight runs before `make`, and `make` is
     called with exactly `up CLUSTER_PROVIDER=k3s-aws`.
  4. `E2E_SANDBOX_PROVISION=1`, `CLUSTER_PROVIDER=k3d`, absent context: fails and `make` is never called.
  5. `E2E_SANDBOX_PROVISION=1`, `make` fails: the run fails and `_E2E_ACTIVE_PHASE` is
     `provisioning-sandbox`.
  6. `E2E_SANDBOX_PROVISION=1`, auth preflight fails: `make` is never called.
  Show tests 3 and 6 red against the pre-fix `e2e.sh` on a temp copy.
- `scripts/tests/bin/webhook_make_targets.py`: `e2e-sandbox-provision` is `admin` with `confirm`, not
  listed for `operator`, listed for `admin`.
- `scripts/tests/bin/test_cloud_bridge.py`: add `"e2e-sandbox-provision"` to `NEVER_EXPOSED`.

### F7. Docs

- `docs/howto/slack-slash-commands.md`: a row for `e2e-sandbox-provision` (admin, confirm, `DIGEST`,
  7200) next to `e2e-sandbox`, plus one sentence in the e2e-sandbox section saying which to use.
- `docs/guides/vcluster-e2e-harness.md`: in the `make e2e-sandbox` section, describe
  `make e2e-sandbox-provision` and the reuse-if-healthy rule.
- `CHANGELOG.md` `[Unreleased]` → `### Added`.

## Files

`scripts/plugins/e2e.sh`, `Makefile`, `scripts/lib/webhook/make_targets.py`,
`scripts/tests/plugins/e2e_sandbox_preflight.bats`, `scripts/tests/bin/webhook_make_targets.py`,
`scripts/tests/bin/test_cloud_bridge.py`, `docs/howto/slack-slash-commands.md`,
`docs/guides/vcluster-e2e-harness.md`, `CHANGELOG.md`.

## Rules

shellcheck clean on `scripts/plugins/e2e.sh`; `bats scripts/tests/plugins/e2e_sandbox_preflight.bats`
and `bats scripts/tests/plugins/e2e.bats` green; `pytest scripts/tests/bin/test_cloud_bridge.py
scripts/tests/bin/webhook_make_targets.py` green. No test runs a real `make up`, `kubectl` or AWS call.

## Definition of Done

Commit message: `feat(e2e): make e2e-sandbox-provision brings up a missing ACG sandbox first`.
Live proof (operator, later): with no `ubuntu-k3s`, `make e2e-sandbox-provision` provisions and reaches
`running-playwright`; a second run reuses the sandbox without calling `make up`.

## What NOT to Do

- Do not change `make e2e-sandbox` behaviour or its `operator` role.
- Do not add the new target to the cloud-runner capability set or to the cloud-bridge.
- Do not add a teardown, and do not call `bin/cluster-up` directly: use `make up` so the
  observability and platform-ops steps run the same as a manual bring-up.
