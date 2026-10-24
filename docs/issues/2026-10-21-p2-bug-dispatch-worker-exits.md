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

The DR freshness diagnostics worker subsequently **exited successfully**, leaving scoped changes in its isolated worktree; independent review/verification and landing are still pending. The hub-data macOS, Slack multi-job, and networked ACG workers report `terminated unexpectedly`; their supervisor logs are empty and their worktrees contain unlanded edits. No task changes were copied into the main worktree. The cluster-up recurrence triage **exited successfully** and produced a scoped report, but found no task-local job metadata; it did not establish whether the Slack notification was actually top-level.

The sixth task, `hostinger-multi-service-incident-triage`, was not started. Exact dispatcher response:

```text
[codex-dispatch] ERROR: network task acg-observability-appset-triage is still running; only one networked task at a time
```

This conflicts with the ACG task's `terminated unexpectedly` status: the network-task lock appears stale or terminal bookkeeping is missing. Do not start another network task until this is resolved.

## Root cause / follow-up

Cause is unknown. Some workers complete successfully while other workers for the same launch batch report unexpected termination without supervisor logs; the ACG task status conflicts with the network lock. The cluster-up metadata-only task returned an inconclusive finding. Review the DR task independently, and investigate worker lifecycle/supervisor terminal bookkeeping before safely recovering or resuming unfinished slugs; preserve all worktrees. Do not land partial changes, start another network task while the lock is held, or claim verification.
