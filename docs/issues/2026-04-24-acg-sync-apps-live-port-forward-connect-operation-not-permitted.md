# acg-sync-apps live validation: kubectl port-forward cannot connect to the apiserver in this sandbox

**Date:** 2026-04-24
**Branch:** `k3d-manager-v1.1.0`

## What I tested

Ran:

```text
timeout 30s make sync-apps
```

## Actual output

```text
bin/acg-sync-apps
INFO: [sync-apps] Starting argocd-server port-forward...
INFO: [sync-apps] ERROR: argocd-server port-forward exited early — see /tmp/k3d-manager/acg-sync-apps-argocd-pf.log
Unable to connect to the server: dial tcp 127.0.0.1:61722: connect: operation not permitted
make: *** [sync-apps] Error 1
```

## Root Cause

The temp-backed state directory fix worked, but this sandbox does not allow the `kubectl`
process to connect to the cluster apiserver for the port-forward session.

## Follow-up

Validate `make sync-apps` on the real host environment outside the sandbox. The code path no
longer fails on the state directory write.
