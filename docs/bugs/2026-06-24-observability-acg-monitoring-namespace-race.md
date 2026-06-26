# Bug: ACG observability creates monitoring secrets before the target namespace exists

**Filed:** 2026-06-24
**Type:** bugfix
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`
**Files:** `scripts/plugins/observability.sh`, `bin/cluster-up`

## Problem

`acg-up` fails during the observability step with:

```text
INFO: [acg-up] Step 14/14 — Deploying ACG observability (Prometheus + Trivy)...
INFO: [observability] Deploying ACG observability stack...
applicationset.argoproj.io/observability-acg configured
INFO: [observability] ACG ApplicationSet applied — ArgoCD will sync monitoring/trivy-system on ubuntu-k3s
INFO: [observability] Reading Alertmanager credentials from Vault...
Error from server (NotFound): error when creating "STDIN": namespaces "monitoring" not found
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
```

Two things were wrong:

1. The ACG observability path assumed `ubuntu-k3s` instead of resolving the active app-cluster context.
2. The code tried to create `monitoring/alertmanager-smtp-secret` immediately after applying the
   ApplicationSet, before ArgoCD had created the namespace.

That makes the path brittle on non-aws k3s providers such as Hostinger, where the app-cluster
context should remain `ubuntu-hostinger`.

## Root Cause

`scripts/plugins/observability.sh::deploy_observability_acg()` hardcoded `ubuntu-k3s` for the secret
apply path and `bin/cluster-up` hardcoded `ubuntu-k3s` for the ACG port-forward path. The
ApplicationSet uses `CreateNamespace=true`, but that only takes effect when ArgoCD syncs the app,
not at the instant the shell script continues to the secret creation command.

## Fix

- Resolve the active app-cluster context dynamically via `_acg_resolve_provider` +
  `_acg_provider_context`.
- Ensure `monitoring` exists on that context before creating Alertmanager and Prometheus secrets.
- Use the same resolved context for the ACG Prometheus port-forward and Pushgateway LaunchAgent.

## Verification

- `python3 -m py_compile bin/k3dm-webhook` is not relevant to this bug.
- `scripts/tests/lib/observability.bats` was updated to pin provider context in tests.
- Final validation still needs `shellcheck` and `_agent_audit` after the patch is committed.

## Follow-up

- Keep the ACG observability path provider-aware so Hostinger remains supported without special
  casing.
