# Dispatch spec: ACG ApplicationSet destination registration lifecycle

Investigate and, only if a source defect is demonstrated, fix the ACG app-cluster registration path that left `observability-acg` targeting `ubuntu-k3s` while Argo CD had no cluster registered under that name. The live evidence does not establish sandbox expiry; the ACG stack was present at the later inspection. Treat this as a registration/re-provision reconciliation issue, not authorization for automatic cleanup.

## Scope

- Trace `bin/cluster-up`, `register_app_cluster`, `deploy_observability_acg`, and `bin/cluster-down` to determine whether a successful ACG bring-up guarantees the exact Argo CD cluster registration consumed by the `observability-acg` ApplicationSet.
- Check how the live `ubuntu-k3s-app-cluster` Secret (`data.name=k3d-cluster`, provider `k3d`) can coexist with the missing expected `cluster-ubuntu-k3s` / `ubuntu-k3s` registration.
- If a code-path defect is demonstrated, implement the smallest idempotent correction and focused BATS regression tests. Make bring-up fail with an actionable diagnostic rather than report success if its required registration invariant is absent or mismatched.
- If no repository defect is demonstrated, make no source-code changes; write the evidence and exact remaining live repro needed to the investigation issue.

## Safety boundaries

- No live AWS, Kubernetes, or Argo CD mutations; no provisioning, teardown, sync, apply, refresh annotation, delete, prune, or registration changes.
- Do not add automatic expiry cleanup, alert-triggered mutation, or a generic destructive command.
- Do not treat a missing/unreachable API as proof that the sandbox is destroyed.
- Preserve all non-ACG cluster registrations and hub/Hostinger resources.

## Files

- `bin/cluster-up` (only if a code defect is demonstrated)
- `scripts/plugins/argocd.sh` (only if a code defect is demonstrated)
- `scripts/tests/bin/cluster_up.bats` and/or focused Argo CD BATS suite
- `docs/issues/2026-10-21-acg-observability-appset-investigation.md`
- `docs/bugs/2026-10-20-acg-expiry-leaves-observability-appset-degraded.md`

## Acceptance

- Establish whether the current source guarantees an Argo CD registration named `ubuntu-k3s` with provider `k3s-aws` before the ACG observability ApplicationSet is deployed.
- If a defect exists, add a regression test that fails before the fix and passes after it; preserve idempotency and fail closed on missing/mismatched registration.
- If a defect cannot be established, report that clearly and specify a safe live observation that would distinguish stale runtime state from a source defect.
- Run the focused BATS suite, ShellCheck for any changed shell files, `git diff --check`, and `_agent_audit`.

## Rules

- `bats scripts/tests/bin/cluster_up.bats`
- `bats scripts/tests/plugins/argocd.bats`
- `shellcheck bin/cluster-up scripts/plugins/argocd.sh` (if either shell file changes)
- `git diff --check`
- `_agent_audit`
