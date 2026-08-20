# Bug: SSM app-cluster provisioning advertises a Vault bridge that is not installed

**Filed:** 2026-08-20
**Severity:** P1 — blocks `make up CLUSTER_PROVIDER=k3s-aws` after the app cluster is provisioned

## Evidence

The app-cluster `ClusterSecretStore` is not ready:

```text
status:
  conditions:
  - message: unable to validate store
    reason: InvalidProviderConfig
    status: "False"
    type: Ready
```

The Kubernetes event identifies the failing hop:

```text
invalid vault credentials: Get "http://vault-bridge.secrets.svc.cluster.local:8201/v1/auth/token/lookup-self": dial tcp 10.43.55.100:8201: connect: connection refused
```

The `ubuntu-k3s` `vault-bridge` Endpoint points at `10.0.1.61:8201`, but the SSM-provisioned control-plane host has no `vault-bridge.service`:

```text
Failed to get unit file state for vault-bridge.service: No such file or directory
inactive
Unit vault-bridge.service could not be found.
```

The source path confirms the mismatch: `_ssm_bootstrap_k3s` ends with `Vault reverse bridge not available in SSM mode`, while `shopping_cart_create_vault_bridge` still publishes the endpoint and `shopping_cart_sync_vault_backed_secrets` waits for the resulting `ClusterSecretStore`.

## Root cause

SSM mode cannot use the SSH-only `_setup_vault_bridge` helper. The later app-cluster bootstrap nevertheless assumes the bridge listener exists, so ESO connects to a valid Service/Endpoint whose node port has no listener.

## Recommended fix

Add an SSM-native bridge setup step using `ssm_exec` (install/enable the same socat systemd unit), call it after the SSM k3s server is ready, and verify `10.0.1.61:8201` before applying/waiting on the `ClusterSecretStore`. Keep SSH behavior unchanged. Add stubbed BATS coverage for both the SSM setup and fail-fast readiness check.

## Separate lifecycle policy note

`make down CLUSTER_PROVIDER=<provider>` already performs the selected provider teardown with the provider's internal confirmation. Stale-resource cleanup is intentionally separate because it can remove unrelated expired managed registrations. Current behavior is:

```text
make down CLUSTER_PROVIDER=<provider>              # teardown only
make down CLUSTER_PROVIDER=<provider> CLEANUP_STALE=1  # teardown + guarded stale cleanup
```

Changing this to implicit stale deletion or interactive confirmation is a separate Makefile design change and should not be coupled to the ESO bridge fix.
