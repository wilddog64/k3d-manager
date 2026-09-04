# M2 remote E2E acceptance blocked by runner name resolution

## Attempt

M2 bootstrap and capacity preflight passed after OrbStack was started. An intentional
failure run using a nonexistent, valid image digest produced the expected failed artifact:

```text
INFO: [e2e] Overriding product-catalog image with candidate sha256:0000000000000000000000000000000000000000000000000000000000000000
error: timed out waiting for the condition
ERROR: e2e: kubectl -n shopping-cart-apps rollout status deployment/product-catalog --timeout=300s failed
INFO: [e2e] Summary written to /Users/cliang/.k3dm/e2e/1787707008-17529.json (exit_code=1)
WARN: [e2e-remote] M4 publication unavailable; retained 1787707008-17529.publication_pending.json for replay
make: *** [e2e-remote] Error 1
```

Replay with publisher variables then failed because the existing M2 SSH alias could not
resolve its configured hostname:

```text
ssh: Could not resolve hostname m2-air.local: nodename nor servname provided, or not known
ERROR: [e2e-remote] runner m2 unreachable; cannot replay
make: *** [e2e-replay] Error 1
```

A second SSH probe after 30 seconds produced the same resolution error.

## Blocker and follow-up

The acceptance cannot complete until the existing `m2jump` → `m2-air.local` resolution
path is restored. Do not hard-code a LAN IP. Then replay the retained failure with
`E2E_M2_PUBLISH_BACK_HOST` configured and run one normal passing
`make e2e-remote RUNNER=m2`; verify both ConfigMaps, runner-labelled metrics, and M4
Grafana health before closing the gate.
