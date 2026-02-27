# Jenkins Smoke Test TLS Retry Failure

**Date:** 2026-02-27
**Status:** ✅ Fixed

## Summary

`deploy_jenkins --enable-vault` consistently logged `TLS connection failed` and
`Failed to extract certificate` even though the follow-up certificate pinning
check succeeded. This was happening on macOS runs that use the new port-forward
path for private ingress IPs.

## Root Cause

`_jenkins_run_smoke_test` launches `kubectl port-forward ... 8443:443` in a
subshell and immediately invokes `bin/smoke-test-jenkins.sh` with
`JENKINS_SMOKE_IP_OVERRIDE=127.0.0.1` and port `8443`. The smoke script's TLS
connectivity and certificate extraction steps perform a **single** `openssl
s_client` call. When the port-forward is still warming up, `openssl` receives a
connection refusal and the test fails even though the port forward becomes ready
milliseconds later (evidenced by the pinning + auth tests passing).

## Fix

`bin/smoke-test-jenkins.sh` now retries the `openssl s_client` handshake and
certificate extraction up to 5 times with a short delay between attempts. This
absorbs the race between `kubectl port-forward` readiness and the TLS probes.

## Verification

1. Re-ran `CLUSTER_PROVIDER=orbstack PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager deploy_jenkins --enable-vault`.
2. Smoke test now reports all TLS checks as PASS when port-forward is used.
3. Manual run of `bin/smoke-test-jenkins.sh` also passes.
