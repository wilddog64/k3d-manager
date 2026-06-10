# Bug: `acg-kube-prometheus-stack-operator` pod stuck in `ContainerCreating`

**Filed:** 2026-06-08
**Source:** /ask agent observation

## Description

The `acg-kube-prometheus-stack-operator` pod in the `monitoring` namespace is in a `0/1 ContainerCreating` state. This indicates an issue with its initialization, such as missing resources (e.g., PersistentVolumeClaims), image pull failures, or insufficient permissions. This needs to be investigated to ensure the Prometheus stack is fully operational.
