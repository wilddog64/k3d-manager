# Bugfix: v1.16.0 — ambient istio-cni conf/bin dir mismatch (Cilium default paths)

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/etc/argocd/applicationsets/istio-ambient.yaml`

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "istio-cni conf/bin dir mismatch" OPEN blocker on branch `k3d-manager-v1.16.0` (the last
  blocker before the ambient dataplane is fully green on `k3s-aws`).
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/etc/argocd/applicationsets/istio-ambient.yaml` — the whole istio-cni list element,
    especially the `helm.values` block scalar and the `cni:` sub-block (currently lines ~34–36).
  - `scripts/plugins/shopping_cart.sh` — `_ambient_install_cilium`: confirm it sets **no**
    `cni.confPath` / `cni.binPath` overrides, so Cilium uses its defaults (`/etc/cni/net.d`,
    `/opt/cni/bin`). This is why istio-cni must be aligned to those same paths.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

On the multi-node `k3s-aws` ambient sandbox (after the Cilium pod-CIDR fix `bcc87f1c`), the
ambient control plane comes up except **`istio-cni-node` stays `0/1` on every node forever**
(readiness `/readyz` → HTTP 503). With istio-cni not ready, pods in any ambient-labeled namespace
fail to start:

```
istio-cni log:
  Istio CNI is configured as chained plugin, but cannot find existing CNI network config:
  no networks found in /host/etc/cni/net.d
  Waiting for CNI network config file to be written in /host/etc/cni/net.d...

pod-sandbox event (ambient-labeled ns):
  failed to setup network for sandbox ...: plugin type="istio-cni" name="istio-cni" failed (add):
  failed to find plugin "istio-cni" in path [/opt/cni/bin]
```

**Root cause:** the istio-ambient ApplicationSet pins istio-cni to the **standard k3s** CNI paths
(`cniConfDir: /var/lib/rancher/k3s/agent/etc/cni/net.d`, `cniBinDir: /var/lib/rancher/k3s/data/current/bin`),
but `_ambient_install_cilium` (`scripts/plugins/shopping_cart.sh`) installs Cilium with its **default**
CNI paths — it sets **no** `cni.confPath` / `cni.binPath` overrides. So on this cluster:

- Cilium writes its conflist to **`/etc/cni/net.d/05-cilium.conflist`** (host default), and its
  plugin binary to **`/opt/cni/bin`**.
- k3s reads CNI config from **`/etc/cni/net.d`** (verified: the rancher net.d dir is empty; the sole
  conflist on the node is `/etc/cni/net.d/05-cilium.conflist`; pods get Cilium networking).
