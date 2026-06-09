# Bug Report: Prometheus Operator requires Vault secret even for unauthenticated setup

## Issue
The `acg-kube-prometheus-stack` is in a `Degraded` state, with the `acg-kube-prometheus-stack-operator` pod stuck in `ContainerCreating`. This prevents the Prometheus stack from deploying correctly.

## Observed Behavior / Terminal Output

During `acg-up`, the following warning was observed:
```
WARN: [observability] Prometheus basic auth Vault secret not found — applying empty config (unauthenticated)
```

The `acg-status` command showed:
```
*Pods (ACG)* — 30/31 ready
```monitoring  acg-kube-prometheus-stack-operator-847bc9569c-jc6lg  0/1  ContainerCreating```

*ACG ArgoCD apps:*
```acg-kube-prometheus-stack       Synced      Degraded
acg-trivy-operator              Synced      Healthy
ubuntu-k3s-platform             Synced      Healthy```
```

My previous analysis confirmed:
```
The `acg-kube-prometheus-stack` is in a `Degraded` state because the `acg-kube-prometheus-stack-operator` pod is stuck in `ContainerCreating`. This indicates a likely misconfiguration or missing dependency preventing the operator from starting.

The root cause appears to be the unprovisioned Prometheus basic authentication secret in Vault. The `acg-up` job logs show a warning: `WARN: [observability] Prometheus basic auth Vault secret not found — applying empty config (unauthenticated)`. While an empty configuration might be intended for unauthenticated access, the Prometheus Operator's initialization process likely expects a well-formed secret to exist, even if its content is minimal. The absence or malformation of this expected secret can prevent the operator pod from successfully transitioning out of the `ContainerCreating` state.
```

## Root Cause
The `k3d-manager` script `scripts/plugins/observability.sh` explicitly handles the case where the `prometheus-basic-auth` Vault secret is not found by applying an "empty config (unauthenticated)". However, the Prometheus Operator, which is a downstream dependency, appears to require the `prometheus-basic-auth` secret to be formally provisioned in Vault, even if its content is minimal or empty, for its successful initialization. The operator's pod gets stuck in `ContainerCreating` because it expects this secret to exist, despite the `k3d-manager`'s fallback logic.

This is not a regression in the `k3d-manager` script's logic, but rather an incompatibility between the script's intended unauthenticated setup and the Prometheus Operator's startup requirements.

## Recommended Follow-up
1.  **Provision the secret in Vault:** Ensure the `prometheus-basic-auth` secret is properly provisioned in Vault, even if it contains minimal or placeholder values (e.g., empty username/password), *before* the `acg-kube-prometheus-stack` is deployed.
2.  **Update `k3d-manager` script:** Modify `scripts/plugins/observability.sh` to explicitly create an empty `prometheus-basic-auth` secret in Vault if it does not already exist, rather than relying solely on the "applying empty config" fallback. This would satisfy the Prometheus Operator's requirement for the secret's presence.
