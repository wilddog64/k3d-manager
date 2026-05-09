# Bugfix: ArgoCD SSO Fails — CoreDNS maps keycloak.shopping-cart.local to IngressGateway node IP

**Branch:** `k3d-manager-v1.4.5`
**File:** `bin/acg-up` (step 10e, lines ~604–622)

---

## Problem

ArgoCD SSO fails with:

```
failed to query provider "http://keycloak.shopping-cart.local/realms/shopping-cart":
Get "http://keycloak.shopping-cart.local/realms/shopping-cart/.well-known/openid-configuration":
dial tcp 192.168.97.2:80: connect: connection refused
```

**Root cause — two compounding issues:**

1. **Wrong target IP:** The CoreDNS patch uses the Istio IngressGateway LB IP (`192.168.97.2`), which in k3d/OrbStack is the node IP, not a routable service endpoint. Port 80 is not listening there. The correct target is Keycloak's `ClusterIP` (e.g., `10.43.2.172`), which is directly reachable by pods in the cluster.

2. **Non-durable patch location:** The entry is added to `NodeHosts` (the `{.data.NodeHosts}` field of the `coredns` ConfigMap), which k3d manages and periodically overwrites with only the node hostname→IP entries. Our custom `keycloak.shopping-cart.local` entry gets erased on the next k3d write.

---

## Fix

Replace the `NodeHosts` approach with a patch to the CoreDNS `Corefile` itself, adding a standalone `hosts` block that maps `keycloak.shopping-cart.local` to the Keycloak service ClusterIP.

### Change — `bin/acg-up` (step 10e, CoreDNS block)

**Old (lines ~604–622):**
```bash
_gw_ip=$(kubectl get svc istio-ingressgateway -n istio-system --context k3d-k3d-cluster \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [[ -n "${_gw_ip}" ]]; then
  _nh=$(kubectl get cm coredns -n kube-system --context k3d-k3d-cluster \
    -o jsonpath='{.data.NodeHosts}')
  if ! printf '%s' "${_nh}" | grep -qF 'keycloak.shopping-cart.local'; then
    _new_nh="${_nh}
${_gw_ip} keycloak.shopping-cart.local"
    kubectl patch cm coredns -n kube-system --context k3d-k3d-cluster \
      --type merge \
      --patch "$(python3 -c "import json,sys; print(json.dumps({'data':{'NodeHosts':sys.argv[1]}}))" "${_new_nh}")"
    kubectl rollout restart deployment/coredns -n kube-system --context k3d-k3d-cluster
    kubectl rollout status deployment/coredns -n kube-system --context k3d-k3d-cluster --timeout=60s
    _info "[acg-up] CoreDNS NodeHosts patched: keycloak.shopping-cart.local → ${_gw_ip}"
  fi
else
  _info "[acg-up] WARNING: IngressGateway LB IP not found — CoreDNS not patched; ArgoCD SSO in-cluster resolution may fail"
fi
```

**New:**
```bash
# Patch CoreDNS Corefile (not NodeHosts) so keycloak.shopping-cart.local → Keycloak ClusterIP.
# NodeHosts is managed by k3d and gets overwritten; Corefile is stable.
_kc_svc_ip=$(kubectl get svc keycloak -n identity --context k3d-k3d-cluster \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
if [[ -n "${_kc_svc_ip}" ]]; then
  _current_corefile=$(kubectl get cm coredns -n kube-system --context k3d-k3d-cluster \
    -o jsonpath='{.data.Corefile}')
  _new_corefile=$(printf '%s' "${_current_corefile}" | python3 - "${_kc_svc_ip}" <<'PYEOF'
import sys, re
text = sys.stdin.read()
ip = sys.argv[1]
hosts_block = f"    hosts {{\n      {ip} keycloak.shopping-cart.local\n      fallthrough\n    }}\n"
# Remove any previous block (idempotent re-runs)
text = re.sub(r'    hosts \{\n      \S+ keycloak\.shopping-cart\.local\n      fallthrough\n    \}\n', '', text)
# Insert before 'forward . /etc/resolv.conf'
text = text.replace('    forward . /etc/resolv.conf', hosts_block + '    forward . /etc/resolv.conf')
print(text, end='')
PYEOF
)
  kubectl patch cm coredns -n kube-system --context k3d-k3d-cluster \
    --type merge \
    --patch "$(python3 -c "import json,sys; print(json.dumps({'data':{'Corefile':sys.argv[1]}}))" "${_new_corefile}")"
  kubectl rollout restart deployment/coredns -n kube-system --context k3d-k3d-cluster
  kubectl rollout status deployment/coredns -n kube-system --context k3d-k3d-cluster --timeout=60s
  _info "[acg-up] CoreDNS Corefile patched: keycloak.shopping-cart.local → ${_kc_svc_ip} (Keycloak ClusterIP)"
else
  _info "[acg-up] WARNING: Keycloak ClusterIP not found — CoreDNS not patched; ArgoCD SSO may fail"
fi
```

**Resulting Corefile diff (conceptual):**
```diff
+     hosts {
+       10.43.2.172 keycloak.shopping-cart.local
+       fallthrough
+     }
      forward . /etc/resolv.conf
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Replace `NodeHosts` CoreDNS patch with `Corefile` patch using Keycloak ClusterIP |

---

## Definition of Done

- [ ] Old `_gw_ip` / NodeHosts block replaced with new `_kc_svc_ip` / Corefile block
- [ ] Script is idempotent: re-running `acg-up` does not duplicate the hosts entry
- [ ] CoreDNS restarted and rolled out after patch
- [ ] Verify in-cluster resolution: `kubectl run -it --rm dns-test --image=busybox:1.36 --restart=Never --context k3d-k3d-cluster -- nslookup keycloak.shopping-cart.local`
  - Expected: resolves to Keycloak ClusterIP (e.g., `10.43.2.172`), not `192.168.97.2`
- [ ] ArgoCD SSO login succeeds: open `http://localhost:8080`, click SSO button, verify Keycloak redirect
- [ ] Committed and pushed to `k3d-manager-v1.4.5`

**Commit message (exact):**
```
fix(acg-up): patch CoreDNS Corefile with Keycloak ClusterIP instead of IngressGateway NodeHosts
```
