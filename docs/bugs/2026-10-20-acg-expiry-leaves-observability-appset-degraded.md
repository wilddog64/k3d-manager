# Bug: expired ACG sandbox leaves stale Argo CD ApplicationSet observability-acg degraded

**Filed:** 2026-10-20 (operator screenshot, Argo CD ApplicationSets UI)
**Status:** OPEN — diagnosis and live verification pending
**Priority:** P2 — stale GitOps objects produce persistent degraded health after disposable sandbox expiry; cleanup/re-provisioning ownership is unclear
**Severity:** medium
**Approval:** filing requested by operator 2026-10-20; no approval to mutate live infrastructure
**Component:** ACG k3s-aws sandbox lifecycle cleanup; Argo CD ApplicationSet management on persistent hub
**Related:** `bin/cluster-down`, `bin/cleanup-stale-sandbox`, `make e2e-sandbox`; see also `docs/bugs/2026-10-18-keep-hub-down-leaves-sandbox-frontend-agents.md`
**Environment:** persistent Argo CD hub, disposable ACG AWS sandbox (`ubuntu-k3s`)

## Symptom

On 2026-10-20 the Argo CD ApplicationSets UI shows `observability-acg` with **Degraded** health, **1 Info / 2 Errors**, and the condition:

```text
application destination spec is invalid: there are no clusters with this name: ubuntu-k3s
```

The operator suspects the ACG sandbox expired and ACG purged its AWS resources. This is plausible but **not yet confirmed**. In particular, the error says Argo CD does not recognize the destination cluster name; merely losing the EC2 instance would often leave a registered but unreachable cluster. Determine whether registration was removed, the cluster secret changed, or ApplicationSet generation references an incorrect name.

## Expected

When a disposable ACG environment is confirmed destroyed, only ACG-owned Argo CD resources should be retired or suspended safely. Persistent hub/Hostinger observability must remain intact; the next ACG provision should restore the ACG GitOps applications without manual repair. Transient network failures must not trigger destructive cleanup.

## Investigation

1. Inspect the live `observability-acg` ApplicationSet, generated Applications, destination names/servers, owner references, deletion finalizers, and Argo CD registered clusters. Identify the source-of-truth GitOps path and reconciler that could recreate the set.
2. Trace the sandbox expiry/unexpected-purge path versus explicit `cluster-down` / `cleanup-stale-sandbox` / `e2e-sandbox` teardown. Determine which component owns registration and ApplicationSet cleanup.
3. Identify an authoritative signal that the disposable ACG sandbox is gone; treat API timeouts and temporary unreachability as insufficient evidence.
4. Check for any other ACG-only ApplicationSets/Applications left degraded, without broad or name-only deletion of resources shared with the hub.
5. Document whether cleanup should remove an ephemeral generated object, disable an environment-scoped generator, or change the desired-state definition so Argo CD cannot immediately recreate stale resources.

## Fix (direction; validate after investigation)

Make ACG teardown/reconciliation idempotent for both explicit shutdown and unexpected expiry. Gate cleanup on a verified gone/retired sandbox identity and an allowlist of ACG-owned GitOps resources. Respect Argo CD deletion semantics: inspect child Application finalizers and resource-pruning impact before deletion. Re-provisioning should recreate/re-register `ubuntu-k3s` and restore its observability apps. Expose cleanup outcome and reason in existing operational logs/status.

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
must_not:
  - id: N1
    text: A temporarily unreachable ubuntu-k3s cluster must not cause ApplicationSet deletion or child-resource pruning.
  - id: N2
    text: Cleanup must not delete, prune, unregister, or change hub, Hostinger, or non-ACG Argo CD resources.
  - id: N3
    text: A GitOps reconciler must not immediately recreate degraded ACG-only objects after confirmed teardown.
  - id: N4
    text: The fix must not expose generic arbitrary kubectl or Argo CD deletion through reader-level Slack/cloud-bridge endpoints.
evidence:
  - id: E1
    proves: [M2, M3, M5, N1, N2, N3, N4]
    kind: offline
    text: Stub Argo CD, sandbox identity/expiry signal, and Kubernetes API calls; cover verified expiry, transient timeout, second cleanup run, non-ACG resources, and a still-active GitOps reconciler. Prove N1/N2 fail against a deliberately unscoped deletion implementation.
  - id: E2
    proves: [M1, M2, M4, M5, N2, N3]
    kind: live
    text: On a disposable ACG sandbox, record Argo CD state before teardown, confirm sandbox removal, show no stale ACG ApplicationSets/Applications and no hub/Hostinger changes, then provision a fresh sandbox and verify observability-acg health. Run only with operator approval.
interface:
  - ACG lifecycle scripts (final owner to be determined)
  - Argo CD ApplicationSet observability-acg and its generated Applications
  - Argo CD destination cluster ubuntu-k3s
```

## Definition of Done

- [ ] Root cause and owning lifecycle paths identified and documented.
- [ ] Scoped code/tests satisfy offline acceptance; report failing pre-fix cases.
- [ ] Next operator-approved live expiration/teardown and re-provision verifies E2.
- [ ] Capture post-fix health, cleanup logs, and release/commit reference.

## What NOT to Do

- Do NOT modify or delete live ApplicationSets, Applications, cluster registrations or infrastructure as part of filing this bug.
- Do NOT run `make down`, `make e2e-sandbox`, or a live expiry test without operator approval.
- Do NOT commit directly to `main`; changes should go through a reviewed PR.
