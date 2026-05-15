# Issue: Keycloak readiness loop waited on a dead port-forward instead of deployment readiness

**Date:** 2026-05-12
**Repo:** `k3d-manager`
**Area:** `bin/acg-up`

## What happened

`make up` timed out in the Keycloak readiness gate even though the live Keycloak pod eventually became Ready.

Observed terminal output:

```text
INFO: [acg-up] Keycloak API not ready yet (attempt 84/90) — waiting 10s...
INFO: [acg-up] Keycloak API not ready yet (attempt 89/90) — waiting 10s...
ERROR: [acg-up] Keycloak API not Ready after 900s — realm import is required for SSO and cannot be skipped
make: *** [up] Error 1
```

The temporary readiness port-forward log showed the loop was polling a bad tunnel target:

```text
Error from server (NotFound): services "keycloak" not found
Forwarding from 127.0.0.1:18080 -> 8080
Forwarding from [::1]:18080 -> 8080
Handling connection for 18080
```

Live cluster status after the timeout:

```text
True true 0
```

And the Keycloak pod logs showed a clean startup:

```text
2026-05-13 02:47:38,561 INFO  [io.quarkus] Keycloak 24.0.5 on JVM (powered by Quarkus 3.8.4) started in 11.499s. Listening on: http://0.0.0.0:8080
```

## Root cause

The readiness gate in `bin/acg-up` was using a temporary `kubectl port-forward` and polling `http://localhost:18080/health/ready`.

That meant:

- the loop could keep waiting on a dead or stale tunnel
- the log counters reported “API not ready” even when the Keycloak deployment was already Available
- the timeout value became a guess instead of a real signal

## Fix

Replace the tunnel-based readiness loop with a deployment-level readiness gate:

- wait on `deployment/keycloak` becoming `Available`
- dump deployment and pod status if the wait fails
- keep the import step separate from the readiness signal

## Follow-up

If Keycloak ever regresses again, the first thing to inspect should be the deployment availability and pod logs, not the temporary readiness port-forward.
