# Bug: app-cluster registration exits silently when the role-label lookup fails

**Filed:** 2026-10-18 (Claude, from the live `e2e-sandbox-provision` run, job `f5e6229f`)
**Status:** LIVE-VERIFIED — 2026-10-20: Slack-originated job `05f2be6c` completed E2E run `1792538358-29202` with 4/4 passed and `exit_code=0`; registration log confirms the cluster Secret was applied and the live hub Secret has the `app-cluster` role label with creation time `2026-10-20T23:26:40Z`.
**Fix commit:** `a70e52a4`
**Live evidence:** 2026-10-20 · run 1792538358-29202 · env sandbox/local-m4 · scenario slack-e2e-sandbox-provision-app-cluster-registration · commit a70e52a4 · proves E2
**Priority:** P1 — `make up CLUSTER_PROVIDER=k3s-aws` stops at Step 10 with no error; no workaround on this branch
**Severity:** high (regression on `k3d-manager-v1.43.5`, unreleased)
**Approval:** approved — operator, 2026-10-18: "yes" to dispatching to Codex
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `scripts/plugins/argocd.sh` (app-cluster registration, ~1633)
**Related:** `781494e6` `fix(argocd): keep data-layer resources and the role label across re-registration`
(introduced the lookup); `docs/bugs/2026-10-18-data-layer-app-cascade-deleted-by-registration-label-window.md`

## Symptom

Job `f5e6229f` (`/k3dm e2e-sandbox-provision confirm`, 2026-10-19 01:24Z, e2e run `1792372702-6827`):

```
INFO: [argocd] registering app cluster 'ubuntu-k3s' -> https://host.k3d.internal:16443
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
```

No line in between. The hub's `ubuntu-k3s-app-cluster` Secret was not updated (still 2d23h old,
provider `k3d`). The ACG CloudFormation stack was left running.

## Root cause

`781494e6` added:

```bash
_existing_role="$(_kubectl get secret "${ARGOCD_APP_CLUSTER_SECRET_NAME}" -n "${ARGOCD_NAMESPACE}" \
  -o jsonpath='{.metadata.labels.k3d-manager/role}' 2>/dev/null || true)"
```

`_kubectl` runs through `_run_command` without `--no-exit`. When `kubectl get` fails (Secret not
found, or the current context is not the hub), `_run_command_handle_failure` calls `_err`, which
**exits** the command-substitution subshell before `|| true` runs. The substitution returns non-zero,
the assignment fails under `set -e`, and the function dies. `2>/dev/null` hides both the kubectl error
and the `_err` line. Reproduced with
`bash -c 'set -euo pipefail; f(){ exit 1; }; g(){ x="$(f 2>/dev/null || true)"; echo reached; }; g'`
(prints nothing, rc 1).

The bats test for `781494e6` stubbed `_kubectl` as a function that returns 1, never exits, so it could
not see this.

## Fix

- **F1.** Make the lookup soft and quiet:
  `_kubectl --no-exit --quiet get secret ... -o jsonpath='{...}' 2>/dev/null || true`.
  A failed lookup leaves `_existing_role` empty, so no role label is added, as for a new registration.
- **F2.** Tests in `scripts/tests/plugins/argocd_register_role_label.bats`: stub `kubectl` (the binary,
  on `PATH`) so `get secret` exits 1 and `apply` records its input, and run the registration with the
  real `_kubectl`/`_run_command`. Assert rc 0, `apply` was called, and no role label is rendered.
  Keep the existing found-label case.

## Files

- `scripts/plugins/argocd.sh`
- `scripts/tests/plugins/argocd_register_role_label.bats`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: When kubectl get of the existing cluster Secret fails, registration continues, applies the Secret without a k3d-manager/role label, and returns 0.
  - id: M2
    text: When the existing Secret has k3d-manager/role=app-cluster, the rendered Secret keeps that label (781494e6 behaviour unchanged).
must_not:
  - id: N1
    text: A failed role lookup must not end registration (red on pre-fix with the real _run_command, which exits before apply).
  - id: N2
    text: The lookup must not print kubectl errors or Secret data.
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    text: bats scripts/tests/plugins/argocd_register_role_label.bats with a PATH kubectl stub and the real _kubectl/_run_command; N1 red on 781494e6.
  - id: E2
    proves: [M1]
    kind: live
    text: The operator reruns /k3dm e2e-sandbox-provision confirm (or make up CLUSTER_PROVIDER=k3s-aws); Claude reads the job log past "cluster secret applied" and the hub Secret's age resets.
interface:
  - scripts/plugins/argocd.sh app-cluster registration function (the one that logs "[argocd] registering app cluster")
  - scripts/lib/foundation _kubectl / _run_command (--no-exit, --quiet)
```

## Definition of Done

- [ ] F1–F2 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 shown red against `781494e6`'s `argocd.sh`.
- [ ] `bats scripts/tests/plugins/argocd_register_role_label.bats scripts/tests/plugins/argocd.bats` green; shellcheck clean.
- [ ] Commit: `fix(argocd): role-label lookup must not end registration`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT modify `scripts/lib/foundation/`.
- Do NOT contact the hub or a cluster from tests.

## Verification log

- 2026-10-19: Codex (dispatcher) fix landed `a70e52a4`, using `_kubectl --no-exit --quiet`. Claude verified: the new real-`_run_command` test is red on `781494e6` (N1). Codex's "no error text printed" assertions read grep's `${output}`, not the registration's; Claude moved them before the `run grep`. A mutation that drops `--quiet` and `2>/dev/null` now turns the test red (N2). `argocd_register_role_label.bats` + `argocd.bats` green; shellcheck clean.
- 2026-10-20: independent rerun `bats scripts/tests/plugins/argocd_register_role_label.bats scripts/tests/plugins/argocd.bats` passed 41/41. `shellcheck -x scripts/plugins/argocd.sh` exited 0 with no findings. At that point live E2 was pending; it was completed by the operator's later Slack-originated run recorded below.
- 2026-10-20: operator ran Slack-originated job `05f2be6c`; `make.log` records `[argocd] registering app cluster 'ubuntu-k3s'`, `cluster secret applied`, and the `app-cluster` role label being set. E2E summary `~/.k3dm/e2e/1792538358-29202.json` reports `result=pass`, `passed=4`, `failed=0`, `total=4`, `exit_code=0`. Read-only hub check (`kubectl` context `k3d-k3d-cluster`) reports Secret `cluster-ubuntu-k3s` creation timestamp `2026-10-20T23:26:40Z` and role `app-cluster`, confirming refresh during the run. E2 passed; status is LIVE-VERIFIED.
