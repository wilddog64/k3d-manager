# E2E transient-resource cleanup

## Symptom

`make status` became slow/returned `Overall: UNKNOWN` while E2E/vCluster tooling was active. The
webhook process was listening, but its synchronous health sweep timed out under host load.

## Evidence

The webhook was running on `127.0.0.1:7443`, while the host showed high local virtualization and
browser CPU usage. E2E teardown called `vcluster_destroy` only; when the vCluster was already gone,
that function could return before removing the local proxy and kubeconfig. Per-run `.log` files
were also retained indefinitely even though JSON summaries are the durable audit record.

## Fix

`scripts/plugins/e2e.sh` now performs best-effort, idempotent cleanup after every run: it removes
the vCluster kubeconfig and background proxy even if destroy fails, and deletes the transient run
log while retaining the JSON summary. A BATS regression covers the orphaned-destroy path.

## Follow-up

Observe m4 CPU and webhook response latency after cleanup. If OrbStack remains saturated, keep hub
services on m4 and run E2E/vCluster workloads on m2-air.
