# Bug: expired ACG sandbox leaves stale Argo CD ApplicationSet observability-acg degraded

**Filed:** 2026-10-20 (operator screenshot, Argo CD ApplicationSets UI)
**Status:** LIVE-VERIFIED — registration guard `bc8f2dae` and teardown lifecycle fix `d26574dc` landed; operator confirmed healthy bring-up and successful live teardown on 2026-10-21
**Fix commit:** `d26574dc`
**Priority:** P2 — stale GitOps objects produce persistent degraded health after disposable sandbox expiry; cleanup/re-provisioning ownership is unclear
**Severity:** medium
**Approval:** filing requested by operator 2026-10-20; no approval to mutate live infrastructure
**Dispatch approval:** operator requested review and dispatch on 2026-10-21; read-only investigation only, no cluster or Argo CD mutation
**Component:** ACG k3s-aws sandbox lifecycle cleanup; Argo CD ApplicationSet management on persistent hub
**Related:** `bin/cluster-down`, `bin/cleanup-stale-sandbox`, `make e2e-sandbox`; see also `docs/bugs/2026-10-18-keep-hub-down-leaves-sandbox-frontend-agents.md`
**Environment:** persistent Argo CD hub, disposable ACG AWS sandbox (`ubuntu-k3s`)

**Source-path finding (2026-10-21):** `bin/cluster-up` previously proceeded after applying the app-cluster Secret without verifying its exact persisted identity/provider/server. Its later Argo CD connection loop accepts substring matches and continues after timeout. A scoped fix now reads the Secret back and fails bring-up with an actionable expected/observed diagnostic unless it is exactly `cluster-ubuntu-k3s`, `ubuntu-k3s`, `k3s-aws`, and the configured sandbox server. This demonstrates a source invariant gap, but does not establish that it caused the observed missing live registration or that expiry caused the state. The remaining safe live repro is documented in `docs/issues/2026-10-21-acg-observability-appset-investigation.md`; live expiry/re-provision acceptance remains pending.

**Live verification attempt (2026-10-21):** ACG bring-up stopped before registration: `ubuntu@ubuntu` did not answer SSH within 180s. The chained `make down` then began deleting the CloudFormation stack. This does not verify the fix; see `docs/issues/2026-10-21-acg-live-verification-node-ssh-timeout.md`.

**Follow-up live evidence (2026-10-21):** The operator's post-teardown screenshot still shows `observability-acg` Degraded with 0 Applications. Source inspection identified the specific remaining gap: `bin/cluster-down` calls `_k3s_aws_deregister_cluster`, which removes the cluster Secret and destination-matching Applications but leaves the directly applied `ApplicationSet/observability-acg` behind. A narrow teardown/reprovision lifecycle fix is dispatched in `docs/issues/2026-10-21-acg-observability-appset-teardown-fix-spec.md`; no live resources were modified.

**Offline lifecycle fix (2026-10-21):** Confirmed AWS teardown now precedes hub deregistration in both `bin/cluster-down` and the provider `destroy_cluster` path. An unsuccessful AWS lookup/delete, or invalid AWS credentials, preserves the hub registration and `observability-acg`. After successful deletion, cleanup removes only destination-matching generated Applications and then deletes the fixed-name `ApplicationSet/observability-acg`; `--ignore-not-found` makes repeats safe. Bring-up verifies the exact persisted `cluster-ubuntu-k3s` registration before `deploy_observability_acg` reapplies the ACG set.

**Live bring-up verification (2026-10-21):** During the
operator's completed `make up CLUSTER_PROVIDER=k3s-aws`, the supplied Argo CD
ApplicationSets screenshot shows `observability-acg` with a green Healthy status
and 3 Applications. This confirms the set is present and healthy after cluster
registration. The same bring-up passed the k3s 3-node readiness step. The
operator has not run `make down`, so deletion after confirmed AWS teardown and
the full teardown/re-bring-up lifecycle are not yet live-verified. A separate
ArgoCD controller reconnect timeout warning occurred during setup but did not
prevent completion; see
`docs/issues/2026-10-21-acg-up-argocd-controller-reconnect-warning.md`.

**Live teardown verification (2026-10-21):** Operator ran
`make down CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1`. Output confirmed CloudFormation
stack deletion, then reported `Deregistered cluster-ubuntu-k3s + generated
Applications and retired ApplicationSet/observability-acg from hub ArgoCD
(cicd)`. Teardown completed with `cloud teardown: verified`; the local Hub was
preserved. Together with the preceding screenshot showing
`observability-acg` Healthy with 3 Applications after bring-up, this verifies
the live registration/re-registration and confirmed-teardown cleanup paths.
The operator then supplied a post-teardown Argo CD screenshot:
`observability-acg` is absent, and the remaining displayed ApplicationSets are
Healthy. This visually confirms the retired set no longer appears in the hub UI.

