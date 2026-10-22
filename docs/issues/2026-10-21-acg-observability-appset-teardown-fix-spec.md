# Dispatch spec: retire the stale ACG observability ApplicationSet

**Purpose:** Fix the confirmed lifecycle gap where `observability-acg` remains in the persistent hub after ACG teardown, degraded against missing destination `ubuntu-k3s`.
**Related bug:** `docs/bugs/2026-10-20-acg-expiry-leaves-observability-appset-degraded.md`
**Evidence:** Operator screenshot on 2026-10-21 shows `observability-acg` Degraded with 0 Applications. Source inspection shows `bin/cluster-down` calls `_k3s_aws_deregister_cluster`; that helper deletes `cluster-ubuntu-k3s` and destination-matching Applications but does not delete `ApplicationSet/observability-acg`. The ApplicationSet is directly applied from `scripts/etc/argocd/applicationsets/observability-acg.yaml`, without a parent owner that would remove it automatically.

## Implementation record

Teardown ordering is: verify AWS credentials and stack state; delete the CloudFormation stack and confirm success; remove the ACG cluster Secret; clear finalizers and delete Applications whose destination is `ubuntu-k3s` (or the exact registered server); then delete only `ApplicationSet/observability-acg` in the Argo CD namespace. Failed lookup/delete or invalid credentials skip all hub deregistration, preserving the set. `--ignore-not-found` makes successful cleanup repeatable. Bring-up applies the observability ApplicationSet only after `argocd_require_app_cluster_registration` verifies the expected Secret identity, provider, and server.

Argo CD's default ApplicationSet deletion cascades to its owned Applications; an Application resource finalizer may cascade further and prune workloads. Existing deregistration explicitly clears finalizers on destination-matching Applications before deleting them, so those cluster resources are not pruned by Argo CD. This is safe only after confirmed CloudFormation deletion. A failure to delete the named ApplicationSet returns a cleanup error/warning; retry is safe. No live Argo CD or AWS operation was performed.

### Offline gate results (2026-10-21)

- `bats scripts/tests/bin/cluster_down.bats`: **34/34 passed**.
- `bats scripts/tests/plugins/argocd.bats`: **40/40 passed**.
- Focused bring-up ordering test: `ok 1 acg-up verifies exact ACG registration before deploying observability`.
- `bats scripts/tests/bin/cluster_up.bats`: **66/67 passed**. The remaining existing local-socket fixture failed because this sandbox denies loopback bind; exact failure:

```text
not ok 66 acg-up Vault port cleanup kills the listener but not a connected client such as an ssh -R tunnel
# (from function `_start_vault_port_fixture' in file scripts/tests/bin/cluster_up.bats, line 1060,
#  in test file scripts/tests/bin/cluster_up.bats, line 1075)
#   `_start_vault_port_fixture' failed
# Traceback (most recent call last):
#   File "<string>", line 2, in <module>
#     s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",0)); s.listen(4)
#                                                                               ~~~~~~^^^^^^^^^^^^^^^^^
# PermissionError: [Errno 1] Operation not permitted
# cat: /tmp/bats-run-GU7Zin/test/66/port: No such file or directory
```

- `shellcheck -S warning bin/cluster-down bin/cluster-up scripts/lib/providers/k3s-aws.sh scripts/tests/bin/cluster_down.bats`: clean. ShellCheck on `scripts/tests/plugins/argocd.bats` reports existing warnings at lines 6, 157, 176, and 179 (SC1090, SC2034, SC2154).
- `git diff --check`: clean. `make check-doc-links`: `check-doc-links: 2293 file(s) OK`.
- `./scripts/k3d-manager _agent_audit`: exit 0 (`running under bash version 5.3.20(1)-release`). This audit reads staged diffs; the requested working-tree-only changes were deliberately not staged, so the command did not inspect these edits.

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
