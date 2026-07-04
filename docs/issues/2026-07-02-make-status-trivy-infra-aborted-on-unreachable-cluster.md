# `make status` aborted in the Trivy infra section when clusters were unreachable

## What I tested

I ran:

```bash
make status CLUSTER_PROVIDER=k3s-hostinger
```

## Actual output

Before the fix, the command stopped immediately after the Trivy infra header and exited nonzero:

```text
=== Trivy Infra Security ===
INFO: [observability] Trivy infra security summary — Hub (k3d-k3d-cluster):
make: *** [status] Error 1
```

That made `make status` look broken even when the problem was only that the hub cluster or Prometheus backend was unreachable.

## Root cause

The new Trivy infra reporting path was still running inside `set -e` shell context. When the hub Prometheus query could not be satisfied, the command substitution in the report path could terminate the script before the report helper finished rendering its fallback text.

## Fix

`scripts/plugins/observability.sh` now treats the Trivy infra report as best-effort:

- `_trivy_prom_query()` returns an empty payload instead of aborting when Prometheus cannot be reached.
- `_trivy_infra_security_report_for_context()` temporarily disables `errexit` while it probes and renders the report, then restores the caller’s shell mode.

## Verification

After the fix, `make status CLUSTER_PROVIDER=k3s-hostinger` completes and prints the Trivy infra fallbacks instead of aborting:

```text
=== Trivy Infra Security ===
INFO: [observability] Trivy infra security summary — Hub (k3d-k3d-cluster):
INFO: [observability]   (no cluster compliance metrics found)
INFO: [observability]   (no High/Critical infra RBAC findings found)
INFO: [observability] Trivy infra security summary — ACG (ubuntu-hostinger):
INFO: [observability]   (no cluster compliance metrics found)
INFO: [observability]   (no High/Critical infra RBAC findings found)
```
