# Issue: Cannot run Hostinger + ACG AWS clusters simultaneously — vault-backend ClusterSecretStore never Ready on k3s-aws

**Date:** 2026-07-07
**Component:** acg-up / vault-bridge / ESO ClusterSecretStore (k3s-aws context)
**Status:** Filed (RCA from codex thread)

## Symptom

`make up CLUSTER_PROVIDER=k3s-aws` fails at Step 9/12 waiting for the
`vault-backend` ClusterSecretStore to become `Ready` on the `ubuntu-k3s`
remote cluster. All three 90s reconcile attempts time out (270s total) and
`acg-up` aborts:

```
INFO:  [shopping_cart] Waiting for ClusterSecretStore vault-backend to be Ready on ubuntu-k3s...
WARN:  [shopping_cart] ClusterSecretStore vault-backend not Ready after 90s (attempt 1/3) — forcing reconcile...
WARN:  [shopping_cart] ClusterSecretStore vault-backend not Ready after 90s (attempt 2/3) — forcing reconcile...
WARN:  [shopping_cart] ClusterSecretStore vault-backend not Ready after 90s (attempt 3/3) — forcing reconcile...
ERROR: [shopping_cart] ClusterSecretStore vault-backend never became Ready after 3 attempts (270s total)
WARN:  [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
ERROR: make up CLUSTER_PROVIDER=k3s-aws exited 2
```

The failure is specific to bringing up the ACG AWS cluster while the
Hostinger cluster is already up — both providers wire the same
`vault-bridge` Endpoints/Service in the `secrets` namespace, but only one
cluster can own the localhost:18200 Vault tunnel and the associated
`vault-bridge` Endpoints IP at a time.

## Investigation

From job `d7447e8b` log:

- Step 6: `vault-bridge` Endpoints created pointing to `10.0.1.74:8201` and
  `vault-bridge` Service applied in the `secrets` namespace on
  `ubuntu-k3s`.
- Step 8: ESO v1.0.0 installed cleanly; webhook ready after ~100s.
- Step 9: `ClusterSecretStore/vault-backend` applied against
  `ubuntu-k3s`, but never reports `Ready=True`. ESO cannot reach Vault
  through the `vault-bridge` Service — the `10.0.1.74:8201` endpoint is
  reachable only from the Hostinger reverse-tunnel path, not from the AWS
  cluster's pod network.
- Vault port-forward on the workstation is a single launchd agent
  (`com.k3d-manager.vault-port-forward`) bound to `localhost:18200` and
  tied to whichever cluster `acg-up` last configured — Hostinger currently
  owns it.

## Root Cause (per codex RCA)

The Vault access path from a remote cluster back to the workstation Vault
is single-tenant:

1. Only one `com.k3d-manager.vault-port-forward` launchd agent exists,
   bound to `localhost:18200`, targeting the k3d Vault pod in one cluster
   context at a time.
2. The `vault-bridge` Endpoints IP in the remote cluster's `secrets`
   namespace is hard-wired to a single reverse-tunnel egress IP
   (`10.0.1.74:8201` here), which is valid for exactly one remote cluster.
3. ESO's ClusterSecretStore on the second cluster (k3s-aws) therefore
   cannot reach Vault, times out, and `acg-up` fails.

We do not yet have a design that lets Hostinger and ACG AWS both hold a
concurrent, distinct Vault bridge — the launchd agent, the endpoints IP,
and the `vault-bridge` Service name collide.

## Fix Applied

None — filing only. Codex produced the RCA above; the redesign has not
been scoped yet. Immediate workaround: only bring up one remote cluster at
a time. `acg-down CLUSTER_PROVIDER=hostinger` before running
`make up CLUSTER_PROVIDER=k3s-aws`, and vice versa.

## Notes

- Related: `docs/issues/2026-04-28-clustersecretstore-vault-bridge-pod-traffic-empty-reply.md`
- Related: `docs/issues/2026-04-28-vault-bridge-same-port-reverse-tunnel-reset.md`
- Related project: `project_app_cluster_vault_auth_portability.md` — the
  "kubecontext-keyed helper for every provider; Vault endpoint is the
  open seam" line item is exactly this seam. Multi-cluster concurrency
  should be tracked there.
- Follow-up scope: per-context launchd agent name + per-context
  `vault-bridge` Endpoints IP + per-context ClusterSecretStore identity,
  so Hostinger and ACG AWS can both hold a live Vault bridge without
  collision.
