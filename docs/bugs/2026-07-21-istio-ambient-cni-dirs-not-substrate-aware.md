# Bugfix: v1.16.0 — ambient istio-cni CNI dirs are not CNI-substrate aware

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/etc/argocd/applicationsets/istio-ambient.yaml`, `scripts/plugins/istio_ambient.sh`

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — the Hostinger ambient
  section records the live evidence behind this spec.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/etc/argocd/applicationsets/istio-ambient.yaml` — the `istio-cni` list element and its
    `values` block scalar (`cni:` sub-block, currently lines ~34–36).
  - `scripts/plugins/istio_ambient.sh` — the `: "${VAR:=default}"` block, the `export` line, and the
    `envsubst '<var list>'` call. All three must stay in agreement.
  - `docs/bugs/2026-07-17-ambient-istio-cni-conf-bin-dir-mismatch.md` — the prior fix (`ce4d83f0`)
    that hardcoded the **Cilium** paths. That fix was correct for its cluster; do NOT revert it.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

`scripts/etc/argocd/applicationsets/istio-ambient.yaml` hardcodes **one** pair of istio-cni host
paths for **all** target clusters:

```yaml
              cni:
                cniConfDir: /etc/cni/net.d
                cniBinDir: /opt/cni/bin
```

Those are correct only when the target cluster's CNI is **Cilium** (`k3s-aws` with
`K3S_AMBIENT_MESH=true`, which installs Cilium at its default paths). They are **wrong** on a
cluster whose CNI is **k3s' bundled flannel**, where k3s keeps CNI state under `/var/lib/rancher`.

`k3s-hostinger` is exactly that case: `_hostinger_k3sup_install` runs a plain
`k3sup install --k3s-extra-args '--disable traefik --disable servicelb'` — bare flannel, no Cilium.
So `deploy_istio_ambient` against `ubuntu-hostinger` leaves `istio-cni-node` at `0/1` forever.

**Root cause:** the correct CNI conf/bin directories are a property of the target cluster's CNI
substrate, but the ApplicationSet expresses them as a constant. There is no way to deploy ambient to
a Cilium cluster and a flannel cluster from the same manifest.

### Live evidence (2026-07-21, rebuilt `ubuntu-hostinger`, k3s v1.36.2+k3s1, flannel)

istio-cni log, with the committed Cilium paths:

```
info  cni-agent  configuration requires updates, (re)writing CNI config file at "":
                 no networks found in /host/etc/cni/net.d
warn  cni-agent  Istio CNI is configured as chained plugin, but cannot find existing
                 CNI network config: no networks found in /host/etc/cni/net.d
```

On-node reality (`ssh ubuntu@srv1754834.hstgr.cloud`):

