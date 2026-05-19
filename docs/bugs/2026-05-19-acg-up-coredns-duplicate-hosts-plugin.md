# Bugfix: acg-up — CoreDNS crash from duplicate `hosts` plugin

**Branch:** `k3d-manager-v1.4.9`
**Files:** `bin/acg-up`

---

## Problem

After `make up` runs the Keycloak CoreDNS step, CoreDNS crashes and all cluster DNS
resolution fails. The symptom is a 502 Bad Gateway on all Ingress-routed services
(e.g. `frontend.3ai-talk.org`).

**Root cause:** Lines 884–909 of `bin/acg-up` inject a second `hosts {}` block into the
CoreDNS `Corefile`. CoreDNS only allows one `hosts` plugin per server block — a duplicate
causes CoreDNS to refuse to start.

---

## Reproduction

1. Run `make up` on a fresh ACG sandbox (or re-run after the Keycloak step has already
   run once and the workaround has not been applied).
2. Watch CoreDNS pods crash-loop after the "CoreDNS updated" log line.
3. All in-cluster DNS resolution fails; frontend returns 502.

---

## Fix

### Change 1 — `bin/acg-up`: patch `NodeHosts` key instead of inserting a second `hosts` block

Replace the entire `_coredns_corefile` / `_coredns_patch` block (lines 884–909) with
logic that reads the `NodeHosts` key, appends `keycloak.shopping-cart.local` to the
existing `${_node_ip}` line, and patches only `data.NodeHosts`.

**Exact old block (lines 884–909):**
```bash
  _coredns_corefile=$(kubectl get configmap coredns -n kube-system --context ubuntu-k3s \
    -o jsonpath='{.data.Corefile}' 2>/dev/null || true)
  if echo "${_coredns_corefile}" | grep -q "keycloak.shopping-cart.local"; then
    _info "[acg-up] CoreDNS keycloak hosts entry already present — skipping"
  else
    _coredns_patch=$(cat <<COREDNS_PATCH
    hosts {
        ${_node_ip} keycloak.shopping-cart.local
        fallthrough
    }
COREDNS_PATCH
)
    _new_corefile=$(COREDNS_PATCH="${_coredns_patch}" python3 -c "
import sys, os
patch = os.environ['COREDNS_PATCH']
for line in sys.stdin:
    if line.strip().startswith('prometheus'):
        sys.stdout.write(patch + '\n')
    sys.stdout.write(line)
" <<< "${_coredns_corefile}")
    kubectl patch configmap coredns -n kube-system --context ubuntu-k3s \
      --type merge -p "{\"data\":{\"Corefile\":$(echo "${_new_corefile}" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')}}" >/dev/null 2>&1 || \
      _warn "[acg-up] CoreDNS patch for keycloak.shopping-cart.local failed"
    kubectl rollout restart deployment/coredns -n kube-system --context ubuntu-k3s >/dev/null 2>&1 || true
    _info "[acg-up] CoreDNS updated: keycloak.shopping-cart.local → ${_node_ip} (via port 80 DNAT → 127.0.0.1:18080 → SSH tunnel → Keycloak)"
  fi
```

**Exact new block:**
```bash
  _coredns_nodehosts=$(kubectl get configmap coredns -n kube-system --context ubuntu-k3s \
    -o jsonpath='{.data.NodeHosts}' 2>/dev/null || true)
  if echo "${_coredns_nodehosts}" | grep -q "keycloak.shopping-cart.local"; then
    _info "[acg-up] CoreDNS keycloak hosts entry already present — skipping"
  else
    _new_nodehosts=$(NODE_IP="${_node_ip}" python3 -c "
import sys, os
node_ip = os.environ['NODE_IP']
lines = sys.stdin.read().splitlines()
result = []
appended = False
for line in lines:
    result.append(line)
    if not appended and line.strip().startswith(node_ip):
        result.append(node_ip + ' keycloak.shopping-cart.local')
        appended = True
if not appended:
    result.append(node_ip + ' keycloak.shopping-cart.local')
print('\n'.join(result))
" <<< "${_coredns_nodehosts}")
    kubectl patch configmap coredns -n kube-system --context ubuntu-k3s \
      --type merge -p "{\"data\":{\"NodeHosts\":$(printf '%s' "${_new_nodehosts}" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')}}" >/dev/null 2>&1 || \
      _warn "[acg-up] CoreDNS NodeHosts patch for keycloak.shopping-cart.local failed"
    kubectl rollout restart deployment/coredns -n kube-system --context ubuntu-k3s >/dev/null 2>&1 || true
    _info "[acg-up] CoreDNS updated: keycloak.shopping-cart.local → ${_node_ip} (NodeHosts entry)"
  fi
```

**Why `NodeHosts` instead of `Corefile`:**
The k3s CoreDNS Addon uses a separate `NodeHosts` configmap key (not part of `Corefile`)
to inject node IP→hostname mappings. The existing `hosts` block in `Corefile` already
reads from `/etc/hosts` which k3s populates from `NodeHosts`. Appending to `NodeHosts`
is the correct extension point and avoids a duplicate `hosts` plugin.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Replace Corefile `hosts` block injection with `NodeHosts` key append |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- Code change limited to `bin/acg-up`; CHANGELOG and memory-bank updates are required documentation

---

## Definition of Done

- [ ] `bin/acg-up` patches `data.NodeHosts` (not `data.Corefile`) for `keycloak.shopping-cart.local`
- [ ] Idempotent: re-running `make up` skips the step if entry already present
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.4.9`
- [ ] memory-bank updated with commit SHA

**Commit message (exact):**
```
fix(acg-up): patch NodeHosts instead of injecting duplicate hosts block into CoreDNS Corefile
```

---

## What NOT to Do

- Do NOT modify `Corefile` — the `hosts` block must remain untouched
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
