# Issue: Hostinger data-layer and app secrets were missing until ArgoCD re-applied the ExternalSecrets

## What was observed

During the same `2026-07-08` incident window, Hostinger app workloads were failing behind the public `502`s because the data/app/payment secrets were absent even though the `ClusterSecretStore` was healthy.

Initial live state:

```text
$ kubectl --context ubuntu-hostinger -n shopping-cart-data get secret
NAME               TYPE                             DATA   AGE
ghcr-pull-secret   kubernetes.io/dockerconfigjson   1      23d
```

```text
$ kubectl --context ubuntu-hostinger -n shopping-cart-data describe pod postgresql-orders-0
Error: secret "postgres-orders-admin" not found
```

```text
$ kubectl --context ubuntu-hostinger -n shopping-cart-apps describe pod frontend-6495c6db9c-p4kmx
FailedToRetrieveImagePullSecret ... Unable to retrieve some image pull secrets (ghcr-pull-secret)
failed to authorize ... ghcr.io/token ... 401 Unauthorized
```

ArgoCD app status at that point showed the desired `ExternalSecret` objects as tracked but `OutOfSync`:

```text
$ kubectl --context k3d-k3d-cluster -n cicd get application data-layer -o yaml
...
  - group: external-secrets.io
    kind: ExternalSecret
    name: postgres-orders-admin
    namespace: shopping-cart-data
    status: OutOfSync
...
  - group: external-secrets.io
    kind: ExternalSecret
    name: payment-gateway-secrets
    namespace: shopping-cart-payment
    status: OutOfSync
...
  - group: external-secrets.io
    kind: ExternalSecret
    name: order-service-secrets
    namespace: shopping-cart-apps
    status: OutOfSync
```

## What happened next

ArgoCD controller logs later showed a partial sync at `2026-07-08T12:00:25Z` that explicitly applied all of the missing `ExternalSecret` resources:

```text
Applying resource ExternalSecret/postgres-orders-admin in cluster: https://2.25.146.252:6443, namespace: shopping-cart-data
Applying resource ExternalSecret/payment-gateway-secrets in cluster: https://2.25.146.252:6443, namespace: shopping-cart-payment
Applying resource ExternalSecret/order-service-secrets in cluster: https://2.25.146.252:6443, namespace: shopping-cart-apps
...
externalsecret.external-secrets.io/postgres-orders-admin configured
externalsecret.external-secrets.io/payment-gateway-secrets configured
externalsecret.external-secrets.io/order-service-secrets configured
...
Updated sync status: OutOfSync -> Synced
```

After that resync, the cluster recovered:

```text
$ kubectl --context ubuntu-hostinger -n shopping-cart-data get externalsecret,secret,pods
externalsecret.external-secrets.io/postgres-orders-admin         ... SecretSynced   True
...
secret/postgres-orders-admin                                     Opaque   1   5m41s
...
pod/postgresql-orders-0                                          1/1     Running
```

```text
$ kubectl --context ubuntu-hostinger -n shopping-cart-apps get externalsecret,secret,pods
externalsecret.external-secrets.io/ghcr-pull-secret              ... SecretSynced   True
...
pod/frontend-684f6c4fcb-4bvxf                                    1/1     Running
```

## Current understanding

This was not a Vault/ESO connectivity failure:

- `ClusterSecretStore/vault-backend` was `Ready=True`
- the `ExternalSecret` manifests existed in `shopping-cart-infra`
- the controller was eventually able to apply them successfully without any manifest change

The still-open question is why those `ExternalSecret` resources were absent long enough to surface as public `502`s before ArgoCD eventually re-applied them.

## Follow-up

If this recurs, inspect:

- `argocd-application-controller` logs around `data-layer`
- whether a prior app refresh left `data-layer` partially applied before the `ExternalSecret` phase
- whether any controller restart or cluster-registration step delayed the Hostinger destination refresh before the `12:00:25Z` partial sync
