# Issue: k3d cluster rebuild blocked by test cluster port conflict

## Date
2026-03-07

## Discovered During
OrbStack cluster teardown + rebuild validation (Task 3, v0.7.0)

## Symptom

`deploy_cluster` stalls after starting k3d agent nodes. The
`k3d-k3d-cluster-serverlb` container is created but never starts.
`deploy_cluster` hangs indefinitely waiting for the cluster API to
become available.

## Root Cause

A BATS test (`_provider_k3d_cluster_exists` or similar) left behind a
live cluster named `k3d-test-orbstack-exists`. That cluster's serverlb
held ports 8000 (HTTP) and 8443 (HTTPS). The new `k3d-cluster` serverlb
tried to bind the same ports and failed silently — Docker assigned no
ports to the container.

## Secondary Issue (also found during rebuild)

The colima VM had a stale inotify limit:

```
Failed to watch cert and key file: error creating fsnotify watcher:
too many open files
```

The k3s API server inside the cluster containers could not watch cert/key
files. Applied fix:

```bash
colima ssh -- sudo sysctl -w fs.inotify.max_user_instances=512
colima ssh -- sudo sysctl -w fs.inotify.max_user_watches=524288
```

Note: this fix is not persistent across colima VM restarts — it resets
on next `colima start`. For a permanent fix, add to colima's `lima.yaml`
or apply via a DaemonSet.

## Resolution

1. Stopped the hung background task.
2. `k3d cluster delete k3d-cluster` (removes broken partial cluster).
3. `k3d cluster delete k3d-test-orbstack-exists` (removes test artifact).
4. Applied inotify fix to colima VM.
5. Re-ran `deploy_cluster` — succeeded.

## Proper Fix

- BATS test teardown must clean up any k3d test clusters it creates.
  Investigate `_provider_k3d_cluster_exists` test in
  `scripts/tests/` to add teardown.
- inotify limit should be set persistently in colima config. Track as
  separate issue or OrbStack migration item.

## Assigned To

Gemini — BATS test teardown fix (v0.7.x backlog)
