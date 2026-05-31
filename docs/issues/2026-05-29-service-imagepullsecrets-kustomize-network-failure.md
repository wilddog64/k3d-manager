# Service imagePullSecrets kustomize validation: initial sandbox DNS failure

## What I tested

Validated the four service overlays after adding `imagePullSecrets` patches for named ServiceAccounts.

## Attempted command

```bash
kubectl kustomize services/shopping-cart-basket
kubectl kustomize services/shopping-cart-order
kubectl kustomize services/shopping-cart-payment
kubectl kustomize services/shopping-cart-product-catalog
```

## Actual output

Initial sandbox-run output:

```text
error: accumulating resources: accumulation err='accumulating resources from 'https://github.com/wilddog64/shopping-cart-basket//k8s/base?ref=main': Get "https://github.com/wilddog64/shopping-cart-basket//k8s/base?ref=main": dial tcp: lookup github.com: no such host': failed to run '/opt/homebrew/bin/git fetch --depth=1 https://github.com/wilddog64/shopping-cart-basket main': fatal: unable to access 'https://github.com/wilddog64/shopping-cart-basket/': Could not resolve host: github.com
: exit status 128
```

## Root cause

The sandbox could not resolve `github.com` while `kubectl kustomize` tried to fetch the remote base manifests.

## Follow-up

Reran the same `kubectl kustomize` checks with escalated network access. All four overlays rendered successfully and showed `imagePullSecrets:
- name: ghcr-pull-secret` on the named ServiceAccounts.
