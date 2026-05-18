# Bug: Keycloak JWT issuer mismatch — OAUTH2_ISSUER_URI uses hub-cluster DNS unreachable from ubuntu-k3s

**Branch:** `k3d-manager-v1.4.6`
**Files:**
- `bin/acg-up` — insert Step 10g.5 between lines 1102 and 1104
- `shopping-cart-order/k8s/base/configmap.yaml` — update OAUTH2_ISSUER_URI + OAUTH2_JWK_SET_URI
- `shopping-cart-basket/k8s/base/configmap.yaml` — update OAUTH2_ISSUER_URI

---

## Before You Start

```
git pull origin k3d-manager-v1.4.6
```

Read this spec in full before touching any file.

**Work repos (separate from spec repo):**
- Spec is in: `k3d-manager` on branch `k3d-manager-v1.4.6`
- Code changes go in: `shopping-cart-order` and `shopping-cart-basket` — create branch `fix/keycloak-jwt-issuer` in each

---

## Problem

`shopping-cart-order` and `shopping-cart-basket` are deployed on `ubuntu-k3s` (AWS EC2 app
cluster). Their configmaps set:

```
OAUTH2_ISSUER_URI: http://keycloak.identity.svc.cluster.local/realms/shopping-cart
OAUTH2_JWK_SET_URI: http://keycloak.identity.svc.cluster.local/realms/shopping-cart/protocol/openid-connect/certs
```

`keycloak.identity.svc.cluster.local` is hub-cluster DNS (OrbStack, `k3d-k3d-cluster`).
From `ubuntu-k3s` pods it does NOT resolve — causing two failures:

1. **Issuer mismatch**: The Keycloak JWT `iss` claim is
   `http://keycloak.shopping-cart.local/realms/shopping-cart` (Keycloak's `frontendUrl` is
   unset; issuer is derived from request URL via `keycloak.shopping-cart.local`).
   Spring Security rejects all JWTs because `iss` ≠ `OAUTH2_ISSUER_URI`.

2. **JWK set unreachable**: Spring cannot fetch the JWK set to validate JWT signatures
   because `keycloak.identity.svc.cluster.local` is not resolvable from ubuntu-k3s.

Result: every API request requiring authentication returns 401/403, making order history
and basket endpoints unusable after login.

---

## Root cause

- `OAUTH2_ISSUER_URI` was set to the hub-cluster service DNS
  (`keycloak.identity.svc.cluster.local`) but Keycloak issues JWTs with
  `keycloak.shopping-cart.local` as the issuer
- The app cluster (`ubuntu-k3s`) has no connectivity to hub-cluster service DNS
- No cross-cluster DNS or networking is configured between the two clusters

---

## Fix

### Change 1 — `bin/acg-up`: add Step 10g.5 to wire Keycloak reachability on ubuntu-k3s

**Exact insertion point — between lines 1102 and 1104:**

```
fi                                                       ← line 1102 (closes Step 10g if _is_mac)

if _is_mac; then                                         ← line 1104 (Step 10h Cloudflare)
```

**Insert this block between lines 1102 and 1104:**

```bash

_info "[acg-up] Step 10g.5/14 — Wiring Keycloak cross-cluster reachability on ubuntu-k3s..."
_node_ip=$(kubectl get node --context ubuntu-k3s \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
if [[ -z "${_node_ip}" ]]; then
  _warn "[acg-up] Could not determine ubuntu-k3s node IP — skipping Keycloak cross-cluster tunnel"
else
  # SSH reverse tunnel: bind 127.0.0.1:18080 on ubuntu-k3s → Mac 127.0.0.1:80 (Keycloak via Istio)
  ssh -f -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
    -R 127.0.0.1:18080:127.0.0.1:80 ubuntu 2>/dev/null || \
    _warn "[acg-up] Keycloak reverse tunnel setup failed — JWT auth from app cluster may be unavailable"

  # Enable routing to loopback from non-loopback interfaces (needed for PREROUTING DNAT to 127.0.0.1)
  ssh ubuntu "sudo sysctl -w net.ipv4.conf.all.route_localnet=1" >/dev/null 2>&1 || true

  # PREROUTING DNAT: pod traffic to node-ip:80 → 127.0.0.1:18080 (SSH tunnel endpoint)
  # Remove any existing rule first to keep idempotent
  ssh ubuntu "sudo iptables -t nat -D PREROUTING -p tcp -d ${_node_ip} --dport 80 -j DNAT --to-destination 127.0.0.1:18080" >/dev/null 2>&1 || true
  ssh ubuntu "sudo iptables -t nat -A PREROUTING -p tcp -d ${_node_ip} --dport 80 -j DNAT --to-destination 127.0.0.1:18080" >/dev/null 2>&1 || \
    _warn "[acg-up] iptables DNAT rule for Keycloak failed — JWT auth from app cluster may be unavailable"

  # Patch CoreDNS on ubuntu-k3s to resolve keycloak.shopping-cart.local → node IP
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
    # Insert the hosts block before the first 'prometheus' line in the Corefile
    _new_corefile=$(echo "${_coredns_corefile}" | sed "/^    prometheus/i\\
${_coredns_patch}")
    kubectl patch configmap coredns -n kube-system --context ubuntu-k3s \
      --type merge -p "{\"data\":{\"Corefile\":$(echo "${_new_corefile}" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')}}" >/dev/null 2>&1 || \
      _warn "[acg-up] CoreDNS patch for keycloak.shopping-cart.local failed"
    kubectl rollout restart deployment/coredns -n kube-system --context ubuntu-k3s >/dev/null 2>&1 || true
    _info "[acg-up] CoreDNS updated: keycloak.shopping-cart.local → ${_node_ip} (via port 80 DNAT → 127.0.0.1:18080 → SSH tunnel → Keycloak)"
  fi
fi

```