**Live evidence:** 2026-10-21 · run operator-tmux-make-down · env k3s-aws · scenario confirmed-stack-teardown-retires-appset · commit d26574dc · proves fix

Argo CD normally cascades ApplicationSet deletion to owned Applications, and an Application's `resources-finalizer.argocd.argoproj.io` can then prune its managed resources ([ApplicationSet deletion documentation](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Application-Deletion/)). This cleanup first removes the finalizer from Applications matching the retired ACG destination and deletes those Applications, so their managed resources are not pruned by Argo CD. The cluster has already been confirmed deleted. The fixed ApplicationSet delete is namespace scoped and can only target `observability-acg`; Hub, Hostinger, `grafana-dashboards-acg`, and unrelated resources are not selected. A Kubernetes deletion error is surfaced as a deregistration warning and is safe to retry.

## Files

- `docs/bugs/2026-10-20-acg-expiry-leaves-observability-appset-degraded.md`
- `docs/issues/2026-10-21-acg-observability-appset-investigation.md`
- `docs/issues/2026-10-21-acg-observability-appset-triage-spec.md`
- `docs/issues/2026-10-21-acg-observability-appset-teardown-fix-spec.md`

## Symptom

On 2026-10-20 the Argo CD ApplicationSets UI shows `observability-acg` with **Degraded** health, **1 Info / 2 Errors**, and the condition:

```text
application destination spec is invalid: there are no clusters with this name: ubuntu-k3s
```

The operator suspects the ACG sandbox expired and ACG purged its AWS resources. This is plausible but **not yet confirmed**. In particular, the error says Argo CD does not recognize the destination cluster name; merely losing the EC2 instance would often leave a registered but unreachable cluster. Determine whether registration was removed, the cluster secret changed, or ApplicationSet generation references an incorrect name.

## Additional evidence: existing Alertmanager detection (2026-10-20)

The operator received an Alertmanager notification reporting **[1] Firing** with:

```yaml
alertname: TargetDown
cluster: acg
job: federate-acg
prometheus: monitoring/kube-prometheus-stack-prometheus
severity: warning
summary: One or more targets are unreachable.
description: 100% of the federate-acg/ targets in namespace are down.
```

This confirms that monitoring and alert delivery detect loss of the ACG federation target. **There is no observed automatic cleanup invocation following this alert.** The missing integration is an alert-to-verification-to-remediation workflow, not basic detection. Neither the alert nor Argo CD's missing-cluster error alone proves sandbox expiration; corroborate with authoritative sandbox lifecycle state.

## Expected

When a disposable ACG environment is confirmed destroyed, only ACG-owned Argo CD resources should be retired or suspended safely. Persistent hub/Hostinger observability must remain intact; the next ACG provision should restore the ACG GitOps applications without manual repair. Transient network failures must not trigger destructive cleanup.

## Investigation

1. Inspect the live `observability-acg` ApplicationSet, generated Applications, destination names/servers, owner references, deletion finalizers, and Argo CD registered clusters. Identify the source-of-truth GitOps path and reconciler that could recreate the set.
2. Trace the sandbox expiry/unexpected-purge path versus explicit `cluster-down` / `cleanup-stale-sandbox` / `e2e-sandbox` teardown. Determine which component owns registration and ApplicationSet cleanup.
3. Identify an authoritative signal that the disposable ACG sandbox is gone; treat API timeouts and temporary unreachability as insufficient evidence.
4. Check for any other ACG-only ApplicationSets/Applications left degraded, without broad or name-only deletion of resources shared with the hub.
5. Document whether cleanup should remove an ephemeral generated object, disable an environment-scoped generator, or change the desired-state definition so Argo CD cannot immediately recreate stale resources.
6. Trace Alertmanager routing for `TargetDown` (`cluster=acg`, `job=federate-acg`), existing Hermes/dispatcher integration, and `cleanup-stale-sandbox` behavior. Identify how to trigger verification without granting a generic cluster mutation endpoint.

## Fix (direction; validate after investigation)

Make ACG teardown/reconciliation idempotent for both explicit shutdown and unexpected expiry. Gate cleanup on a verified gone/retired sandbox identity and an allowlist of ACG-owned GitOps resources. Respect Argo CD deletion semantics: inspect child Application finalizers and resource-pruning impact before deletion. Re-provisioning should recreate/re-register `ubuntu-k3s` and restore its observability apps. Expose cleanup outcome and reason in existing operational logs/status.

Reuse `bin/cleanup-stale-sandbox` or existing lifecycle logic if it can be safely scoped, rather than duplicating teardown code. Accept a validated, allowlisted ACG-specific alert as a **verification request**, not an authorization to delete. The remediation dispatcher must independently confirm destruction for the same sandbox identity, deduplicate repeated firing alerts, serialize cleanup per identity, record the outcome, and safely retry/recover partial cleanup. If verification is unavailable or inconclusive, leave resources unchanged and record the reason. Do not let an alert from an old sandbox delete resources belonging to a newly provisioned sandbox.

