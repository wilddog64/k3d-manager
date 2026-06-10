# Bug: Prometheus Operator Requires Vault Secret Object

**Filed:** 2026-06-08
**Source:** /ask agent observation

## Description

The `k3d-manager` script `observability.sh` is designed to apply an "empty config (unauthenticated)" if the `prometheus-basic-auth` Vault secret is not found. However, the Prometheus Operator's `ContainerCreating` state suggests it requires the Vault secret object (`secret/k3d-manager/prometheus-basic-auth`) to exist, even if its content is minimal or placeholder, to properly initialize its web configuration. The current script's fallback mechanism does not satisfy this requirement, leading to a degraded Prometheus stack.
