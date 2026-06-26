# Bugfix: Hostinger refresh was not restoring the public Keycloak `localhost:8880` hop

**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`  
**Files:** `scripts/lib/providers/k3s-hostinger.sh`, `scripts/tests/lib/provider_contract.bats`

## Problem

`make refresh CLUSTER_PROVIDER=k3s-hostinger` restored the ArgoCD public hop at
`argocd.3ai-talk.org`, but browser login still failed because the OIDC redirect to
`keycloak.3ai-talk.org` returned `502 Bad Gateway`.

The local terminal checks showed the mismatch:

```bash
curl -Ik https://argocd.3ai-talk.org/
curl -Ik https://keycloak.3ai-talk.org/
curl -I http://127.0.0.1:8880/health/live
```

Observed behavior:

- `https://argocd.3ai-talk.org/` returned `HTTP/2 200`
- `https://keycloak.3ai-talk.org/` returned `HTTP/2 502`
- `http://127.0.0.1:8880/health/live` refused the connection

Cloudflare was healthy, but its local origin for Keycloak was dark. The tunnel config already
maps `keycloak.3ai-talk.org` to `http://localhost:8880`, so browser SSO depends on the
`com.k3d-manager.keycloak-port-forward` LaunchAgent being present and healthy after refresh.

## Root Cause

The Hostinger refresh path only restarted:

- `com.k3d-manager.argocd-port-forward`
- `com.k3d-manager.keycloak-browser-http`
- other browser/service listeners

It did **not** restore the separate public Keycloak port-forward on `localhost:8880`.
That browser-facing `keycloak-browser-http` daemon serves the local `keycloak.shopping-cart.local`
path through Istio on system port `80`; it is not the same hop Cloudflare uses for
`keycloak.3ai-talk.org`.

As a result, refresh could leave:

- no listener on `127.0.0.1:8880`
- or a stale/orphan `keycloak-port-forward.sh` wrapper outside launchd

and ArgoCD SSO would still fail in the browser even though direct ArgoCD curl checks passed.

## Fix

Update `scripts/lib/providers/k3s-hostinger.sh` so `_hostinger_refresh_access_layer()` also:

1. Regenerates `~/Library/LaunchAgents/com.k3d-manager.keycloak-port-forward.plist` when missing
2. Rewrites the canonical `~/.local/share/k3d-manager/bin/keycloak-port-forward.sh` wrapper from
   the shared `scripts/etc/argocd/port-forward-wrapper.sh.tmpl`
3. Kills stale wrapper processes matching the Keycloak wrapper path
4. Clears stale `localhost:8880` listeners before restart
5. Restarts `com.k3d-manager.keycloak-port-forward` before restarting Cloudflare

## Rules

- Do not change the Cloudflare hostname mapping
- Do not remove the existing `keycloak-browser-http` restart
- Keep the fix provider-safe so ACG/local flows still use their existing listeners unchanged

## Definition of Done

- [ ] Hostinger refresh regenerates the Keycloak `8880` wrapper from the shared port-forward template
- [ ] Hostinger refresh clears stale Keycloak wrapper processes and `8880` listeners before restart
- [ ] Hostinger refresh restarts `com.k3d-manager.keycloak-port-forward`
- [ ] `scripts/tests/lib/provider_contract.bats` asserts the Keycloak wrapper/restart behavior
- [ ] Validation includes `bash -n`, `shellcheck`, BATS, `_agent_audit`, and a live Hostinger refresh plus Keycloak public curl checks

**Commit message:**

```text
fix(hostinger): restore keycloak public port-forward during refresh
```
