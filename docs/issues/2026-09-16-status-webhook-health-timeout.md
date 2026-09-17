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

The summary command also retries the Keychain token when an explicitly exported `K3DM_WEBHOOK_TOKEN` is rejected. This prevents a stale shell environment value from masking a valid rotated Keychain token as `webhook unavailable`.

The live incident added a second authentication failure mode: the Keychain item existed but its password was empty (`security find-generic-password ... -w` exited cleanly with zero bytes). Public Grafana remained reachable because it uses a separate Cloudflare route. `bin/k3dm-webhook-setup` now treats an empty Keychain value as missing and regenerates it.

Deep-dive follow-up: the terminal could not write the replacement because macOS returned `User interaction is not allowed` for `security add-generic-password`. The login Keychain item exists, but the current terminal/session is not authorized to read/write its value. Unlock the login Keychain in Keychain Access (or with `security unlock-keychain` interactively) before rotating; do not bypass this with a plaintext token file.

Resolution: token rotation was not required. Unlocking the login Keychain restored access to the existing token; `make status CLUSTER_PROVIDER=k3s-hostinger` then returned ArgoCD, Frontend, Keycloak, and Grafana HTTP 200, with only the expected unauthenticated Prometheus readiness warning.

## Prevention improvement

`cluster-status-summary` now distinguishes an empty/missing Keychain token, a Keychain interaction denial, and a rejected exported token from a generic webhook outage. `bin/k3dm-webhook-setup` also reports the unlock action when macOS denies a Keychain write.

Rotation initially failed because `bin/rotate-webhook-token` used the obsolete Keychain service `cloudflare-api-token`; the configured service is `k3dm-cloudflare-api-token`. That lookup is corrected. `make rotate-webhook-token` then succeeded, uploaded the Worker secret, restored a 64-byte local token, and verified the public endpoint (HTTP 404, proving authentication reached the route).

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
