# Dispatcher status false negative when process inspection is restricted

**Date:** 2026-10-22
**Branch:** `k3d-manager-v1.43.5`
**Tasks:** `cluster-lifecycle-thread-recurrence-fix`, `hostinger-multi-service-incident-attribution`

## Observation

Both dispatcher starts created isolated, in-scope worktrees. An ordinary status
check reported both as unexpectedly terminated, despite empty supervisor logs
and no `exit` marker:

```text
task: cluster-lifecycle-thread-recurrence-fix
state: terminated unexpectedly (see /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/cluster-lifecycle-thread-recurrence-fix.run/supervisor.log)
scope: in-scope

task: hostinger-multi-service-incident-attribution
state: terminated unexpectedly (see /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/hostinger-multi-service-incident-attribution.run/supervisor.log)
network: yes
scope: in-scope
```

The shell denied process inspection:

```text
zsh:1: operation not permitted: ps
```

Rerunning the dispatcher status commands with the required process-inspection
permission reported both workers running:

```text
task: cluster-lifecycle-thread-recurrence-fix
state: running
scope: in-scope

task: hostinger-multi-service-incident-attribution
state: running
network: yes
scope: in-scope
```

## Impact and follow-up

This was a process-visibility false negative, not evidence of task failure. The
worktrees were preserved; neither task was resumed or restarted. The dispatcher
status path relies on `ps` to compare process start times, so a restricted `ps`
can classify an active worker as terminated. Future diagnosis should rerun the
read-only status check in an execution context with process visibility before
resuming or redispatching.
