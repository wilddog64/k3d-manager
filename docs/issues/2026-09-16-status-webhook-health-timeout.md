# Status falsely reported the webhook as unavailable

## Symptom

```text
Overall: UNKNOWN
  ! status source: webhook unavailable
  hint: make restart-webhook
make: *** [status] Error 2
```

At the same time, the webhook process was listening on `127.0.0.1:7443`. Its full health sweep includes public endpoint checks, Kubernetes/ESO checks, and browser login checks; that sweep can exceed the summary command's timeout. The result was a misleading UNKNOWN status rather than service-level results.

## Fix

The webhook health endpoint now supports `quick=1`. It returns the bounded public service liveness probes with one attempt and skips the expensive credential/Kubernetes drill-down. `bin/cluster-status-summary` uses that quick endpoint with a 30-second bound.

Prometheus returning HTTP 401 is classified as a warning in the quick liveness view because the public endpoint intentionally requires basic authentication. The full login checks remain responsible for validating authenticated Prometheus access.

## Verification

The live result after restarting the webhook is:

```text
  ✓ ArgoCD: HTTP 200
  ✓ Frontend: HTTP 200
  ✓ Keycloak: HTTP 200
  ! Prometheus: HTTP 401 (authentication required)
  ✓ Grafana: HTTP 200
Overall: WARN (1 warnings)
status_rc=0
```

The service credential target also resolved all credential fields after authenticated Vault preflight. The optional Python smoke-login test could not run because this host does not have `pytest` installed; the BATS cluster-status suite passed 3/3.
