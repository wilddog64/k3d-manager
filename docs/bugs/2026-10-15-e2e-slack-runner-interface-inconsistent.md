# P3 — Slack E2E command interface is inconsistent across execution environments

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.5` (triage 2026-10-15, operator-approved placement)
**Priority:** P3 — operator-facing command contract / interface consistency
**Status:** OPEN — interface gap verified, design change proposed; no implementation
**Approval:** operator explicitly requested appropriate bug filing on 2026-10-15

## Operator observation

During an active AWS ACG sandbox session, Slack command `k3dm e2e-remote RUNNER=acg` was rejected:

```
ERROR: [e2e-remote] runner 'acg' not in allowlist (m2)
make: *** [e2e-remote] Error 1
```

The operator reasonably expected a single Slack-accessible E2E command with runner selection (`m2`, `m4`, `aws`). From the Slack user's perspective **all executions happen remotely**, including those running on the webhook host/m4. The current distinction between `e2e-remote` and `e2e-sandbox` exposes implementation topology rather than operator intent.

Separately, `e2e-sandbox` attempted to install Argo CD over an existing AWS provisioned cluster and failed on CRD Helm ownership; this separate P2 issue remains tracked in `docs/bugs/2026-10-15-e2e-sandbox-argocd-crd-helm-ownership-conflict.md`.

## Confirmed current implementation

- `scripts/plugins/e2e_remote.sh` defaults `E2E_RUNNER_ALLOWLIST` to `m2`; the `e2e_runner_dispatch` implementation uses m2-specific SSH, paths, kubeconfig, locking, and result collection. Simply extending the allowlist to `aws` or `m4` **would not** implement those adapters.
- `scripts/plugins/e2e.sh` implements a separate `e2e-sandbox` flow targeting `ubuntu-k3s`, with its own setup and reporting paths.
- Both are exposed as operator-visible Make/Slack targets, forcing the operator to know internal transport details.

This is classified as a **P3 interface/design bug (enhancement-scale remediation)**, not a claim that the deliberately restricted m2 runner is itself malfunctioning.

## Expected unified operator contract

Prefer one stable command:

```text
k3dm e2e-remote RUNNER=m2
k3dm e2e-remote RUNNER=m4
k3dm e2e-remote RUNNER=aws
```

`RUNNER` selects an approved execution adapter; in a future version an optional separate `TARGET` could identify the environment under test. **Do not conflate execution host with test target.** A Slack caller should not need to distinguish local-vs-remote *relative to the webhook server*.

## Required design and migration work

1. Audit the current `e2e-remote`, `e2e-sandbox`, webhooks, Make target contracts, help output, bridge allowlist, and artifact/metrics paths. Document current supported roles, confirmations, resource prerequisites, and exact semantics of runner/target.
2. Define explicit validated runner enumeration `m2|m4|aws`, with a dispatch adapter for each: `m2` SSH/dedicated runner; `m4` local execution under a controlled job; `aws` approved ACG Kubernetes execution. Preserve current operational safety guarantees and deny unknown runners.
3. Reuse existing implementations as internal adapters instead of duplicating E2E setup, Git revision synchronization, health checks or report publishing. Avoid automatically patching Argo CD CRD ownership or reinstalling an existing healthy Argo CD.
4. Define predictable sandbox policy: already running AWS cluster is reused; absent cluster receives an explicit, policy-approved provision/deny decision with clear cost and destructive-operation boundaries. No implicit AWS spin-up merely because a user selected `RUNNER=aws` unless explicitly approved.
5. Standardize correlation and results: request/job ID, runner, target, source Git SHA/branch, test exit status, duration, artifacts, and durable Grafana metrics. Provide a meaningful Slack result regardless of adapter, with proper thread correlation.
6. Preserve backwards compatibility during a deprecation window: `e2e-sandbox` may become a thin wrapper or documented alias, with warning and migration guidance; do not abruptly remove existing users, automations, or cloud-bridge callers.
7. Preserve concurrency isolation, role-based authorization, bounded job runtime, redaction, non-destructive defaults and safe recovery after interruptions. Avoid opening arbitrary remote shell/SSH or unrestricted Kubernetes execution.
8. Decide implementation release after checking the roadmap and enhancement cap. The previously planned v1.45.2 release has five enhancement specs allocated; **do not silently add this as a sixth**. Candidate future slot v1.46.0 subject to operator/maintainer prioritization.

## Acceptance criteria

- All three `k3dm e2e-remote RUNNER=m2|m4|aws` requests dispatch to the correct validated adapter (using mocked infrastructure in tests); each retains distinct target semantics.
- Running `RUNNER=aws` against a provisioned healthy sandbox does not reinstall or hijack Argo CD ownership.
- Unsupported runner and unavailable substrate return actionable, accurate errors; approved existing AWS substrate is reused.
- Slack help and documentation advertise one preferred interface; alias remains compatible as specified.
- All adapters publish consistently correlated, redacted outcomes/artifacts to the existing reporting pipeline.
- Deterministic regression tests cover runner selection, denied permissions, races, timeout, error handling, result forwarding and absence of inadvertent cloud provisioning.

**Implementation:** not started. Bug filing made no change to Make targets, infrastructure, Helm releases or E2E jobs.