---

### Change 2 — `shopping-cart-order/k8s/base/configmap.yaml`: fix OAUTH2 URIs

**Exact old block (lines 46–48):**
```yaml
  OAUTH2_ENABLED: "true"
  OAUTH2_ISSUER_URI: "http://keycloak.identity.svc.cluster.local/realms/shopping-cart"
  OAUTH2_JWK_SET_URI: "http://keycloak.identity.svc.cluster.local/realms/shopping-cart/protocol/openid-connect/certs"
```

**Exact new block:**
```yaml
  OAUTH2_ENABLED: "true"
  OAUTH2_ISSUER_URI: "http://keycloak.shopping-cart.local/realms/shopping-cart"
  OAUTH2_JWK_SET_URI: "http://keycloak.shopping-cart.local/realms/shopping-cart/protocol/openid-connect/certs"
```

---

### Change 3 — `shopping-cart-basket/k8s/base/configmap.yaml`: fix OAUTH2_ISSUER_URI

**Exact old block (lines 12–13):**
```yaml
  OAUTH2_ENABLED: "true"
  OAUTH2_ISSUER_URI: "http://keycloak.identity.svc.cluster.local:8080/realms/shopping-cart"
```

**Exact new block:**
```yaml
  OAUTH2_ENABLED: "true"
  OAUTH2_ISSUER_URI: "http://keycloak.shopping-cart.local/realms/shopping-cart"
```

---

## How the fix works

1. `bin/acg-up` sets up an SSH reverse tunnel from Mac → ubuntu-k3s EC2 node, binding
   `127.0.0.1:18080` on the EC2 node and forwarding to `127.0.0.1:80` on the Mac
   (where Keycloak is accessible via Istio IngressGateway).

2. An iptables PREROUTING DNAT rule on the ubuntu-k3s node redirects pod traffic destined
   for `node-ip:80` → `127.0.0.1:18080` (the SSH tunnel). `route_localnet=1` is required
   to allow DNAT to the loopback address.

3. CoreDNS on ubuntu-k3s is patched to resolve `keycloak.shopping-cart.local` → node IP.
   Pods resolve this hostname, connect to node-ip:80, get DNAT-redirected to the SSH
   tunnel endpoint, and ultimately reach Keycloak on the Mac.

4. OAUTH2_ISSUER_URI is updated to `keycloak.shopping-cart.local` — matching the actual
   JWT `iss` claim (`http://keycloak.shopping-cart.local/realms/shopping-cart`, confirmed
   via OIDC discovery endpoint).

---

## Files Changed

| Repo | File | Change |
|------|------|--------|
| `k3d-manager` | `bin/acg-up` | Add Step 10g.5: SSH tunnel + iptables + CoreDNS patch |
| `shopping-cart-order` | `k8s/base/configmap.yaml` | OAUTH2_ISSUER_URI + OAUTH2_JWK_SET_URI → keycloak.shopping-cart.local |
| `shopping-cart-basket` | `k8s/base/configmap.yaml` | OAUTH2_ISSUER_URI → keycloak.shopping-cart.local |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- SSH tunnel failure is `_warn`, not `_err` — must not block the rest of make up
- iptables rule is idempotent (DELETE before ADD)
- CoreDNS patch is idempotent (check before patch)
- shopping-cart repos: changes go on branch `fix/keycloak-jwt-issuer` in each repo

---

## Definition of Done

### k3d-manager
- [ ] Step 10g.5 block inserted between lines 1102 and 1104 (exact new block above)
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed to `k3d-manager-v1.4.6` with message:
      `fix(acg-up): wire Keycloak cross-cluster reachability on ubuntu-k3s`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds

### shopping-cart-order
- [ ] `k8s/base/configmap.yaml` OAUTH2 URIs updated to `keycloak.shopping-cart.local`
- [ ] Committed to branch `fix/keycloak-jwt-issuer` with message:
      `fix(config): update Keycloak JWT issuer URI to match actual iss claim`
- [ ] `git push origin fix/keycloak-jwt-issuer`

### shopping-cart-basket
- [ ] `k8s/base/configmap.yaml` OAUTH2_ISSUER_URI updated to `keycloak.shopping-cart.local` (no port)
- [ ] Committed to branch `fix/keycloak-jwt-issuer` with message:
      `fix(config): update Keycloak JWT issuer URI to match actual iss claim`
- [ ] `git push origin fix/keycloak-jwt-issuer`

### All repos
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHAs and task status
- [ ] Report back: commit SHA per repo + `git show <sha> --stat`

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT commit k3d-manager changes to `main`
- Do NOT modify any file outside the listed targets
- Do NOT change the `_warn` to `_err` — tunnel setup failure must not halt make up
- Do NOT modify `scripts/lib/` — all changes are in `bin/acg-up` only
- Do NOT commit shopping-cart changes to `main` — use branch `fix/keycloak-jwt-issuer`

---

## After the Fix

On next `make up`, Step 10g.5 will automatically:
- Set up the SSH tunnel
- Configure iptables DNAT on the ubuntu-k3s node
- Patch CoreDNS

To verify manually after `make up`:
```bash
# From inside a pod on ubuntu-k3s
kubectl run -it --rm --restart=Never -n shopping-cart-apps --context ubuntu-k3s tmptest \
  --image=busybox -- wget -qO- http://keycloak.shopping-cart.local/realms/shopping-cart/.well-known/openid-configuration 2>&1 | head -1
```

Expected: JSON starting with `{"realm":"shopping-cart",...}`
