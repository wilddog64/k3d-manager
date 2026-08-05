# Trivy alert `app ''` notification diagnosis

## Finding

The `app ''` value is a notification-label/template mismatch, not proof that
completed scan pods are the source of the alert.

The live Prometheus alert series contain `namespace` and `image_repository`, for
example `monitoring/prometheus/prometheus`, `cicd/argoproj/argocd`, and
`identity/keycloak/keycloak`; they do not contain an `app` label. The rule groups
by `namespace, image_repository`:

```promql
sum by (namespace, image_repository) (
  trivy_image_vulnerabilities{severity="Critical"}
) > 0
```

Completed scan pods do exist, but the alert series prove the current firing
notifications are also backed by ordinary monitored images. Deleting completed
pods would not fix the empty `app` rendering and could hide useful scan history.

## Recommendation

Keep the alert grouping by namespace/repository and update the notification
template to use `image_repository` (or add an explicit alert label derived from
it) instead of assuming `app`. Treat completed-pod TTL cleanup as a separate
maintenance improvement, not the alert fix. Validate any alert-rule change
against the live `ALERTS` labels before deployment.

## Re-verification — 2026-08-04

The live rule is now deployed in `cicd/argocd-degraded` and evaluates
`trivy_vulnerability_inventory{severity="CRITICAL"}`, grouped by
`cluster`, `namespace`, and `image_repository`.  It sets the compatibility
label `app: "{{ $labels.image_repository }}"`.

The live Prometheus API reported 39 firing
`TrivyCriticalVulnerabilityDetected` alerts and `empty_app_alerts=0`.
Each checked alert had an `app` value equal to its `image_repository`, including
`wilddog64/shopping-cart-order`, `wilddog64/shopping-cart-payment`,
`argoproj/argocd`, and `aquasec/trivy`.

Trivy's completed scan Jobs are present, but this is expected maintenance
behavior: every inspected Job has `ttlSecondsAfterFinished: 3600` and was less
than ten minutes old. The operator configuration also sets
`OPERATOR_SCAN_JOB_TTL: "1h"`. Therefore no cleanup bug is open: shortening
or deleting these Jobs would not resolve an empty `app` notification and would
reduce useful scan-job diagnostics.