- istio-cni (chained) is pointed at the **empty** rancher `net.d`, so it never finds a conflist to
  chain onto → never writes its chained config → `/readyz` 503 → `0/1`. And even once chained, the
  runtime resolves the `istio-cni` plugin against `/opt/cni/bin` (Cilium's bin dir), where the
  istio-cni binary was **not** installed (it went to the k3s data bin dir) → pod-sandbox creation
  fails with `failed to find plugin "istio-cni" in path [/opt/cni/bin]`.

Both istio-cni paths must match where **this** Cilium install actually puts its conf and binary:
`/etc/cni/net.d` and `/opt/cni/bin`.

Proof captured live on the sandbox (2026-07-17, acct `975201825692`):
- `/etc/cni/net.d/05-cilium.conflist` present; `/var/lib/rancher/k3s/agent/etc/cni/net.d` **empty**.
- After changing istio-cni to `cniConfDir: /etc/cni/net.d`: istio-cni chained
  (`CNI config file "" preempted by "/host/etc/cni/net.d/05-cilium.conflist" … initial installation complete`)
  but pod-sandbox still failed with `failed to find plugin "istio-cni" in path [/opt/cni/bin]`.
- After **also** changing `cniBinDir: /opt/cni/bin`: **istio-cni `1/1` on all 3 nodes**, and the
  ambient dataplane capture passed (ns `istio.io/dataplane-mode=ambient`, curl client→server HTTP
  200, ztunnel access log shows HBONE + mutual-SPIFFE mTLS).

Verified live as an ApplicationSet override on the hub; the **repo file is unchanged**, so when
ArgoCD re-syncs the ApplicationSet from git it will overwrite the override and re-break istio-cni.
This spec makes the fix durable.

---

## Reproduction

1. Provision the ambient sandbox and deploy istio ambient via ArgoCD (Phase 2 flow):
   `register_app_cluster` → `deploy_istio_ambient --confirm` on hub `k3d-k3d-cluster`.
2. `kubectl --context ubuntu-k3s -n istio-system get pods` → `istio-cni-node` stuck `0/1`.
3. `kubectl --context ubuntu-k3s -n istio-system logs <istio-cni-pod>` → `no networks found in /host/etc/cni/net.d`.

Expected: istio-cni `1/1` on all nodes; ambient pods schedule.

---

## Fix

### Change 1 — `scripts/etc/argocd/applicationsets/istio-ambient.yaml`: point istio-cni at Cilium's actual CNI paths

**Exact old block (lines 34–36):**

```yaml
              cni:
                cniConfDir: /var/lib/rancher/k3s/agent/etc/cni/net.d
                cniBinDir: /var/lib/rancher/k3s/data/current/bin
```

**Exact new block:**

```yaml
              cni:
                cniConfDir: /etc/cni/net.d
                cniBinDir: /opt/cni/bin
```

> These are the host paths where `_ambient_install_cilium` (Cilium default `cni.confPath`/`cni.binPath`)
> writes its conflist and plugin binary, and where k3s reads CNI config. istio-cni (chained) must
> use the same directories to find Cilium's conflist and to install its binary where the runtime
> resolves it. Do NOT reintroduce the rancher `/var/lib/rancher/k3s/...` paths unless
> `_ambient_install_cilium` is also changed to pin Cilium's `cni.confPath`/`cni.binPath` to them
> (keep both sides in agreement — the minimal fix is aligning istio-cni to the Cilium defaults).

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/applicationsets/istio-ambient.yaml` | istio-cni `cniConfDir` → `/etc/cni/net.d`, `cniBinDir` → `/opt/cni/bin` |

---

## Rules

- YAML must still parse (`python -c 'import yaml,sys; list(yaml.safe_load_all(open(...)))'` or `ruby -ryaml`).
- No other files touched. Do NOT change any other ApplicationSet element (base/istiod/ztunnel) or the profile values.
- Keep the `helm.values` block-scalar structure (not `helm.parameters`).

---

## Definition of Done

- [ ] istio-cni element `cniConfDir: /etc/cni/net.d` and `cniBinDir: /opt/cni/bin`.
- [ ] YAML parses clean; no other element changed.
- [ ] Committed and pushed to `k3d-manager-v1.16.0`.
- [ ] memory-bank updated with commit SHA and task status.

**Commit message (exact):**
```
fix(mesh): point ambient istio-cni at Cilium default CNI conf/bin dirs
```

### Live re-verify — Claude runs this after the push (NOT Codex)

Re-sync the istio-ambient ApplicationSet from the corrected repo file on the hub, confirm the
generated `istio-cni-node` DaemonSet mounts `cni-net-dir → /etc/cni/net.d` and
`cni-bin-dir → /opt/cni/bin`, istio-cni `1/1` on all nodes, and the ambient dataplane capture still
passes (labeled ns, curl between two pods, ztunnel HBONE + mTLS log).

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than `scripts/etc/argocd/applicationsets/istio-ambient.yaml`.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
- Do NOT change the base/istiod/ztunnel elements or switch `helm.values` to `helm.parameters`.
- Do NOT switch Cilium to the rancher CNI paths as the fix — align istio-cni to the Cilium defaults instead.
