# Issue: v1.11.0 P3 live in-cluster Vault naming could not be verified on `ubuntu-hostinger`

## What was tested / attempted

Attempted the spec-mandated live verification for Change 4 against the reachable `ubuntu-hostinger`
context to confirm:

- the in-cluster Vault Service name
- the root token Secret name/key

Commands run:

```text
kubectl --context ubuntu-hostinger -n secrets get svc vault
kubectl --context ubuntu-hostinger -n secrets get secret vault-root -o jsonpath='{.data.root_token}'
kubectl --context ubuntu-hostinger -n secrets get svc
kubectl --context ubuntu-hostinger -n secrets get secret
```

## Actual output

```text
Error from server (NotFound): services "vault" not found
Error from server (NotFound): secrets "vault-root" not found
NAME                       TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
external-secrets-webhook   ClusterIP   10.43.22.245   <none>        443/TCP    32h
vault-bridge               ClusterIP   10.43.74.228   <none>        8201/TCP   2d12h
NAME                       TYPE     DATA   AGE
external-secrets-webhook   Opaque   4      32h
vault-token                Opaque   1      2d12h
```

## Root cause if known

`ubuntu-hostinger` is reachable, but it does not currently have the P2b-provisioned in-cluster Vault
objects present in `secrets`. The cluster still shows the bridge-era `vault-bridge` Service and
`vault-token` Secret instead of a live in-cluster `vault` Service plus `vault-root` Secret.

## Recommended follow-up

Provision the in-cluster Vault on `ubuntu-hostinger` with `vault_deploy_hub_into_context` and then
re-run the live verification for:

- Service name in `${VAULT_NS:-secrets}`
- root token Secret name/key

Until that verification is redone, `vault_seed_hub_into_context` keeps the spec’s assumed names:
`svc/vault` and `secret/vault-root` key `root_token`.
