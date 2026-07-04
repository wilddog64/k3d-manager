# Trivy Operator ArgoCD sync stayed `Unknown` because the chart pin did not exist upstream

## What I Checked

I inspected the live ArgoCD Applications for both Trivy Operator installs and compared them to the rendered ApplicationSet source in this repo.

## Actual Output

The live Applications reported healthy workloads but unknown sync status:

```text
trivy-operator	Unknown	Healthy
acg-trivy-operator	Unknown	Healthy
```

ArgoCD then reported a comparison failure while rendering the Helm source:

```text
Failed to load target state: failed to generate manifest for source 2 of 2: rpc error: code = Unknown desc = error fetching chart: failed to fetch chart: failed running helm: `helm pull --destination /tmp/ed7c9f0a-8802-496e-b619-e12ec06127e5 --version 0.31.2 --repo https://aquasecurity.github.io/helm-charts trivy-operator` failed exit status 1: Error: chart "trivy-operator" version "0.31.2" not found in https://aquasecurity.github.io/helm-charts repository
```

The running deployment still used the older image:

```text
ghcr.io/aquasecurity/trivy-operator:0.22.0
```

## Root Cause

The ApplicationSets pinned `trivy-operator` to `0.31.2`, but that chart version is not present in the upstream Aqua Security Helm repository. ArgoCD could not render the app, so sync status stayed `Unknown` even though the existing deployment remained healthy.

## Recommended Follow-Up

- Pin both Trivy Operator ApplicationSets to a chart version that actually exists in the upstream Helm repo.
- Refresh ArgoCD after the pin change so the sync revision is recorded again.
- Keep the existing reconcile-failure observability because the operator can still hit Kubernetes/job-condition regressions even when the chart pin is valid.
