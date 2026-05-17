# Bug: frontend.shopping-cart.local still blank — ServiceEntry blocked by ACG SG, replace with direct launchd port-forward

**Branch:** `k3d-manager-v1.4.6`
**Files:**
- `bin/acg-up` — line 232 (hosts list) + lines 947–1015 (Step 10g) + line 1038 (Step 13 info)

---

## Before You Start

```
git pull origin k3d-manager-v1.4.6
```

Read this spec in full before touching any file.

---

## Problem

Commit `14e7b8b0` added Step 10g which routes `frontend.shopping-cart.local` through the local k3d
Istio ingressgateway via a ServiceEntry pointing to ubuntu-k3s NodePort 30080. This fails because
the ACG security group blocks ALL external inbound connections to ubuntu-k3s (ports 80, 443, 30080,
8080 all timeout from k3d pods). The ServiceEntry endpoint is unreachable — Istio returns 503.

**Root cause:** The ACG SG only permits port 6443 (kubectl API) and port 22 (SSH) from external IPs.
k3d pods cannot reach ubuntu-k3s on any NodePort. k3d pods also cannot reach the Mac host directly
on the OrbStack bridge (connections from 10.42.x.x to 192.168.97.1 are refused at the OS level).

**Fix:** Abandon the Istio/ServiceEntry routing for frontend entirely. Instead:
- Bind `frontend.shopping-cart.local` to `127.0.0.2` (a separate loopback IP, no conflict with
  `127.0.0.1` used by Keycloak/ArgoCD via Istio)
- Add a dedicated launchd agent: `kubectl port-forward --address=127.0.0.2 svc/frontend 80:80`
  targeting ubuntu-k3s directly from the Mac (kubectl API on port 6443 is open)
- Remove the NodePort, ServiceEntry, and VirtualService from Step 10g — they are dead code

---

## Fix

### Change 1 — line 232: change frontend /etc/hosts IP from 127.0.0.1 to 127.0.0.2

**Exact old line:**
```bash
  "frontend.shopping-cart.local|127.0.0.1"
```

**Exact new line:**
```bash
  "frontend.shopping-cart.local|127.0.0.2"
```

---

### Change 2 — lines 947–1015: replace Step 10g block

**Exact old block (lines 947–1015):**
```bash
_info "[acg-up] Step 10g/14 — Wiring frontend.shopping-cart.local → ubuntu-k3s frontend (NodePort + ServiceEntry + VirtualService)..."

# 1. Create / reconcile NodePort 30080 for the frontend service on ubuntu-k3s.
#    NodePort 30080 is reserved for frontend; 30081 = order-service, 30082 = product-catalog.
kubectl apply --context ubuntu-k3s -f - <<'FRONTEND_NP_EOF'
apiVersion: v1
kind: Service
metadata:
  name: frontend-nodeport
  namespace: shopping-cart-apps
spec:
  type: NodePort
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30080
FRONTEND_NP_EOF

# 2. Get the ubuntu-k3s control-plane public IP from the kubeconfig server URL.
_ubuntu_k3s_ip=$(kubectl config view \
  --context ubuntu-k3s --minify \
  -o jsonpath='{.clusters[0].cluster.server}' \
  | sed 's|https://||; s|:.*||')

# 3. Apply a ServiceEntry in k3d so Istio can route to the remote NodePort.
kubectl apply --context k3d-k3d-cluster -f - <<FRONTEND_SE_EOF
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: frontend-ubuntu-k3s
  namespace: istio-system
spec:
  hosts:
    - frontend-ubuntu-k3s.external
  addresses:
    - ${_ubuntu_k3s_ip}/32
  ports:
    - number: 30080
      name: http
      protocol: HTTP
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: ${_ubuntu_k3s_ip}
FRONTEND_SE_EOF

# 4. Apply VirtualService in k3d: frontend.shopping-cart.local → ServiceEntry host:30080.
kubectl apply --context k3d-k3d-cluster -f - <<'FRONTEND_VS_EOF'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: frontend
  namespace: istio-system
spec:
  hosts:
    - frontend.shopping-cart.local
  gateways:
    - istio-system/default-gateway
  http:
    - route:
        - destination:
            host: frontend-ubuntu-k3s.external
            port:
              number: 30080
FRONTEND_VS_EOF

_info "[acg-up] frontend.shopping-cart.local wired: ingressgateway → ${_ubuntu_k3s_ip}:30080 → frontend pod"
```

