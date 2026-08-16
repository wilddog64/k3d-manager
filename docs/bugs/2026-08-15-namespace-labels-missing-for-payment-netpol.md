# Bugfix: v1.25.0 — namespace labels missing for payment NetworkPolicy selectors

**Branch:** `k3d-manager-v1.25.0`
**Files:** `services/shopping-cart-namespace/namespace.yaml`, `scripts/etc/argocd/applicationsets/data-git.yaml`

---

## Problem

On a NetworkPolicy-enforcing CNI (Cilium on k3s-aws — the self-contained Tier 2
sandbox), the payment service cannot reach PostgreSQL/RabbitMQ and the order
service cannot reach payment. The payment `default-deny-all` policy is only
opened by companion policies whose `namespaceSelector`s match labels that the
deployed namespaces **never carry**:

- `allow-to-postgresql` / `allow-to-rabbitmq` (egress) select the data namespace
  by `app.kubernetes.io/component: data`.
- `allow-from-order-service` (ingress) selects the apps namespace by
  `app.kubernetes.io/name: shopping-cart` **and**
  `app.kubernetes.io/component: application`.

(See `shopping-cart-payment/k8s/base/networkpolicy.yaml`.)

But on the deployed path:

- **`shopping-cart-data`** is created by the `data-git` ApplicationSet via the
  ArgoCD `CreateNamespace=true` sync option — a **bare** namespace carrying only
  `kubernetes.io/metadata.name`. No `component: data` label → payment egress to
  Postgres/RabbitMQ is denied. (Observed live 2026-08-15: payment Flyway
  migration blocked until `kubectl label ns shopping-cart-data
  app.kubernetes.io/component=data` was applied by hand.)
- **`shopping-cart-apps`** is created by the k3d-manager namespace app
  (`services/shopping-cart-namespace/namespace.yaml`), which stamps
  `part-of`/`managed-by`/`istio.io/dataplane-mode` but **not**
  `app.kubernetes.io/name: shopping-cart` or
  `app.kubernetes.io/component: application` → payment ingress from order is
  denied.

The canonical, fully-labeled manifest **does** exist
(`shopping-cart-infra/namespaces/namespaces.yaml`) but is orphaned config: the
`data-git` appset sources `path: data-layer`, not `namespaces`, and the k3d-manager
namespace app is a divergent partial copy. Neither deployed path applies the
canonical labels.

**Root cause:** the deployed namespace manifests omit the
`app.kubernetes.io/component` / `app.kubernetes.io/name` labels that the payment
NetworkPolicy selectors require; the omission is masked on default-CNI clusters
(k3d/OrbStack) that don't enforce NetworkPolicy, and only bites on Cilium.

This is substrate-independent and safe everywhere — the labels are semantic
metadata the policies already expect. It is filed separately from the Tier 2
harness codification (which handles the *environment-specific* URL/gateway/JWK
overrides that are production-correct and must not change in the app repos).

---

## Reproduction

1. Deploy the shopping-cart stack to a Cilium-enforcing cluster (Tier 2 k3s-aws
   sandbox) via the `data-git` + `services-git` appsets.
2. `kubectl -n shopping-cart-data get ns shopping-cart-data -o
   jsonpath='{.metadata.labels}'` → no `app.kubernetes.io/component`.
3. Payment pod stalls: Flyway cannot reach `postgresql.shopping-cart-data:5432`
   (egress denied by `default-deny-all`, `allow-to-postgresql` never matches).
4. Order → payment calls fail (ingress denied; `allow-from-order-service` never
   matches the apps namespace).

---

## Fix

### Change 1 — `services/shopping-cart-namespace/namespace.yaml`: stamp the apps-namespace labels

**Exact old block:**

```yaml
  name: shopping-cart-apps
  labels:
    app.kubernetes.io/part-of: shopping-cart
    app.kubernetes.io/managed-by: argocd
    istio.io/dataplane-mode: ambient
```

**Exact new block:**

```yaml
  name: shopping-cart-apps
  labels:
    app.kubernetes.io/name: shopping-cart
    app.kubernetes.io/part-of: shopping-cart
    app.kubernetes.io/component: application
    app.kubernetes.io/managed-by: argocd
    istio.io/dataplane-mode: ambient
```

### Change 2 — `scripts/etc/argocd/applicationsets/data-git.yaml`: label the ArgoCD-created data namespace

Add `managedNamespaceMetadata` so the namespace ArgoCD creates via
`CreateNamespace=true` carries `component: data`. This is the ArgoCD-native way
to label a namespace the appset owns (supported since ArgoCD 2.5; sandbox runs
argo-cd 10.1.4).

**Exact old block:**

```yaml
      syncPolicy:
        automated:
          prune: false
          selfHeal: true
          allowEmpty: false
        syncOptions:
          - CreateNamespace=true
```

**Exact new block:**

```yaml
      syncPolicy:
        managedNamespaceMetadata:
          labels:
            app.kubernetes.io/name: shopping-cart
            app.kubernetes.io/part-of: shopping-cart
            app.kubernetes.io/component: data
        automated:
          prune: false
          selfHeal: true
          allowEmpty: false
        syncOptions:
          - CreateNamespace=true
```

---

## Files Changed

| File | Change |
|------|--------|
| `services/shopping-cart-namespace/namespace.yaml` | Add `name: shopping-cart` + `component: application` labels to `shopping-cart-apps` |
| `scripts/etc/argocd/applicationsets/data-git.yaml` | Add `managedNamespaceMetadata.labels` (`component: data`) so the ArgoCD-created `shopping-cart-data` namespace is labeled |

---

## Rules

- No other files touched. This is the label gap **only** — the payment
  URL/gateway/JWK substrate overrides are the Tier 2 harness codification's job
  (`docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md`), not this bugfix.
- Do NOT modify `shopping-cart-infra/namespaces/namespaces.yaml` (already correct;
  separate repo; not on the deployed path).
- YAML must remain valid: `kubectl kustomize services/shopping-cart-namespace`
  renders clean; the appset stays a valid ApplicationSet.

---

## Definition of Done

- [ ] `shopping-cart-apps` namespace carries `app.kubernetes.io/name=shopping-cart`
      and `app.kubernetes.io/component=application`.
- [ ] `data-git` appset stamps `app.kubernetes.io/component=data` on the created
      `shopping-cart-data` namespace via `managedNamespaceMetadata`.
- [ ] `kubectl kustomize services/shopping-cart-namespace` renders without error.
- [ ] Committed and pushed to `k3d-manager-v1.25.0`.
- [ ] memory-bank updated with commit SHA and task status.

**Commit message (exact):**
```
fix(netpol): stamp component/name labels so payment NetworkPolicies match
```

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than the two listed targets.
- Do NOT commit to `main` — work on `k3d-manager-v1.25.0`.
- Do NOT touch the shopping-cart-* repos — this fix is entirely in k3d-manager.

---

## Related

- `docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md` — the harness that surfaced
  this live; it handles the *environment* overrides (order URLs, payment
  gateway=stripe, JWK public issuer), which are production-correct and stay in the
  harness, not the app repos.
- `shopping-cart-payment/k8s/base/networkpolicy.yaml` — the selectors this fix
  satisfies.
