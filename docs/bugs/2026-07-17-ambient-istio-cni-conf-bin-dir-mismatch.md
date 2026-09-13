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

---

## Recurrence 2026-09-13 — hub (k3d/flannel) as app cluster

**Status:** live hub FIXED 2026-09-13 (operator reapply); code default still needs a spec

After the 2026-09-11 hub rebuild the hub fills the `ubuntu-k3s` app-cluster role,
but the hub `istio-ambient` ApplicationSet (created `2026-09-10T23:57:18Z`) was
rendered with the Cilium defaults from `deploy_istio_ambient`
(`scripts/plugins/istio_ambient.sh:25-26`): `cniConfDir: /etc/cni/net.d`,
`cniBinDir: /opt/cni/bin`. The hub runs k3d flannel, so all four
`istio-cni-node` pods sit `Running 0/1` (readiness 503) with the original
signature:

```text
Istio CNI is configured as chained plugin, but cannot find existing CNI network config:
no networks found in /host/etc/cni/net.d
```

`kubectl rollout restart ds/istio-cni-node` (operator, 2026-09-13) did not help —
the paths are wrong, not the process. Measured on `k3d-k3d-cluster-agent-1`:

```text
/etc/cni/net.d:                              (empty)
/var/lib/rancher/k3s/agent/etc/cni/net.d:    10-flannel.conflist
/var/lib/rancher/k3s/data/cni:               does not exist
/bin:                                        bridge cni flannel host-local loopback portmap
containerd config.toml:                      bin_dir = "/bin"
```

So the k3d paths are conf `/var/lib/rancher/k3s/agent/etc/cni/net.d` and bin
`/bin`. The help text in `istio_ambient.sh` (`/var/lib/rancher/k3s/data/cni`) is
right for bare k3s (hostinger, `k3s-hostinger.sh:816-817`) but wrong for k3d.
`ztunnel` is 4/4 Ready and `shopping-cart-apps` is ambient-labelled, but with
istio-cni never ready no new pod can be enrolled into the mesh, so ambient
traffic capture on the hub should be treated as not in effect until fixed.

Operator reapply (hub ArgoCD, then Argo re-renders the DaemonSet):

```bash
AMBIENT_CNI_CONF_DIR=/var/lib/rancher/k3s/agent/etc/cni/net.d \
AMBIENT_CNI_BIN_DIR=/bin \
  ./scripts/k3d-manager deploy_istio_ambient
```

Verify: DaemonSet `cni-net-dir`/`cni-bin-dir` hostPaths match, `istio-cni-node`
4/4 Ready, then restart `shopping-cart-apps` workloads one at a time and confirm
ztunnel HBONE logs.

Code follow-up (spec first, `scripts/plugins/` is guarded): choose
`AMBIENT_CNI_CONF_DIR`/`AMBIENT_CNI_BIN_DIR` defaults from the app cluster's
provider (`k3d` → the k3d paths above) instead of always defaulting to Cilium,
and correct the help text.

### Resolution 2026-09-13

Operator ran the reapply (the dispatcher's `deploy_*` gate requires `--confirm`;
env vars alone do not satisfy it). Verified by Claude:

- DaemonSet hostPaths `cni-net-dir=/var/lib/rancher/k3s/agent/etc/cni/net.d`,
  `cni-bin-dir=/bin`; `istio-cni-node` 4/4 Ready; `istio-cni-ubuntu-k3s` Synced/Healthy.
- `10-flannel.conflist` now chains `flannel, portmap, bandwidth, istio-cni`;
  `/bin/istio-cni` present on the node.
- No workload restart was needed: the CNI agent re-enrolled the running pods
  (`inpod::statemanager pod received, starting proxy` at 12:19:52Z) and
  `istioctl ztunnel-config workloads --workload-namespace shopping-cart-apps`
  lists basket, frontend, order, product-catalog as `HBONE`.
- Public frontend `/api/products`, Keycloak realm, Grafana health still 200.

## Spec 2026-09-13 — provider-aware `AMBIENT_CNI_*` defaults (READY FOR CODEX)

**Branch:** `k3d-manager-v1.33.0`
**Targets:** `scripts/plugins/istio_ambient.sh`, `scripts/tests/plugins/istio_ambient_cni_dirs.bats` (new), `CHANGELOG.md`

### Before You Start

- `git pull origin k3d-manager-v1.33.0`; read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- Read in full: `scripts/plugins/istio_ambient.sh` and `_hostinger_reapply_gitops_applicationsets` in `scripts/lib/providers/k3s-hostinger.sh` (~808). That function already exports explicit hostinger paths and must keep winning.
- The registration Secret for the hub in-cluster target carries the label `k3d-manager/provider=k3d` and has `.data.name` (base64) `ubuntu-k3s`.

