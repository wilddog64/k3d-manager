# Bug: Prometheus auth missing

**Filed:** 2026-06-08
**Source:** /ask agent observation

## Description

The deploy path for `scripts/plugins/observability.sh` is reading `secret/k3d-manager/prometheus-basic-auth` too early or without a hard precondition, so the generated `prometheus-web-config` ends up empty. The fix is to guarantee the Vault secret exists before the Kubernetes secret is created, or fail the deploy instead of applying an unauthenticated config.
