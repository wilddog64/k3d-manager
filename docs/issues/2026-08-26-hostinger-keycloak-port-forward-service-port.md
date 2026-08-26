# Hostinger refresh regenerated Keycloak port-forward with the wrong service port

## What was tested / attempted

Ran the live status and the provider's edge-only recovery:

```text
make status
  ✗ ArgoCD: HTTP Error 502: Bad Gateway
  ✓ Frontend: HTTP 200
  ✗ Keycloak: HTTP Error 502: Bad Gateway
  ✓ Prometheus: HTTP 200
  ✓ Grafana: HTTP 200
Overall: FAIL (2 errors, 2 warnings)
```

```text
make refresh-edge CLUSTER_PROVIDER=k3s-hostinger
INFO: [k3s-hostinger] Refreshing edge only (cloudflared + port-forwards) — no GitOps reapply
INFO: [k3s-hostinger] launchd com.k3d-manager.argocd-port-forward: restarted
INFO: [k3s-hostinger] launchd com.k3d-manager.keycloak-port-forward: restarted
INFO: [k3s-hostinger] Edge refresh complete
```

The Keycloak agent continued logging:

```text
[argocd-pf] starting port-forward: svc/keycloak -> localhost:8880
error: Service keycloak does not have a service port 80
[argocd-pf] port-forward exited before healthz became reachable — restarting
```

A direct temporary forward to ArgoCD returned HTTP 200, confirming the Kubernetes backend was
healthy while the managed local access layer was failing.

## Root cause

The Hostinger provider's `_hostinger_write_keycloak_port_forward_wrapper` regenerated the wrapper
with `REMOTE_PORT="80"` and `/health/live`. The current hub `identity/keycloak` Service exposes
only service port 8080 (`targetPort: http`), so every refresh/restart failed. The generated wrapper
also used a health URL that did not match the previously working realm endpoint.

After correcting the service port, the Keycloak local endpoint returned 200 but the public probe
still intermittently returned 502. Cloudflared logged connection attempts to `[::1]:8880` while
the managed listener was only reliably available on IPv4. The durable tunnel configuration also
used `localhost:8880`; it is changed to `127.0.0.1:8880` in both the checked-in config and template.
The provider-generated health probes are also pinned to `127.0.0.1` so the wrappers do not probe
the IPv6 listener and tear down a healthy IPv4 path after a reset.

## Fix

Use Keycloak service port 8080 and probe `/realms/master` over IPv4; route cloudflared to IPv4
loopback for both services. Update the provider contract test to assert `8880:8080`.

## Recommended follow-up

Keep the provider contract test aligned with the live Service port whenever the identity chart is
changed, and verify `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger` followed by `make status`.

The final service check also exposed two access-layer follow-ups: the hub Prometheus port-forward
agent was absent after the edge refresh, and the Hostinger status probe still used Keycloak's
nonexistent `/health/live` path. The live recovery installed the existing Prometheus LaunchAgent;
the Hostinger probe now uses `/realms/master`.

## Follow-up: transient port-forward flapping

The subsequent status showed ArgoCD's health probe passing while its login request returned 502,
and Keycloak also returned 502. The forwarder logs captured the race:

```text
E0826 13:56:28.412565   35674 portforward.go:502] "Unhandled Error" err="error copying from local connection to remote stream: writeto tcp4 127.0.0.1:8080->127.0.0.1:64887: read tcp4 127.0.0.1:8080->127.0.0.1:64887: read: connection reset by peer"
[argocd-pf] healthz check failed (1/3)
E0826 13:56:46.288125   35674 portforward.go:502] "Unhandled Error" err="error copying from local connection to remote stream: writeto tcp4 127.0.0.1:8080->127.0.0.1:64934: read tcp4 127.0.0.1:8080->127.0.0.1:64934: read: connection reset by peer"
[argocd-pf] healthz check failed (1/3)
```

The shared wrapper was restarting immediately on the first failed one-second health check and
waiting 30 seconds before retrying. It now binds kubectl explicitly to `127.0.0.1`, tolerates
three consecutive health failures, and retries after 2 seconds. After regeneration, both local
endpoints returned HTTP 200:

```text
local-argocd-health 200
local-keycloak-realm 200
```

Public DNS checks from the agent shell were skipped because this environment could not resolve
`argocd.3ai-talk.org` or `keycloak.3ai-talk.org`; verify them from the user's normal shell with
`make status` after the tunnel has had a few seconds to settle.