**Exact new block:**
```bash
if _is_mac; then
  _info "[acg-up] Step 10g/14 — Installing frontend HTTP listener (frontend.shopping-cart.local → 127.0.0.2:80 → ubuntu-k3s, auto-restart)..."
  _frontend_browser_label="com.k3d-manager.frontend-browser-http"
  _frontend_browser_plist="${FRONTEND_BROWSER_LISTENER_PLIST:-/Library/LaunchDaemons/${_frontend_browser_label}.plist}"
  _frontend_browser_log="${HOME}/.local/share/k3d-manager/frontend-browser-http.log"
  _frontend_browser_launchctl_log="${HOME}/.local/share/k3d-manager/frontend-browser-http-launchctl.log"
  _frontend_browser_wrapper="${HOME}/.local/share/k3d-manager/frontend-browser-http.sh"
  _frontend_browser_plist_tmp="${HOME}/.local/share/k3d-manager/frontend-browser-http.plist"
  _frontend_browser_kubeconfig="${HOME}/.kube/config"
  mkdir -p "$(dirname "${_frontend_browser_log}")"
  # Write self-contained wrapper script; paths are baked in at write-time.
  cat > "${_frontend_browser_wrapper}" <<FRONTEND_WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG="${_frontend_browser_kubeconfig}"
_log="${_frontend_browser_log}"
while true; do
  printf '%s\n' "[\$(date)] starting frontend port-forward: svc/frontend → 127.0.0.2:80" >> "\${_log}"
  kubectl --context ubuntu-k3s port-forward --address=127.0.0.2 \
    svc/frontend 80:80 -n shopping-cart-apps >> "\${_log}" 2>&1 || true
  sleep 2
done
FRONTEND_WRAPPER
  chmod +x "${_frontend_browser_wrapper}"
  cat > "${_frontend_browser_plist_tmp}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${_frontend_browser_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${_frontend_browser_wrapper}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${_frontend_browser_log}</string>
  <key>StandardErrorPath</key>
  <string>${_frontend_browser_log}</string>
</dict>
</plist>
PLIST
  : > "${_frontend_browser_launchctl_log}"
  if _run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${_frontend_browser_plist}" \
      >"${_frontend_browser_launchctl_log}" 2>&1; then
    _info "[acg-up] Stopped existing frontend browser HTTP listener"
  elif [[ -s "${_frontend_browser_launchctl_log}" ]]; then
    tail -n 20 "${_frontend_browser_launchctl_log}" >&2 || true
    _warn "[acg-up] existing frontend browser HTTP listener was not loaded; continuing"
  fi
  : > "${_frontend_browser_launchctl_log}"
  if ! _run_command --interactive-sudo --quiet -- install -m 644 "${_frontend_browser_plist_tmp}" "${_frontend_browser_plist}" \
      >"${_frontend_browser_launchctl_log}" 2>&1; then
    if [[ -s "${_frontend_browser_launchctl_log}" ]]; then
      tail -n 20 "${_frontend_browser_launchctl_log}" >&2 || true
    fi
    _err "[acg-up] failed to install frontend browser HTTP listener plist"
  fi
  rm -f "${_frontend_browser_plist_tmp}"
  : > "${_frontend_browser_launchctl_log}"
  if ! _run_command --interactive-sudo --quiet -- launchctl bootstrap system "${_frontend_browser_plist}" \
      >"${_frontend_browser_launchctl_log}" 2>&1; then
    if [[ -s "${_frontend_browser_launchctl_log}" ]]; then
      tail -n 20 "${_frontend_browser_launchctl_log}" >&2 || true
    fi
    _err "[acg-up] failed to bootstrap frontend browser HTTP listener"
  fi
  _info "[acg-up] Frontend HTTP listener active: http://frontend.shopping-cart.local → ubuntu-k3s svc/frontend via 127.0.0.2 (launchd: ${_frontend_browser_label})"
fi
```

---

### Change 3 — line 1038: update Step 13 info line

**Exact old line:**
```bash
_info "[acg-up] Step 13/14 — Frontend wired via NodePort 30080 on ubuntu-k3s (Step 10g). URL: http://frontend.shopping-cart.local"
```

**Exact new line:**
```bash
_info "[acg-up] Step 13/14 — Frontend served via direct kubectl port-forward on 127.0.0.2:80 → ubuntu-k3s (Step 10g). URL: http://frontend.shopping-cart.local"
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Line 232: 127.0.0.1 → 127.0.0.2 for frontend host; Step 10g: replace NodePort/ServiceEntry/VirtualService with launchd port-forward; Step 13: update info line |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files modified
- The wrapper heredoc uses an unquoted delimiter (`FRONTEND_WRAPPER`) so paths bake in at write-time — this is intentional; `\$(date)` and `\${_log}` use backslash-escape to defer expansion to runtime

---

## Definition of Done

- [ ] Line 232: `frontend.shopping-cart.local|127.0.0.1` → `frontend.shopping-cart.local|127.0.0.2`
- [ ] Lines 947–1015: Step 10g block replaced with launchd port-forward (exact new block above)
- [ ] Line 1038: Step 13 info line updated (exact new line above)
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat`

**Commit message (exact):**
```
fix(acg-up): replace broken ServiceEntry with direct launchd port-forward on 127.0.0.2 for frontend
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT delete the ServiceEntry/VirtualService that were applied to the live cluster — they are harmless stale resources; a future `make up` will not re-apply them
- Do NOT touch the keycloak or ArgoCD launchd agents — only the new frontend agent is in scope
