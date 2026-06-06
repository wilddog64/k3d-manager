# Bug: acg-refresh restarts CoreDNS but never patches the NodeHosts ConfigMap

**Branch:** `k3d-manager-v1.6.3`
**Files:** `bin/acg-refresh`

---

## Problem

`acg-refresh` step 2b-pre restarts the CoreDNS deployment to restore `host.k3d.internal`
resolution. This only works if the `host.k3d.internal` entry already exists in the CoreDNS
`NodeHosts` ConfigMap. After a cluster restart or any other event that resets the ConfigMap,
the entry is gone — restarting CoreDNS reads from an empty NodeHosts and the DNS failure
persists.

**Root cause:** In k3d with OrbStack, CoreDNS reads `host.k3d.internal` from
`/etc/coredns/NodeHosts`, which is populated from the `NodeHosts` key of the `coredns`
ConfigMap in `kube-system`. The ConfigMap does not automatically contain a
`host.k3d.internal` entry — it must be patched explicitly. The current code only restarts
the pod without patching the ConfigMap.

**Correct host IP:** Inside OrbStack-managed k3d containers, the Mac host is reachable at
`0.250.250.254` (`host.docker.internal`). The gateway IP `192.168.97.1` (the Docker bridge
router) is NOT the Mac host and is not reachable on port 6443.

---

## Reproduction

1. After `acg-up`, check CoreDNS ConfigMap:
   ```bash
   kubectl get configmap coredns -n kube-system --context k3d-k3d-cluster \
     -o jsonpath='{.data.NodeHosts}'
   # host.k3d.internal is missing
   ```
2. Run `/acg-refresh` — CoreDNS restarts but `host.k3d.internal` still doesn't resolve
   from pods.
3. ArgoCD ComparisonError persists; shopping-cart apps never sync.

---

## Fix

### Change 1 — `bin/acg-refresh`: replace CoreDNS restart with ConfigMap patch + restart

**Exact old block (lines 188–196):**

```bash
# ── 2b-pre. CoreDNS restart on hub cluster ───────────────────────────────────
_info "[acg-refresh] Restarting CoreDNS on hub cluster to restore host.k3d.internal resolution..."
if kubectl rollout restart deployment/coredns -n kube-system --context k3d-k3d-cluster >/dev/null 2>&1; then
  kubectl rollout status deployment/coredns -n kube-system --context k3d-k3d-cluster --timeout=30s >/dev/null 2>&1 \
    && _info "[acg-refresh] CoreDNS restarted — host.k3d.internal resolution restored" \
    || _warn "[acg-refresh] CoreDNS rollout status timed out — DNS may still be recovering"
else
  _warn "[acg-refresh] CoreDNS restart failed — hub cluster may not be running"
fi
```

**Exact new block:**

```bash
# ── 2b-pre. CoreDNS NodeHosts patch + restart ────────────────────────────────
_info "[acg-refresh] Detecting host IP for host.k3d.internal..."
_coredns_host_ip=$(docker exec k3d-k3d-cluster-server-0 sh -c \
  "getent hosts host.docker.internal 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo "")
if [[ -z "${_coredns_host_ip}" ]]; then
  _warn "[acg-refresh] Could not detect host IP from host.docker.internal — CoreDNS patch skipped"
else
  _info "[acg-refresh] Patching CoreDNS NodeHosts: host.k3d.internal → ${_coredns_host_ip}"
  _existing_nodes=$(kubectl get configmap coredns -n kube-system \
    --context k3d-k3d-cluster \
    -o jsonpath='{.data.NodeHosts}' 2>/dev/null \
    | grep -v "host\.k3d\.internal" || true)
  _new_node_hosts="${_coredns_host_ip} host.k3d.internal"
  if [[ -n "${_existing_nodes}" ]]; then
    _new_node_hosts="${_new_node_hosts}"$'\n'"${_existing_nodes}"
  fi
  _patch_json=$(python3 -c \
    "import json,sys; print(json.dumps({'data':{'NodeHosts':sys.argv[1]}}))" \
    "${_new_node_hosts}")
  if kubectl patch configmap coredns -n kube-system \
      --context k3d-k3d-cluster --type merge -p "${_patch_json}" >/dev/null 2>&1; then
    _info "[acg-refresh] CoreDNS ConfigMap patched — host.k3d.internal → ${_coredns_host_ip}"
  else
    _warn "[acg-refresh] CoreDNS ConfigMap patch failed — DNS may not resolve"
  fi
  if kubectl rollout restart deployment/coredns -n kube-system \
      --context k3d-k3d-cluster >/dev/null 2>&1; then
    kubectl rollout status deployment/coredns -n kube-system \
      --context k3d-k3d-cluster --timeout=30s >/dev/null 2>&1 \
      && _info "[acg-refresh] CoreDNS restarted — host.k3d.internal resolution restored" \
      || _warn "[acg-refresh] CoreDNS rollout status timed out — DNS may still be recovering"
  else
    _warn "[acg-refresh] CoreDNS restart failed — hub cluster may not be running"
  fi
fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-refresh` | Replace CoreDNS restart-only with: detect host IP via `host.docker.internal`, patch `NodeHosts` ConfigMap, then restart CoreDNS |

---

## Rules

- `shellcheck -S warning bin/acg-refresh` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] `bin/acg-refresh`: step 2b-pre detects `_coredns_host_ip` via `docker exec k3d-k3d-cluster-server-0 getent hosts host.docker.internal`
- [ ] `bin/acg-refresh`: patches CoreDNS ConfigMap `NodeHosts` key with `<ip> host.k3d.internal` prepended to existing node entries
- [ ] `bin/acg-refresh`: restarts CoreDNS deployment and waits for rollout after patch
- [ ] `shellcheck -S warning bin/acg-refresh` — zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.6.3`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-refresh): patch CoreDNS NodeHosts ConfigMap with host.k3d.internal before restart
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-refresh`
- Do NOT commit to `main` — work on `k3d-manager-v1.6.3`
- Do NOT hardcode `0.250.250.254` — always detect via `host.docker.internal` from inside the k3d node
- Do NOT remove the CoreDNS restart step — the patch alone is insufficient; restart ensures immediate pickup
