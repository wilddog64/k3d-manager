# P2 bug dispatch attempt — workers exit unexpectedly

## What was dispatched

After commit `c218ff47` was pushed to `origin/k3d-manager-v1.43.5`, dispatcher start created isolated worktrees for:

- `hub-data-bats-macos-sha256sum-p2`
- `dr-drill-freshness-diagnostics-p2`
- `slack-multi-job-thread-targeting-p2`
- `cluster-up-thread-recurrence-triage`
- `acg-observability-appset-triage` (networked, read-only)

## Actual status output

```text
task: hub-data-bats-macos-sha256sum-p2
state: terminated unexpectedly (see /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/hub-data-bats-macos-sha256sum-p2.run/supervisor.log)
 M scripts/tests/plugins/hub_data.bats
scope: in-scope
task: dr-drill-freshness-diagnostics-p2
state: terminated unexpectedly (see /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/dr-drill-freshness-diagnostics-p2.run/supervisor.log)
 D scripts/etc/dr/drill-freshness.sh
scope: in-scope
task: slack-multi-job-thread-targeting-p2
state: terminated unexpectedly (see /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/slack-multi-job-thread-targeting-p2.run/supervisor.log)
scope: in-scope
task: cluster-up-thread-recurrence-triage
state: terminated unexpectedly (see /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/cluster-up-thread-recurrence-triage.run/supervisor.log)
scope: in-scope
task: acg-observability-appset-triage
state: terminated unexpectedly (see /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/acg-observability-appset-triage.run/supervisor.log)
network: yes
scope: in-scope
```

Three non-network implementation workers and the networked ACG worker ultimately report `terminated unexpectedly`; their supervisor logs are empty and their worktrees contain unlanded partial edits. No partial task edits were landed or copied into the main worktree. The cluster-up recurrence triage subsequently **exited successfully** and produced a scoped report, but found no task-local job metadata; it did not establish whether the Slack notification was actually top-level.

The sixth task, `hostinger-multi-service-incident-triage`, was not started. Exact dispatcher response:

```text
[codex-dispatch] ERROR: network task acg-observability-appset-triage is still running; only one networked task at a time
```

This conflicts with the ACG task's `terminated unexpectedly` status: the network-task lock appears stale or terminal bookkeeping is missing. Do not start another network task until this is resolved.

## Root cause / follow-up

Cause is unknown. The dispatcher reports unexpected termination without a supervisor log while task worktrees show partial modifications; the cluster-up metadata-only task did complete and returned an inconclusive finding. Investigate worker lifecycle/supervisor terminal bookkeeping and safely recover or resume the exact unfinished slugs before retrying; preserve all worktrees. Do not land partial changes, dispatch another network task, or claim verification.