Do not introduce a generic destructive `/k3dm` or cloud-bridge command as a prerequisite; if remote mutation is later needed, design it as a separate explicitly authorized, fixed-scope operation.

## Acceptance

```yaml
must:
  - id: M1
    text: Confirm and document why observability-acg reports no cluster named ubuntu-k3s after ACG expiry, distinguishing missing registration from mere network unreachability.
  - id: M2
    text: After authoritative confirmation of sandbox destruction, the lifecycle cleanup retires or disables only stale ACG-owned Argo CD objects and prevents immediate recreation while the sandbox is absent.
  - id: M3
    text: Cleanup is idempotent across repeated calls and handles already-absent Applications, ApplicationSets and cluster registrations.
  - id: M4
    text: On the next ACG provision, cluster registration and ACG observability desired state are recreated successfully without manual Argo CD intervention.
  - id: M5
    text: Cleanup logs the target sandbox identity, decisions, actions and results so an operator can distinguish expiry cleanup from transient errors.
  - id: M6
    text: An authenticated and validated Alertmanager TargetDown notification for cluster=acg and job=federate-acg can trigger a sandbox lifecycle verification request via the existing dispatcher/Hermes path (or an equivalently constrained handler).
  - id: M7
    text: Only after independent confirmation that the matching ACG sandbox identity was destroyed does the dispatcher invoke allowlisted, scoped, idempotent stale-resource cleanup, preferably reusing existing cleanup-stale-sandbox logic.
  - id: M8
    text: Repeated firing alerts for the same expired sandbox identity are deduplicated and cleanup is serialized; partially failed cleanup can be retried safely, and stale notifications cannot affect a replacement sandbox.
must_not:
  - id: N1
    text: A temporarily unreachable ubuntu-k3s cluster must not cause ApplicationSet deletion or child-resource pruning.
  - id: N2
    text: Cleanup must not delete, prune, unregister, or change hub, Hostinger, or non-ACG Argo CD resources.
  - id: N3
    text: A GitOps reconciler must not immediately recreate degraded ACG-only objects after confirmed teardown.
  - id: N4
    text: The fix must not expose generic arbitrary kubectl or Argo CD deletion through reader-level Slack/cloud-bridge endpoints.
  - id: N5
    text: A TargetDown notification, Argo CD Degraded status, or federation scrape failure alone must not authorize cleanup without authoritative expiry/destruction evidence.
  - id: N6
    text: Duplicate alerts, malformed/untrusted alerts, and notifications belonging to prior sandbox identities must not cause concurrent, repeated destructive operations or cleanup of a new sandbox.
evidence:
  - id: E1
    proves: [M2, M3, M5, M8, N1, N2, N3, N4, N6]
    kind: offline
    text: Stub Argo CD, sandbox identity/expiry signal, and Kubernetes API calls; cover verified expiry, transient timeout, second cleanup run, non-ACG resources, and a still-active GitOps reconciler. Prove N1/N2 fail against a deliberately unscoped deletion implementation.
  - id: E3
    proves: [M6, M7, M8, N5, N6]
    kind: offline
    text: Integration test feeds a validated TargetDown alert through notification handling and a stubbed Hermes/dispatcher, authoritative sandbox-state check and cleanup executor; assert alert-to-verification-to-cleanup-to-audit on confirmed expiry. Simulate a transient outage, inconclusive state, duplicate firing alerts, malformed alerts, overlapping execution and a late alert for the previous sandbox; assert no unauthorized cleanup. Demonstrate N5 failure under a naive alert-direct-delete implementation.
  - id: E2
    proves: [M1, M2, M4, M5, N2, N3]
    kind: live
    text: On a disposable ACG sandbox, record Argo CD state before teardown, confirm sandbox removal, show no stale ACG ApplicationSets/Applications and no hub/Hostinger changes, then provision a fresh sandbox and verify observability-acg health. Run only with operator approval.
interface:
  - ACG lifecycle scripts (final owner to be determined)
  - Argo CD ApplicationSet observability-acg and its generated Applications
  - Argo CD destination cluster ubuntu-k3s
  - Alertmanager TargetDown labels cluster=acg, job=federate-acg
  - Hermes/dispatcher verification-to-cleanup integration (implementation owner to be determined)
```

## Definition of Done

- [ ] Root cause and owning lifecycle paths identified and documented.
- [ ] Scoped code/tests satisfy offline acceptance, including E3 alert integration and negative safety tests; report failing pre-fix cases.
- [ ] Next operator-approved live expiration/teardown and re-provision verifies E2.
- [ ] Capture post-fix health, cleanup logs, and release/commit reference.

## What NOT to Do

- Do NOT modify or delete live ApplicationSets, Applications, cluster registrations or infrastructure as part of filing this bug.
- Do NOT run `make down`, `make e2e-sandbox`, or a live expiry test without operator approval.
- Do NOT commit directly to `main`; changes should go through a reviewed PR.
