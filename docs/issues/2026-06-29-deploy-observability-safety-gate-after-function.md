# Issue: `deploy_observability` completes work but still exits via the dispatcher safety gate

## What was attempted

Ran the live hub observability deploy twice while validating the Image Updater Grafana fix:

```text
./scripts/k3d-manager deploy_observability
```

## Actual output

```text
running under bash version 5.3.15(1)-release
INFO: [observability] Deploying Hub observability stack...
applicationset.argoproj.io/observability configured
INFO: [observability] Hub ApplicationSet applied — ArgoCD will sync monitoring/trivy-system
INFO: [observability] Reading Alertmanager credentials from Vault...
secret/alertmanager-smtp-secret unchanged
INFO: [observability] Alertmanager config secret created
INFO: [observability] PrometheusRules applied from /Users/cliang/src/gitrepo/personal/k3d-manager/scripts/etc/prometheus/rules/
INFO: [observability] Removed stale shopping-cart-rules ArgoCD Application
INFO: [observability] Istio Gateway + VirtualServices applied (prometheus/grafana.shopping-cart.local)
INFO: [observability] ArgoCD/Image Updater dashboard applied on k3d-k3d-cluster
INFO: [observability] Loki/Promtail log shipper applied on k3d-k3d-cluster
Safety gate: rerun with explicit options or pass --confirm to apply defaults.
Dry-run requests (--dry-run/-n) bypass the confirmation gate.
```

## Observed behavior

The function did the intended work:

- hub `observability` ApplicationSet updated
- hub Grafana dashboard ConfigMap applied
- hub promtail DaemonSet applied

But the overall command still exited non-zero after printing the generic safety-gate
message.

## Root cause

Not diagnosed in this task. The behavior appears to be in the dispatcher/wrapper path
around `./scripts/k3d-manager deploy_observability`, not in the observability plugin
logic itself.

## Recommended follow-up

Trace the dispatcher confirmation/safety-gate path for direct function invocations and
confirm why `deploy_observability` falls through to the generic warning after the plugin
already ran successfully.
