# Issue: frontend persistent CrashLoopBackOff due to Probe Failures

**Date:** 2026-03-21
**Status:** OPEN
**Component:** `shopping-cart-frontend`

## Symptoms

`frontend` pod is in `CrashLoopBackOff` with frequent restarts. 
Logs show Nginx starting successfully:
```
2026/03/21 16:32:08 [notice] 1#1: start worker processes
2026/03/21 16:32:08 [notice] 1#1: start worker process 22
2026/03/21 16:32:08 [notice] 1#1: start worker process 23
```
However, the pod is eventually terminated and restarted by the kubelet.

## Root Cause

The readiness and/or liveness probes are likely failing.
The current configuration uses:
- Port: `8080`
- Path: `/health`

Nginx traditionally listens on port 80 and may not have a `/health` endpoint configured unless specifically added to the config templates.

## Mitigation

- Manually patched with `emptyDir` volumes to resolve previous permission denied errors.
- Need to verify if Nginx is listening on 8080 and if `/health` is a valid endpoint.
- Consider updating probes to use port 80 or a simple TCP socket check.
