# Issue: imagePullSecrets refactor validation blocked by GitHub DNS resolution

**Branch:** `k3d-manager-v1.4.10`
**Related spec:** `docs/plans/v1.4.10-refactor-services-imagepullsecrets.md`

## What was tested

- `shellcheck -S warning bin/acg-up`
- `kubectl kustomize services/shopping-cart-basket/`
- `kubectl kustomize services/shopping-cart-frontend/`
- `kubectl kustomize services/shopping-cart-order/`
- `kubectl kustomize services/shopping-cart-payment/`
- `kubectl kustomize services/shopping-cart-product-catalog/`

## Actual output

`shellcheck -S warning bin/acg-up`:

```text
<no output; command succeeded>
```

`kubectl kustomize services/shopping-cart-basket/`:

```text
error: accumulating resources: accumulation err='accumulating resources from 'https://github.com/wilddog64/shopping-cart-basket//k8s/base?ref=main': Get "https://github.com/wilddog64/shopping-cart-basket//k8s/base?ref=main": dial tcp: lookup github.com: no such host': failed to run '/opt/homebrew/bin/git fetch --depth=1 https://github.com/wilddog64/shopping-cart-basket main': fatal: unable to access 'https://github.com/wilddog64/shopping-cart-basket/': Could not resolve host: github.com
: exit status 128
```

`kubectl kustomize services/shopping-cart-frontend/`:

```text
error: accumulating resources: accumulation err='accumulating resources from 'https://github.com/wilddog64/shopping-cart-frontend//k8s/base?ref=main': Get "https://github.com/wilddog64/shopping-cart-frontend//k8s/base?ref=main": dial tcp: lookup github.com: no such host': failed to run '/opt/homebrew/bin/git fetch --depth=1 https://github.com/wilddog64/shopping-cart-frontend main': fatal: unable to access 'https://github.com/wilddog64/shopping-cart-frontend/': Could not resolve host: github.com
: exit status 128
```

`kubectl kustomize services/shopping-cart-order/`:

```text
error: accumulating resources: accumulation err='accumulating resources from 'https://github.com/wilddog64/shopping-cart-order//k8s/base?ref=main': Get "https://github.com/wilddog64/shopping-cart-order//k8s/base?ref=main": dial tcp: lookup github.com: no such host': failed to run '/opt/homebrew/bin/git fetch --depth=1 https://github.com/wilddog64/shopping-cart-order main': fatal: unable to access 'https://github.com/wilddog64/shopping-cart-order/': Could not resolve host: github.com
: exit status 128
```

`kubectl kustomize services/shopping-cart-payment/`:

```text
error: accumulating resources: accumulation err='accumulating resources from 'https://github.com/wilddog64/shopping-cart-payment//k8s/base?ref=main': Get "https://github.com/wilddog64/shopping-cart-payment//k8s/base?ref=main": dial tcp: lookup github.com: no such host': failed to run '/opt/homebrew/bin/git fetch --depth=1 https://github.com/wilddog64/shopping-cart-payment main': fatal: unable to access 'https://github.com/wilddog64/shopping-cart-payment/': Could not resolve host: github.com
: exit status 128
```

`kubectl kustomize services/shopping-cart-product-catalog/`:

```text
error: accumulating resources: accumulation err='accumulating resources from 'https://github.com/wilddog64/shopping-cart-product-catalog//k8s/base?ref=main': Get "https://github.com/wilddog64/shopping-cart-product-catalog//k8s/base?ref=main": dial tcp: lookup github.com: no such host': failed to run '/opt/homebrew/bin/git fetch --depth=1 https://github.com/wilddog64/shopping-cart-product-catalog main': fatal: unable to access 'https://github.com/wilddog64/shopping-cart-product-catalog/': Could not resolve host: github.com
: exit status 128
```

## Root cause

`kubectl kustomize` needs to fetch the remote `https://github.com/wilddog64/.../k8s/base?ref=main` resources, but this workspace cannot resolve `github.com`.

## Recommended follow-up

- Re-run the kustomize checks in an environment with outbound DNS/network access to GitHub.
