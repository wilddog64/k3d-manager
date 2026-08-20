# Webhook-unavailable status after stale LaunchAgent listener

## Symptom

`make status` reported:

```text
Overall: UNKNOWN
  ! status source: webhook unavailable
  hint: make restart-webhook
make: *** [status] Error 2
```

## Investigation

The LaunchAgent was registered as running and port 7443 appeared in `lsof`, but the
listener refused connections. The webhook log ended with the prior process's request
exceptions and an old listener PID. This was a stale/unresponsive Python process behind
the `com.k3d-manager.webhook` LaunchAgent, not a missing bearer token or a failed health
check implementation.

## Recovery

Ran `make restart-webhook`, which booted out and bootstrapped the LaunchAgent. The new
process bound port 7443 and the authenticated health endpoint returned:

```text
{"services":[{"name":"ArgoCD","ok":true,"detail":"HTTP 200"},{"name":"Frontend","ok":true,"detail":"HTTP 200"},{"name":"Keycloak","ok":true,"detail":"HTTP 200"},{"name":"Prometheus","ok":true,"detail":"HTTP 200"},{"name":"Grafana","ok":true,"detail":"HTTP 200"},{"name":"Product images","ok":true,"detail":"20/20 have image_url"},{"name":"ESO ClusterSecretStore","ok":true,"detail":"Ready=True"},{"name":"ESO ExternalSecrets","ok":true,"detail":"18/18 synced"},{"name":"Data layer","ok":true,"detail":"4/4 ready"},{"name":"Keycloak login","ok":true,"detail":"token minted (realm=shopping-cart)"},{"name":"Frontend login","ok":true,"detail":"HTTP 200 on /api/cart"},{"name":"ArgoCD login","ok":true,"detail":"HTTP 200"},{"name":"Grafana login","ok":true,"detail":"HTTP 200"}],"all_ok":true}
```

Host-network `make status` now reports `Overall: WARN (4 warnings)` with core service and
login checks green. The remaining warnings are expected optional/non-deployed resources
(Pushgateway, ESO on the selected cluster, and the absent data namespace).

## Follow-up

If the symptom recurs, run `make restart-webhook` before treating the service checks as
unavailable. The status command must be run from the host network; a restricted sandbox
cannot connect to the host LaunchAgent listener even when it is healthy.

## Status default correction

`make status` previously inherited the Makefile-wide `CLUSTER_PROVIDER=k3s-aws` default,
which caused a healthy Hostinger deployment to be checked against the expired AWS sandbox.
The status target now defaults to `k3s-hostinger` when no provider was explicitly supplied,
while honoring an active-provider marker, environment override, or command-line override.

Verification:

```text
Overall: HEALTHY
Details: make status-full
make_status_rc=0
```
