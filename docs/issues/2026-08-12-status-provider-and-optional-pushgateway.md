# Status provider selection and Pushgateway severity follow-up

**Date:** 2026-08-12
**Status:** Fixed in the v1.25.0 branch.

## Findings

`make status` used Make's default `CLUSTER_PROVIDER=k3s-aws` even when the active provider file
contained `k3s-hostinger`. This caused the concise health request to target the wrong provider unless
the caller explicitly supplied `CLUSTER_PROVIDER`.

The webhook health payload also reports Pushgateway connection refusal. Pushgateway is optional for the
service-health summary, so that result is classified as a yellow warning rather than a fatal service
failure. Required login failures remain red.

## Changes

- `make status` now uses `~/.local/share/k3d-manager/active-provider` when `CLUSTER_PROVIDER` was not
  explicitly supplied.
- Pushgateway connection failures are warning-level in summary and JSON modes.
- Added regression coverage for the optional Pushgateway classification.

## Verification

```text
1..4
ok 1 summary reports failed services before healthy checks
ok 2 focused service mode excludes unrelated services
ok 3 json mode contains structured statuses and no ANSI
ok 4 unknown service returns usage error
```

`make status` now selected `ubuntu-hostinger` automatically. Remaining red results are real downstream
authentication failures: Keycloak login HTTP 401, ArgoCD login HTTP 401, and Grafana login HTTP 401.
