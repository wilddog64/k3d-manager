# Bug: ArgoCD SSO Local Connectivity Failure

**Date:** 2026-05-10
**Severity:** High — prevents UI access and SSO login on Mac host
**Status:** Open
**Assignee:** Gemini CLI

## Symptom
1.  **Safari:** "server unexpectedly dropped the connection" when accessing `localhost:8080`.
2.  **SSO Login:** Fails with `NXDOMAIN` for `keycloak.shopping-cart.local`.
3.  **Logs:** `argocd-pf.log` reports `bind: address already in use` for port 8080.

## Root Cause
1.  **Ghost Processes:** Previous `kubectl port-forward` processes are not cleaned up during `acg-down` or `make down`, leaving port 8080 locked by dead connections.
2.  **Missing Local DNS:** The Mac host's `/etc/hosts` file lacks the mapping for `keycloak.shopping-cart.local`, preventing the browser from reaching the identity provider via the local tunnel.

## Required Fixes
1.  **Hardened `acg-down`:** Update teardown logic to find and `kill` any processes listening on ports 8080, 18080, and 18200.
2.  **Robust `acg-up`:** Add logic to Step 10e to automatically inject the `keycloak.shopping-cart.local` entry into `/etc/hosts` (with a user check/sudo prompt).
3.  **Port Guard:** Add a pre-flight check to `acg-up` to verify ports are clear before starting new agents.

## Manual Workaround (Verified)
```bash
# 1. Clear ports
lsof -ti :8080,18080,18200 | xargs kill -9
# 2. Add DNS
sudo sh -c 'echo "127.0.0.1 keycloak.shopping-cart.local" >> /etc/hosts'
# 3. Reload agent
launchctl unload ~/Library/LaunchAgents/com.k3d-manager.argocd-port-forward.plist
launchctl load ~/Library/LaunchAgents/com.k3d-manager.argocd-port-forward.plist
```
