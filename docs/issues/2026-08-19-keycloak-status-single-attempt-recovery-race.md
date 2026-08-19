# Keycloak status check raced local-forward recovery

## Observed output

```text
✗ Keycloak: HTTP Error 502: Bad Gateway
✗ Keycloak login: HTTP Error 502: Bad Gateway
! Frontend login: skipped (no Keycloak token)
Overall: FAIL (2 errors, 1 warnings)
```

The Keycloak port-forward log then showed the underlying recovery sequence:

```text
error upgrading connection: unable to upgrade connection: error dialing backend: tls: failed to verify certificate: x509: certificate is valid for 127.0.0.1, 192.168.97.6, not 192.168.97.3
Forwarding from 127.0.0.1:8880 -> 8080
[argocd-pf] healthz reachable — monitoring backend availability
```

After agent-0 re-registered its current address and the port-forward converged,
both local and public Keycloak health checks returned `{"status":"UP"}`.

## Root cause

The service smoke framework has a bounded three-attempt retry policy for local
forward and Cloudflare recovery. The synchronous `/api/v1/health` handler used
by `make status` bypassed it by calling `_smoke_test_services(retries=1)`.
One 502 during the normal Keycloak forward recovery was therefore presented as
a service outage, and the dependent login probe had no token to run.

## Fix

The health handler now calls `_smoke_test_services()` with its default bounded
retry policy for both unqualified and provider-qualified health requests. A
persistent Keycloak failure still reports red after all attempts fail.