| Path | Contents |
|------|----------|
| `/etc/cni/net.d` | **empty** (stale dir dated Jun 16) |
| `/var/lib/rancher/k3s/agent/etc/cni/net.d` | `10-flannel.conflist` ← the only conflist |
| `/opt/cni/bin` | only `istio-cni` (istio's own binary; no other plugins) |
| `/var/lib/rancher/k3s/data/cni` | `bandwidth`, `bridge`, … → symlinks to the k3s multicall binary |

After overriding the live ApplicationSet to
`cniConfDir: /var/lib/rancher/k3s/agent/etc/cni/net.d` and `cniBinDir: /var/lib/rancher/k3s/data/cni`:
**`istio-cni-node` went `1/1` within ~2 min**, and ztunnel began receiving
`istio.workload.Address` XDS from istiod. That override lives only on the hub — the repo file is
unchanged, so the next `deploy_istio_ambient` re-breaks it. This spec makes it durable.

---

## Reproduction

1. Build a bare-flannel k3s app cluster: `CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager deploy_cluster --confirm`.
2. `APP_CLUSTER_NAME=ubuntu-hostinger ./scripts/k3d-manager deploy_istio_ambient --confirm`.
3. `kubectl --context ubuntu-hostinger -n istio-system get pods` → `istio-cni-node` stuck `0/1`.
4. `kubectl --context ubuntu-hostinger -n istio-system logs -l k8s-app=istio-cni-node`
   → `no networks found in /host/etc/cni/net.d`.

Expected: `istio-cni-node` `1/1` on both Cilium-backed and flannel-backed target clusters.

---

## Fix

Parameterize the two paths, keeping the **current Cilium values as the defaults** so existing
`k3s-aws` behaviour is byte-for-byte unchanged when the new vars are unset.

### Change 1 — `scripts/etc/argocd/applicationsets/istio-ambient.yaml`: substitute the CNI dirs

**Exact old block (lines 34–36):**

```yaml
              cni:
                cniConfDir: /etc/cni/net.d
                cniBinDir: /opt/cni/bin
```

**Exact new block:**

```yaml
              cni:
                cniConfDir: ${AMBIENT_CNI_CONF_DIR}
                cniBinDir: ${AMBIENT_CNI_BIN_DIR}
```

### Change 2 — `scripts/plugins/istio_ambient.sh`: default, export, and substitute the new vars

**Exact old block:**

```bash
  : "${AMBIENT_ISTIO_VERSION:=1.24.2}"
  export ARGOCD_NAMESPACE APP_CLUSTER_NAME AMBIENT_ISTIO_VERSION
```

**Exact new block:**

```bash
  : "${AMBIENT_ISTIO_VERSION:=1.24.2}"
  : "${AMBIENT_CNI_CONF_DIR:=/etc/cni/net.d}"
  : "${AMBIENT_CNI_BIN_DIR:=/opt/cni/bin}"
  export ARGOCD_NAMESPACE APP_CLUSTER_NAME AMBIENT_ISTIO_VERSION
  export AMBIENT_CNI_CONF_DIR AMBIENT_CNI_BIN_DIR
```

### Change 3 — `scripts/plugins/istio_ambient.sh`: add the vars to the `envsubst` allowlist

`envsubst` only replaces variables named in its argument. If they are not added there, the new
`${AMBIENT_CNI_*}` placeholders reach the cluster **literally** and istio-cni breaks on both
providers. Change the existing single-quoted variable list:

**Exact old text:**

```bash
    if envsubst '$ARGOCD_NAMESPACE $APP_CLUSTER_NAME $AMBIENT_ISTIO_VERSION' < "${_appset}" \
```

**Exact new text:**

```bash
    if envsubst '$ARGOCD_NAMESPACE $APP_CLUSTER_NAME $AMBIENT_ISTIO_VERSION $AMBIENT_CNI_CONF_DIR $AMBIENT_CNI_BIN_DIR' < "${_appset}" \
```

> If the same `envsubst '…'` variable list appears more than once in the file (e.g. a dry-run
> branch), apply the identical replacement to **every** occurrence.

### Change 4 — `scripts/plugins/istio_ambient.sh`: correct the stale help precondition

The help text asserts Cilium is required. That is now false — ambient is proven working on k3s
flannel. Replace the Cilium precondition line:

**Exact old text:**

```
  - The target cluster's CNI is Cilium with cni.exclusive=false (deploy with K3S_AMBIENT_MESH=true).
```

**Exact new text:**

```
  - AMBIENT_CNI_CONF_DIR/AMBIENT_CNI_BIN_DIR match the target cluster's CNI substrate.
    Defaults suit Cilium (/etc/cni/net.d, /opt/cni/bin); for bare k3s flannel use
    /var/lib/rancher/k3s/agent/etc/cni/net.d and /var/lib/rancher/k3s/data/cni.
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/applicationsets/istio-ambient.yaml` | istio-cni conf/bin dirs → `${AMBIENT_CNI_CONF_DIR}` / `${AMBIENT_CNI_BIN_DIR}` |
| `scripts/plugins/istio_ambient.sh` | default + export the two vars, add both to `envsubst`, fix stale Cilium precondition in help |

---

## Rules

- `shellcheck -S warning scripts/plugins/istio_ambient.sh` — zero new warnings.
- YAML must still parse: `python3 -c 'import yaml,sys; list(yaml.safe_load_all(open("scripts/etc/argocd/applicationsets/istio-ambient.yaml")))'`
  (the `${…}` placeholders are inside a block scalar, so this parses fine).
- Defaults must reproduce today's committed values exactly — with the new vars unset, the rendered
  output must be identical to the current file. Verify:
  `APP_CLUSTER_NAME=x AMBIENT_ISTIO_VERSION=1.24.2 ARGOCD_NAMESPACE=cicd envsubst '…' < scripts/etc/argocd/applicationsets/istio-ambient.yaml | grep -A2 'cni:'`
  → must show `/etc/cni/net.d` and `/opt/cni/bin`.
- Do NOT change the base/istiod/ztunnel elements, the CPU requests, or the `profile:` values.
- Do NOT switch `helm.values` block scalars to `helm.parameters`.

---

## Definition of Done

- [ ] Appset istio-cni element uses `${AMBIENT_CNI_CONF_DIR}` / `${AMBIENT_CNI_BIN_DIR}`.
- [ ] `istio_ambient.sh` defaults both vars to the current Cilium paths and exports them.
- [ ] Both vars appear in **every** `envsubst '…'` variable list in the file.
- [ ] Help text no longer claims Cilium is a precondition.
- [ ] Unset-var render is byte-identical to today's output (checked per Rules).
- [ ] `shellcheck -S warning` clean; YAML parses.
- [ ] Committed and pushed to `k3d-manager-v1.16.0`.
- [ ] memory-bank updated with commit SHA and task status.

**Commit message (exact):**
```
fix(mesh): make ambient istio-cni conf/bin dirs CNI-substrate aware
```

### Live re-verify — Claude runs this after the push (NOT Codex)

Re-run `deploy_istio_ambient` against `ubuntu-hostinger` with the rancher paths exported, confirm
the generated DaemonSet mounts them, `istio-cni-node` reaches `1/1`, and the ambient dataplane
capture passes (HBONE on :15008 + mutual SPIFFE mTLS).

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than the two listed targets.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
- Do NOT revert `ce4d83f0` or change the **default** values — Cilium clusters must keep working.
- Do NOT add Cilium to the `k3s-hostinger` provider as the fix; flannel + ambient is proven working.
