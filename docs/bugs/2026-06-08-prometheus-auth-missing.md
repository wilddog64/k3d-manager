# Bug: Prometheus auth missing

**Status:** CLOSED — doc merged to main in PR #93; no open follow-up was found. Not individually re-verified; reopen with a Recurrence section if it is seen again (2026-10-09 status sweep)
**Filed:** 2026-06-08
**Source:** /ask agent observation

## Description

The deploy path for `scripts/plugins/observability.sh` is reading `secret/k3d-manager/prometheus-basic-auth` too early or without a hard precondition, so the generated `prometheus-web-config` ends up empty. The fix is to guarantee the Vault secret exists before the Kubernetes secret is created, or fail the deploy instead of applying an unauthenticated config.
