# Bug: _argocd_ensure_logged_in hangs on plaintext TLS confirmation prompt

**Date:** 2026-04-24
**Branch:** `k3d-manager-v1.1.0`
**Status:** COMPLETE (`unassigned`) — implemented in `scripts/plugins/argocd.sh`

## Problem

During `deploy_argocd`, the login helper prints:

```text
INFO: [argocd] Triggering automatic GitOps bootstrap...
INFO: [argocd] Performing automated CLI login...
INFO: [argocd] Starting background port-forward for login...
```

Then it stalls or exits with:

```text
WARNING: server is not configured with TLS. Proceed (y/n)? {"level":"fatal","msg":"EOF","time":"..."}
```

This happens because `_argocd_ensure_logged_in()` forwards Argo CD over `kubectl port-forward` to `localhost:8080`, which is plaintext HTTP, but the `argocd login` invocation still behaves as if it needs interactive confirmation.

## Root Cause

`_argocd_ensure_logged_in()` currently does:

```bash
kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8080:443 >/dev/null 2>&1 &
sleep 3
argocd login localhost:8080 --username admin --password "$pass" --insecure --grpc-web >/dev/null
```

Two issues combine here:

1. The port-forward is plaintext at `localhost:8080`.
2. The login command is non-interactive, but it does not explicitly suppress the TLS prompt / stdin interaction expected by the CLI.

The result is a prompt waiting for `y/n`, then EOF because the script is not interactive.

## Evidence

Local probe against a live port-forward on `localhost:18080`:

```text
WARNING: server is not configured with TLS. Proceed (y/n)? {"level":"fatal","msg":"EOF","time":"2026-04-24T14:42:24-07:00"}
```

The Argo CD server itself is healthy and ready, so this is not a pod/service readiness issue.

## Fix

`_argocd_ensure_logged_in()` now uses the plaintext CLI mode and closes stdin:

```bash
argocd login localhost:8080 --username admin --password "$pass" --plaintext --skip-test-tls --insecure --grpc-web </dev/null >/dev/null
```

That removes the TLS confirmation prompt and prevents the non-interactive bootstrap from hanging on stdin.

## Validation

`bats scripts/tests/plugins/argocd.bats` now includes a focused `_argocd_ensure_logged_in` test that asserts the plaintext non-interactive flags, and a live `./scripts/k3d-manager deploy_argocd --confirm` run completes past the login step.
