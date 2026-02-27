# Issue: `test_istio` failure — Hardcoded namespace in check

## Date
2026-02-27

## Environment
- Hostname: `m4-air.local`
- OS: Darwin (macOS)
- Cluster Provider: `orbstack`

## Symptoms
`test_istio` fails with the following error even if Istio is working:

```
INFO: Checking for Istio sidecar...
ERROR: Istio sidecar was not injected! Check your Istio installation.
```

## Root Cause
In `scripts/lib/test.sh` (line 178), the check for the `istio-proxy` sidecar uses a hardcoded namespace `-n istio-test` instead of the dynamic `$test_ns` variable:

```bash
    # Verify that the Istio proxy has been injected
    _info "Checking for Istio sidecar..."
    if _kubectl --no-exit get pod -n istio-test -o yaml | grep -q istio-proxy; then
```

If `ISTIO_TEST_NAMESPACE` is not set, `test_ns` defaults to a random name like `istio-test-123456789-12345`. The check then looks in the (likely non-existent or empty) `istio-test` namespace instead of the one where the test pod was actually deployed.

There are several other occurrences of hardcoded `istio-test` in the same function. Verified line numbers:

| Line | Hardcoded reference |
|---|---|
| 188 | `_kubectl --no-exit get pod -n istio-test -o yaml` |
| 207 | `_kubectl apply -f - -n istio-test` |
| 212 | `namespace: istio-test` (inside heredoc) |
| 228 | `namespace: istio-test` (inside heredoc) |
| 243 | `_kubectl --no-exit get gateway -n istio-test test-gateway` |

**Note:** Line 275 contains a second function with `local test_ns="${1:-istio-test}"`. This default may also need updating depending on whether the caller always passes `$test_ns` explicitly.

## Resolution (2026-02-27)
- Updated `scripts/lib/test.sh:test_istio` so every manifest apply, resource check, and sidecar verification uses the dynamically generated `$test_ns`. Both the Gateway and VirtualService now inherit the same namespace instead of `istio-test`.
- Cleanup helper `_cleanup_istio_test_namespace` continues to accept the namespace via the trap (callers always pass `$test_ns`).
- Validated locally via `PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test_istio` — sidecar detection succeeds and the gateway route test reaches nginx through Istio.

## Evidence
The test output showed:
`namespace/istio-test-1772155134-17302 created`
But the check failed shortly after.
