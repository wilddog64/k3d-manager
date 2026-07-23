# Bugfix: v1.16.0 — ambient Cilium pod CIDR overlaps AWS VPC → cross-node networking dead

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/plugins/shopping_cart.sh`

---

## Problem

On the multi-node `k3s-aws` ambient sandbox, Istio ambient never converges: `istio-cni-node`
pods stay `0/1` (readiness `/readyz` → HTTP 503) and `ztunnel` is Ready on only the server node
(1/3). istio-cni logs on agent nodes show:

```
failed to list *v1.Pod: Get "https://10.43.0.1:443/api/v1/pods?...": dial tcp 10.43.0.1:443: i/o timeout
```

Agent-node pods cannot reach the Kubernetes API ClusterIP (`10.43.0.1`), so istio-cni can never
sync and never becomes ready — the ambient dataplane (istio-cni + ztunnel) does not come up.

**Root cause:** `_ambient_install_cilium` installs Cilium with `ipam=cluster-pool` but never pins
`ipam.operator.clusterPoolIPv4PodCIDRList`, so Cilium uses its **default `10.0.0.0/8`** pod pool.
The ACG AWS VPC is `10.0.0.0/16` and the node subnet is `10.0.1.0/24` — both **inside** Cilium's
`10.0.0.0/8` pool. Cilium therefore installs a `10.0.0.0/8 → cilium_host` route on every node, so
**all node-to-node traffic (node IPs are in `10.0.0.0/8`) is black-holed into the pod overlay**.
Result: agent→server and agent→agent are 100% unreachable (even ICMP), Cilium's
kubeProxyReplacement DNAT of `10.43.0.1:443 → 10.0.1.46:6443` (the internal API endpoint) times
out, and istio-cni cannot reach the API.

Proof captured live on the sandbox (2026-07-17):
- VPC CIDR `10.0.0.0/16`; Cilium `cluster-pool-ipv4-cidr: 10.0.0.0/8`; `ipam=cluster-pool`.
- `ip route get 10.0.1.46` on an agent → `10.0.1.46 dev cilium_host src 10.0.2.57` (node IP routed
  through the pod overlay, pod-CIDR source).
- `ping 10.0.1.46` and `ping 10.0.1.132` from an agent → 100% packet loss.
- Security group **allows** all intra-VPC traffic (`-1` from `10.0.0.0/16`); host `iptables INPUT`
  policy `ACCEPT`, no DROP; EC2 SourceDestCheck fine; subnet NACL allow-all. So this is **not** an
  SG / NACL / host-firewall issue — it is purely the Cilium pod-CIDR/VPC overlap.

Why Phase 1's e2e missed it: nodes go `Ready` because kubelet→API works via the server's **public**
IP (`k8sServiceHost=external_ip`), and Cilium pods run node-locally — neither path crosses the
broken overlay. Cross-node pod→ClusterIP networking was first exercised by the Phase 2 ambient
dataplane, which is what surfaced the collision.

---

## Reproduction

1. Provision the ambient sandbox: `K3S_AMBIENT_MESH=true K3S_AWS_SSM_ENABLED=false CLUSTER_PROVIDER=k3s-aws ./scripts/k3d-manager deploy_cluster --confirm` (VPC `10.0.0.0/16`).
2. From an agent node: `ping -c2 <server-internal-ip>` → 100% loss.
3. `kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.cluster-pool-ipv4-cidr}'` → `10.0.0.0/8` (overlaps the VPC).

Expected: agent↔server internal reachable; pod pool disjoint from the VPC CIDR.

---

## Fix

### Change 1 — `scripts/plugins/shopping_cart.sh`: pin a non-overlapping Cilium pod CIDR

Add an overridable pod-CIDR var next to the existing ambient vars (near line 1056, beside
`_AMBIENT_CILIUM_VERSION`).

**Exact old block (line 1056):**

```bash
_AMBIENT_CILIUM_VERSION="${AMBIENT_CILIUM_VERSION:-1.16.5}"
```

**Exact new block:**

```bash
_AMBIENT_CILIUM_VERSION="${AMBIENT_CILIUM_VERSION:-1.16.5}"
_AMBIENT_POD_CIDR="${AMBIENT_POD_CIDR:-10.42.0.0/16}"
```

Then add the `--set` to the helm install so Cilium's IPAM pool no longer defaults to `10.0.0.0/8`.

**Exact old block (lines 1082–1086):**

```bash
      --set operator.replicas=1 \
      --set cni.exclusive=false \
      --set kubeProxyReplacement=true \
      --set k8sServiceHost='${external_ip}' \
      --set k8sServicePort=6443
```

**Exact new block:**

```bash
      --set operator.replicas=1 \
      --set cni.exclusive=false \
      --set kubeProxyReplacement=true \
      --set ipam.operator.clusterPoolIPv4PodCIDRList='{${_AMBIENT_POD_CIDR}}' \
      --set k8sServiceHost='${external_ip}' \
      --set k8sServicePort=6443
```

> `10.42.0.0/16` matches the k3s default pod CIDR and is disjoint from the ACG VPC `10.0.0.0/16`.
> The helm list syntax is the curly-brace form `'{10.42.0.0/16}'`. `AMBIENT_POD_CIDR` lets a VPC
> that happens to use `10.42.x` override it. Because `${_AMBIENT_POD_CIDR}` is expanded into the
> remote heredoc that is already single-quoted at the helm layer, keep it inside the `'{...}'` so
> the brace list reaches helm literally.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/shopping_cart.sh` | add `_AMBIENT_POD_CIDR` var + `--set ipam.operator.clusterPoolIPv4PodCIDRList` to the Cilium helm install |

---

## Rules

- `shellcheck -S warning scripts/plugins/shopping_cart.sh` — zero new warnings.
- No other files touched. Do NOT alter `k8sServiceHost`/`k8sServicePort` (verified correct in Phase 1).
- Keep the existing `# shellcheck disable=SC2029` directive; the new `--set` is inside the same heredoc.

---

## Definition of Done

- [ ] `_AMBIENT_POD_CIDR` var added; `--set ipam.operator.clusterPoolIPv4PodCIDRList='{${_AMBIENT_POD_CIDR}}'` present in the helm install.
- [ ] `shellcheck -S warning scripts/plugins/shopping_cart.sh` clean; `bash -n scripts/plugins/shopping_cart.sh` clean.
- [ ] `./scripts/k3d-manager _agent_audit` exit 0.
- [ ] Committed and pushed to `k3d-manager-v1.16.0`.
- [ ] memory-bank updated with commit SHA and task status.

**Commit message (exact):**
```
fix(mesh): pin ambient Cilium pod CIDR to avoid AWS VPC 10.0.0.0/8 overlap
```

### Live re-verify — Claude runs this after the push (NOT Codex)

Re-provision (or reinstall Cilium on) the ambient sandbox, then confirm: agent↔server internal
`ping` succeeds; `cilium-config` `cluster-pool-ipv4-cidr` = `10.42.0.0/16`; istio-cni `1/1` on all
nodes; ztunnel `3/3`; ambient dataplane capture (label a ns `istio.io/dataplane-mode=ambient`, curl
between two pods, ztunnel logs show the captured connection).

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than `scripts/plugins/shopping_cart.sh`.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
- Do NOT change `k8sServiceHost`/`k8sServicePort` or any Phase 2 (ApplicationSet/plugin) file.
- Do NOT switch Cilium to `ipam.mode=kubernetes` — the minimal fix is pinning the cluster-pool CIDR.
