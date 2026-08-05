# Shopping-cart hub Applications were invalid due to missing project destinations

## What was tested

Queried the three ArgoCD Applications shown as Unknown and the live `shopping-cart` AppProject. Checked tracking annotations on the hub identity resources before changing project permissions.

## Actual output

```text
application destination server 'https://kubernetes.default.svc' and namespace 'cicd'
do not match any of the allowed destinations in project 'shopping-cart'

application destination server 'https://kubernetes.default.svc' and namespace 'identity'
do not match any of the allowed destinations in project 'shopping-cart'

application destination server 'https://kubernetes.default.svc' and namespace 'istio-system'
do not match any of the allowed destinations in project 'shopping-cart'
```

The live Keycloak, LDAP, PostgreSQL, Services, and ExternalSecrets carry
`argocd.argoproj.io/tracking-id` values owned by `shopping-cart-identity`, so removing the Application would have risked pruning live identity resources.

## Root cause

The `shopping-cart` AppProject was later restricted to app-cluster namespaces but omitted the original Hub destinations used by the app-of-apps, identity, and networking Applications. All three Applications therefore remained InvalidSpec/Unknown since 2026-07-20.

## Fix and verification

`ae266bae` adds only these Hub destinations to `scripts/etc/argocd/projects/shopping-cart.yaml.tmpl`:

```text
https://kubernetes.default.svc / cicd
https://kubernetes.default.svc / identity
https://kubernetes.default.svc / istio-system
```

The rendered AppProject was applied and the three Applications hard-refreshed. Final result:

```text
shopping-cart-apps sync=Synced health=Healthy
shopping-cart-identity sync=Synced health=Healthy
shopping-cart-networking sync=Synced health=Healthy
```

## Follow-up: legacy `shopping-cart-rules` card

The later `shopping-cart-rules` card is unrelated to the three destination repairs.
It is a resource-free legacy Application that the current observability plugin already
removes because Prometheus rules are applied directly. Deleting it live showed that its
parent immediately recreated it from `shopping-cart-infra/argocd/applications/monitoring-rules.yaml`:

```text
argocd.argoproj.io/tracking-id: shopping-cart-apps:argoproj.io/Application:cicd/shopping-cart-rules
```

`shopping-cart-infra` commit `c558834` deletes only that obsolete manifest. It merged as
PR #88 (`fbc382e`); after a hard refresh, the parent Application pruned the stale card
and `kubectl get application shopping-cart-rules -n cicd` returned `NotFound`. No
PrometheusRule was removed because the direct `deploy_observability` path remains the
rule owner.

`shopping-cart-identity` was already `Synced Healthy`; its red UI marker was an old
2026-07-20 failed operation. A normal sync completed successfully after the project
permission repair and replaced it with `operation=Succeeded`.
