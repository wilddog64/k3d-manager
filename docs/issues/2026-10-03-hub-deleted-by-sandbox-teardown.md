# Incident: the local hub was deleted by a sandbox teardown (2026-10-03)

**Filed:** 2026-10-03, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** RECOVERED — hub rebuilt and reconciled; the guards below have landed. The data-restore
gap that made recovery slow is planned as the v1.43.0 DR drill.

## What happened

- **About 08:35.** The ACG sandbox stopped answering. To tear it down, Claude gave the operator
  `make down CLUSTER_PROVIDER=k3s-aws` **without `KEEP_LOCAL=1`**, and the operator ran it.
- **The hub was deleted.** `bin/cluster-down` defaulted to deleting the hub as well, so it ran
  `k3d cluster delete k3d-cluster`. That removed every hub service and dashboard, plus the Vault PVC.
- **How it was noticed.** Every hub Grafana panel errored; the operator first saw it on
  *k3dm VectorDB Health*.

Root cause and fix: [`make down` deletes the hub by default](../bugs/2026-10-03-make-down-deletes-hub-by-default.md).

## Why recovery took hours

There was no data snapshot, so everything was rebuilt and re-seeded rather than restored. Each gap
was found under pressure:

| Gap | Record |
|---|---|
| No single command restored the hub's Keychain-backed state | [hub-restore has no single make target](../bugs/2026-10-03-hub-restore-has-no-single-make-target.md) |
| No hub-only rebuild target; bare `make up` runs the full ACG path | [no make target for hub-only rebuild](../bugs/2026-10-03-no-make-target-for-hub-only-rebuild.md) |
| `hub-up` would deploy into whatever context was current | fixed in `ed22bda9` |
| The identity Application's `Replace=true` cannot update a bound PVC | [identity Replace=true](../bugs/2026-09-23-argocd-identity-replace-true-cannot-update-bound-pvc.md) |
| On a fresh Vault, the smoke-user ExternalSecret deadlocks the identity sync | [smoke-user secret lost on rebuild](../bugs/2026-10-02-smoke-user-secret-lost-on-hub-rebuild.md) |
| A root-owned logs folder silently stopped the Grafana port-forward | `bin/hub-restore` preflight now refuses root-owned state folders |
| The embeddings key's Vault copy was gone; a full VectorDB re-index took 40+ minutes | hub-restore follow-up (queued) |
| A rebuild regenerates ArgoCD's `server.secretkey`, so every API token is dead (Hermes included) | re-mint the Hermes ArgoCD token (queued) |

## What landed

| Commit | Change |
|---|---|
| `435c95a1` | `make down` keeps the hub; deleting it requires `DELETE_HUB=1` |
| `abbcfd65` | `make up CLUSTER_PROVIDER=k3d` rebuilds the hub alone |
| `ed22bda9` | `hub-up` refuses a non-hub kube context |
| `fb71deb4` | `make hub-recover` / `make hub-restore` restore Keychain-backed state in one run |
| `e08eaa83` | the identity Application uses server-side apply, so a bound PVC syncs |
| `d5b986f4` | the smoke-user Vault entry is pre-seeded before the identity sync |

## Recovery lesson: a failed identity sync does not retry by itself

After the Vault entry existed, `shopping-cart-identity` still showed `OutOfSync/Degraded`. There were
two separate reasons:

1. **ESO had not re-read Vault.** The ExternalSecret's `refreshInterval` is 15 minutes. The sync had
   run 4 seconds after the Vault write and failed. Forcing a refresh with the `force-sync=<timestamp>`
   annotation turned it `SecretSynced`.
2. **ArgoCD auto-sync does not retry a revision whose last sync failed.** Re-applying an identical
   Application does not trigger one. A manual sync operation was needed. After that, Keycloak became
   available in about 4 minutes.

The runbook steps are in
[hub-rebuild-from-gitops-vault.md](../howto/hub-rebuild-from-gitops-vault.md#identity-app-stuck-after-a-rebuild).
`d5b986f4` runs the pre-seed before the sync, but it does not force an ESO refresh. That follow-up is
recorded in the smoke-user bug doc.

## What would have made this fast

A recent, restorable copy of the hub's data: the Vault PVC, the Keycloak database and the LDAP
claims. Proving that copy restores is the
[v1.43.0 weekly hub DR drill](../plans/v1.43.0-hub-dr-drill.md).
