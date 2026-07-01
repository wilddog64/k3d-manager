# Trivy Operator reconcile failure on Kubernetes 1.31

## What I Checked

I inspected the live `trivy-system` deployment, its Jobs, and the operator logs after the dashboard showed blank Trivy alert space and repeated reconcile churn.

## Actual Output

The operator logs repeatedly emitted:

```text
{"level":"error","ts":"2026-07-01T11:53:15Z","msg":"Reconciler error","controller":"job","controllerGroup":"batch","controllerKind":"Job","Job":{"name":"scan-vulnerabilityreport-56dd7499d","namespace":"trivy-system"},"error":"unrecognized scan job condition: SuccessCriteriaMet"}
```

The failed scan job also ended in:

```text
BackoffLimitExceeded
```

The running operator image was:

```text
ghcr.io/aquasecurity/trivy-operator:0.22.0
```

The ArgoCD ApplicationSet was pinned to chart revision:

```text
0.24.1
```

## Root Cause

The running Trivy Operator build is too old for the Job condition set produced on this cluster. Kubernetes 1.31 scan jobs emit `SuccessCriteriaMet`, but the deployed controller does not recognize it and logs a reconcile error instead of handling the job cleanly.

## Recommended Follow-Up

- Bump the Trivy Operator ApplicationSet pin to a current upstream release.
- Keep the Loki panel for `namespace="trivy-system"` / `controller="job"` reconcile errors so this regression is visible immediately.
- Keep the Prometheus scan-job failure path and ServiceMonitor enabled so the operator is observable even when job reconciliation is noisy.
