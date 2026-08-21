# Bug: `bin/acg-sync-apps` still uses the interactive ArgoCD login path

**Date:** 2026-04-24
**Branch:** `k3d-manager-v1.1.0`
**Status:** COMPLETE (`c3a2f146`)
**Files:** `bin/acg-sync-apps`

## Problem

`bin/acg-sync-apps` reaches the ArgoCD port-forward successfully, then dies at the login step.
The preserved port-forward log shows the local endpoint is healthy:

```text
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080
Handling connection for 8080
```

The script then runs:

```bash
argocd login localhost:8080 --username admin --password "${_argocd_pass}" --insecure >/dev/null
```

That call still uses the older login shape and does not match the non-interactive flags already
used in `scripts/plugins/argocd.sh`.

## Root Cause

`bin/acg-sync-apps` has its own ArgoCD login path instead of reusing the hardened helper from
`scripts/plugins/argocd.sh`.

`_argocd_ensure_logged_in()` already uses:

```bash
argocd login localhost:8080 --username admin --password "$pass" --plaintext --skip-test-tls --insecure --grpc-web </dev/null >/dev/null
```

But `bin/acg-sync-apps` still calls `argocd login` without `--plaintext`, `--skip-test-tls`,
`--grpc-web`, or closed stdin. That leaves it exposed to the same TLS confirmation / EOF behavior
that was already fixed for ArgoCD bootstrap.

## Evidence

Observed live log file under `./scratch/logs/`:

```text
scratch/logs/acg-sync-apps-argocd-pf.XXXXXX.log
```

That log only contains port-forward traffic and readiness probes. The failure happens after the
port-forward is ready, during the ArgoCD CLI login step.

## Recommended Fix

Align `bin/acg-sync-apps` with the non-interactive ArgoCD login flags used by
`_argocd_ensure_logged_in()`, or reuse that helper directly if the dependency boundary allows it.
Either way, the login path should not depend on stdin or interactive TLS confirmation.

## Impact

Medium. `make sync-apps` stops after the port-forward is ready, which blocks the sync flow and
leaves the user with no useful progress past the ArgoCD login phase.

## Validation

`shellcheck -x bin/acg-sync-apps` passes, `bats scripts/tests/bin/acg_sync_apps.bats` passes,
and the login invocation now includes `--plaintext --skip-test-tls --insecure --grpc-web </dev/null`.
