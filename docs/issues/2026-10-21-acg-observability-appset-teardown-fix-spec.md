# Dispatch spec: retire the stale ACG observability ApplicationSet

**Purpose:** Fix the confirmed lifecycle gap where `observability-acg` remains in the persistent hub after ACG teardown, degraded against missing destination `ubuntu-k3s`.
**Related bug:** `docs/bugs/2026-10-20-acg-expiry-leaves-observability-appset-degraded.md`
**Evidence:** Operator screenshot on 2026-10-21 shows `observability-acg` Degraded with 0 Applications. Source inspection shows `bin/cluster-down` calls `_k3s_aws_deregister_cluster`; that helper deletes `cluster-ubuntu-k3s` and destination-matching Applications but does not delete `ApplicationSet/observability-acg`. The ApplicationSet is directly applied from `scripts/etc/argocd/applicationsets/observability-acg.yaml`, without a parent owner that would remove it automatically.

## Task

Investigate and implement a safe, idempotent lifecycle for the ACG-only `observability-acg` ApplicationSet so it does not remain stale/degraded after a confirmed ACG teardown, and so a later successful ACG bring-up restores it after the destination cluster has been registered. Keep the fix restricted to this ACG lifecycle; do not add alert-driven cleanup or generic deletion interfaces in this task.

Before changing code, inspect Argo CD ApplicationSet deletion/cascade/finalizer behavior and the existing teardown ordering. Preserve the current safety distinction between confirmed AWS stack deletion and failed/inconclusive teardown: a failed or uncertain teardown must not retire the ApplicationSet as though the sandbox were gone. Ensure teardown remains idempotent when the set or generated Applications are already absent. Ensure bring-up does not apply the set before the expected `ubuntu-k3s` cluster registration is verified.

## Acceptance

- Add focused offline regression tests for: confirmed teardown retires only `observability-acg`; failed/inconclusive teardown preserves it; repeated teardown is safe; a later bring-up re-applies it only after successful expected cluster registration.
- Do not delete or mutate hub, Hostinger, `grafana-dashboards-acg`, or other non-target Argo CD resources.
- Do not perform live kubectl/Argo CD/AWS mutations or claim live verification.
- Document exact lifecycle ordering and any Argo CD pruning/finalizer limitation in the related bug/investigation record.
- Run focused BATS suites, ShellCheck for touched shell files, `git diff --check`, `_agent_audit`, and doc-link checks; leave implementation changes in the isolated task worktree for independent verification.

## Allowed implementation scope

- `bin/cluster-down`
- `bin/cluster-up`
- `scripts/lib/providers/k3s-aws.sh`
- `scripts/plugins/argocd.sh` (only if needed for a fixed-name, fixed-namespace helper)
- Focused tests under `scripts/tests/bin/` and `scripts/tests/plugins/`
- The related bug and investigation documents above

No live infrastructure, cluster state, credentials, or other ApplicationSets are in scope.

## Files

- `bin/cluster-down`
- `bin/cluster-up`
- `scripts/lib/providers/k3s-aws.sh`
- `scripts/plugins/argocd.sh`
- `scripts/tests/bin/cluster_down.bats`
- `scripts/tests/bin/cluster_up.bats`
- `scripts/tests/plugins/argocd.bats`
- `docs/bugs/2026-10-20-acg-expiry-leaves-observability-appset-degraded.md`
- `docs/issues/2026-10-21-acg-observability-appset-teardown-fix-spec.md`