### Change

In `deploy_istio_ambient`, replace:

```bash
  : "${AMBIENT_CNI_CONF_DIR:=/etc/cni/net.d}"
  : "${AMBIENT_CNI_BIN_DIR:=/opt/cni/bin}"
```

with:

```bash
  if [[ -z "${AMBIENT_CNI_CONF_DIR:-}" || -z "${AMBIENT_CNI_BIN_DIR:-}" ]]; then
    local _cni_provider _cni_dirs
    _cni_provider="${AMBIENT_CNI_PROVIDER:-$(_istio_ambient_target_provider "${ARGOCD_CONTEXT}" "${ARGOCD_NAMESPACE}" "${APP_CLUSTER_NAME}")}"
    _cni_dirs="$(_istio_ambient_cni_dirs "${_cni_provider}")"
    : "${AMBIENT_CNI_CONF_DIR:=${_cni_dirs%% *}}"
    : "${AMBIENT_CNI_BIN_DIR:=${_cni_dirs##* }}"
    _info "[istio_ambient] CNI dirs for provider '${_cni_provider:-unknown}': ${AMBIENT_CNI_CONF_DIR} ${AMBIENT_CNI_BIN_DIR}"
  fi
```

Append after `deploy_istio_ambient`:

```bash
function _istio_ambient_cni_dirs() {
  case "${1:-}" in
    k3d)           printf '%s %s\n' /var/lib/rancher/k3s/agent/etc/cni/net.d /bin ;;
    k3s-hostinger) printf '%s %s\n' /var/lib/rancher/k3s/agent/etc/cni/net.d /var/lib/rancher/k3s/data/cni ;;
    *)             printf '%s %s\n' /etc/cni/net.d /opt/cni/bin ;;
  esac
}

function _istio_ambient_target_provider() {
  local context="$1" namespace="$2" cluster_name="$3" secret name
  while IFS= read -r secret; do
    [[ -z "${secret}" ]] && continue
    name="$(_kubectl --no-exit --context "${context}" -n "${namespace}" get "${secret}" -o jsonpath='{.data.name}' 2>/dev/null | base64 --decode 2>/dev/null || true)"
    if [[ "${name}" == "${cluster_name}" ]]; then
      _kubectl --no-exit --context "${context}" -n "${namespace}" get "${secret}" -o jsonpath='{.metadata.labels.k3d-manager/provider}' 2>/dev/null || true
      return 0
    fi
  done < <(_kubectl --no-exit --context "${context}" -n "${namespace}" get secrets -l argocd.argoproj.io/secret-type=cluster -o name 2>/dev/null)
}
```

In the help text, replace the two lines starting with `Defaults suit Cilium` with:

```text
    Defaults follow the target's k3d-manager/provider label (override with
    AMBIENT_CNI_PROVIDER): k3d → /var/lib/rancher/k3s/agent/etc/cni/net.d + /bin;
    k3s-hostinger → /var/lib/rancher/k3s/agent/etc/cni/net.d + /var/lib/rancher/k3s/data/cni;
    anything else (Cilium) → /etc/cni/net.d + /opt/cni/bin.
```

### Tests — `scripts/tests/plugins/istio_ambient_cni_dirs.bats` (pure logic)

- `_istio_ambient_cni_dirs k3d` prints `/var/lib/rancher/k3s/agent/etc/cni/net.d /bin`.
- `_istio_ambient_cni_dirs k3s-hostinger` prints the hostinger pair.
- `_istio_ambient_cni_dirs ""` and `_istio_ambient_cni_dirs k3s-aws` print `/etc/cni/net.d /opt/cni/bin`.
- `deploy_istio_ambient` with both `AMBIENT_CNI_*` preset and `_kubectl` stubbed never calls `_istio_ambient_target_provider`; assert by stubbing it to write a marker file.

### Definition of Done

- [ ] `shellcheck -x scripts/plugins/istio_ambient.sh` clean
- [ ] `bats scripts/tests/plugins/istio_ambient_cni_dirs.bats` green — paste the summary
- [ ] CHANGELOG `## [Unreleased]` → `### Fixed`: "deploy_istio_ambient picks CNI conf/bin dirs from the target's provider label (k3d hub no longer gets Cilium paths)"
- [ ] Commit message verbatim: `fix(istio-ambient): provider-aware istio-cni conf/bin dir defaults`
- [ ] Pushed to `origin/k3d-manager-v1.33.0`; report the SHA

### What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`
- Do NOT modify files outside the targets (leave `k3s-hostinger.sh` untouched)
- Do NOT run anything against a live cluster
