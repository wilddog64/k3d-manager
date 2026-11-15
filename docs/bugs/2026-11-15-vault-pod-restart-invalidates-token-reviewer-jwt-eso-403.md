# Bug: any vault-0 pod restart breaks every hub ESO store (stale pod-bound `token_reviewer_jwt`, 403 on login)

**Status:** OPEN — captured 2026-11-15
**Priority:** P2 (proposed: all hub ExternalSecrets stop refreshing and new pods that need them cannot start; manual workaround exists)
**Introduced by:** pre-existing (auth config written with a pod-bound reviewer token by `_hub_data_repoint_vault`, `scripts/plugins/hub_data.sh:847`, and `vault.sh:2106`, `:2305`)
**Should have been caught by:** deploy step
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-15
**Prior art:** `docs/issues/2026-09-11-status-warnings-hub-vault-eso-breakage.md` and `docs/bugs/2026-10-25-deploy-vault-rejected-unseal-cache-triggers-destructive-reinit.md:163` (grep `token_reviewer`) — appended as the third recurrence; the 2026-10-25 doc says "file it separately if it recurs"

## What happened (Claude, 2026-11-15, M5 hub `k3d-k3d-cluster`)

Claude deleted `secrets/vault-0` at 15:24:45Z to live-check the unseal watchdog (see
`2026-11-15-vault-unseal-watchdog-secret-shard-rejected-errors-suppressed.md`). After the operator unsealed Vault at
about 15:37Z, ESO still failed: `ClusterSecretStore vault-backend` and `identity/vault-kv-store` are
`InvalidProviderConfig: unable to create client`; the ESO controller logs
`PUT http://vault.secrets.svc:8200/v1/auth/kubernetes/login Code: 403 permission denied`. Hermes went degraded at
15:47Z (8/9, then 9/9 not synced by 16:15Z: argocd-oidc-secret, k3dm-smoke-user, keycloak-client-secrets, ...),
ArgoCD apps hub-platform-ops, hub-vectordb, shopping-cart-apps and shopping-cart-identity Degraded, and vectordb-0
cannot start without `vectordb-postgres`. Slack incident card 15:54Z.

## Cause

The Kubernetes auth config holds a `token_reviewer_jwt` read from the vault-0 pod's projected ServiceAccount token.
That token is bound to the pod object; deleting the pod invalidates it, so Vault's TokenReview call fails and every
login is denied. Vault's server log shows only the unrelated audience warning.

## Workaround

Rewrite the auth config from the new pod's token (root token via stdin, never in the exec string), as
`_hub_data_repoint_vault` does.

## Fix direction (needs spec)

Stop storing a pod-bound token: leave `token_reviewer_jwt` unset with `disable_local_ca_jwt=false`, so Vault re-reads
its own local token file on each review (prove on the deployed Vault version first), or refresh the config from the
unseal watchdog after a successful unseal. Add a post-restart ESO store check to the watchdog or Hermes.
