# Issue: Hostinger ArgoCD refresh looped on `localhost:8080` bind conflicts

**Date:** 2026-06-24  
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`  
**Files:** `scripts/lib/providers/k3s-hostinger.sh`, `scripts/etc/argocd/port-forward-wrapper.sh.tmpl`

## What I Saw

`make refresh CLUSTER_PROVIDER=k3s-hostinger` completed the cluster registration step, but the
local ArgoCD listener on `localhost:8080` kept restarting with bind failures:

```text
Unable to listen on port 8080: Listeners failed to create with the following errors:
[unable to create listener: Error listen tcp4 127.0.0.1:8080: bind: address already in use
unable to create listener: Error listen tcp6 [::1]:8080: bind: address already in use]
error: unable to listen on any of the requested ports: [{8080 8080}]
```

The local socket was still owned by `kubectl`:

```text
COMMAND   PID   USER   FD   TYPE  NAME
kubectl 41517 cliang    8u  IPv4  127.0.0.1:8080 (LISTEN)
kubectl 41517 cliang    9u  IPv6  [::1]:8080 (LISTEN)
```

An early wrapper change also hit a macOS bash mismatch:

```text
/Users/cliang/.local/share/k3d-manager/bin/argocd-port-forward.sh: line 60: mapfile: command not found
```

## Root Cause

The generated ArgoCD port-forward wrapper was retrying `kubectl port-forward` without clearing
stale `8080` listeners first. On this Mac, the wrapper is launched through `/bin/bash`, so any
new logic also had to stay compatible with the system bash version.

## Fix

- Regenerate the live ArgoCD wrapper from `scripts/etc/argocd/port-forward-wrapper.sh.tmpl`
  during Hostinger refresh.
- Clear stale listeners on `8080` before each retry.
- Use a Bash 3.2-compatible read loop instead of `mapfile`.

## Verified

The elevated check now returns `200 OK`:

```text
HTTP/1.1 200 OK
```
