# Bugfix: v1.16.0 — k3s-aws `make up` deploys the ambient mesh onto a flannel cluster (Cilium never installed)

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/lib/providers/k3s-aws.sh`
**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is **OPEN blocker 1**
  ("istio-cni 0/1 on `make up` — flannel-vs-Cilium mismatch") on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/lib/providers/k3s-aws.sh` — the `_provider_k3s_aws_deploy_cluster` function,
    especially the `_ready_nodes` check and the `deploy_app_cluster --confirm` call (currently
    lines ~169–174), and the tunnel-mode autoselect just above it (`_provider_k3s_aws_autoselect_tunnel_mode`,
    line ~164) which resolves and exports `K3S_AWS_SSM_ENABLED` BEFORE the `deploy_app_cluster` call.
  - `scripts/plugins/shopping_cart.sh` — `deploy_app_cluster` (line ~1102): the SSM early-return
    at line ~1131, the `K3S_AMBIENT_MESH` flannel-disable at lines ~1160–1163, and the
    `_ambient_install_cilium` call at line ~1183. Also `_ssm_bootstrap_k3s` line ~1246–1249: it
    **hard-errors** when `K3S_AMBIENT_MESH=true` under SSM — this is why the fix must NOT set the
    flag on the SSM path.
  - `scripts/plugins/istio_ambient.sh` line ~12 — documents that ambient requires "Cilium with
    cni.exclusive=false (deploy with K3S_AMBIENT_MESH=true)".
- Implement exactly what is written — no interpretation, no scope expansion. **Minimal patch only.**

---

## Problem

`make up CLUSTER_PROVIDER=k3s-aws` always deploys the `istio-ambient` ApplicationSet
(istiod / ztunnel / istio-cni) via the generic appset loop, but it provisions the k3s cluster with
the **default k3s flannel CNI** — Cilium is never installed. So istio-cni (a *chained* plugin, now
correctly pointed at Cilium's `/etc/cni/net.d` by `ce4d83f0`) finds no base conflist and stays
`0/1` forever:

```
istio-cni log:
  no networks found in /host/etc/cni/net.d
  Istio CNI is configured as chained plugin, but cannot find existing CNI network config
  Waiting for CNI network config file to be written in /host/etc/cni/net.d...
```

**Live evidence (2026-07-19, fresh k3s-aws rebuild, SSH-tunnel sandbox):**
- istiod `1/1`, ztunnel `1/1` ×3 (both fixed by `ce4d83f0`), but **istio-cni-node `0/1` ×3**.
- No cilium pods; no `cilium-config` ConfigMap; pod IPs are `10.42.x` (flannel default).
- Node `ip-10-0-1-14`: `/etc/cni/net.d` **empty**; the real base conflist is
  `10-flannel.conflist` at `/var/lib/rancher/k3s/agent/etc/cni/net.d`; `/opt/cni/bin` has the
  `istio-cni` binary (copied fine by the fixed appset).

**Root cause:** the k3s-aws up flow calls `deploy_app_cluster --confirm`
(`scripts/lib/providers/k3s-aws.sh:173`) **without** `K3S_AMBIENT_MESH=true`, so
`_ambient_install_cilium` (`shopping_cart.sh:1183`, gated on that flag) is skipped and the cluster
runs flannel. `ce4d83f0` is correct for the intended Cilium design; the gap is that the automated
e2e never turns Cilium on. Owner decision (2026-07-19) = **Direction A: install Cilium in the
k3s-aws e2e** by defaulting `K3S_AMBIENT_MESH=true` in the up flow (keep `ce4d83f0`).

**SSM safety constraint:** `deploy_app_cluster` early-returns into `_ssm_bootstrap_k3s` on the SSM
path, and `_ssm_bootstrap_k3s` **hard-errors** (`shopping_cart.sh:1247`) when `K3S_AMBIENT_MESH=true`
("unsupported in this release"). So the fix must set the flag to `true` **only when SSM is
disabled**; under SSM it must force `false` (ambient stays unsupported this release — flannel), or
`make up` would fail at cluster provisioning whenever tunnel autoselect picks SSM.

---

## Reproduction

1. `make down CLUSTER_PROVIDER=k3s-aws` then `make up CLUSTER_PROVIDER=k3s-aws` (SSH-tunnel sandbox).
2. `kubectl --context ubuntu-k3s -n istio-system get pods` → `istio-cni-node` `0/1` ×3.
3. `kubectl --context ubuntu-k3s get pods -A | grep -i cilium` → nothing (flannel cluster).

Expected: Cilium installed, istio-cni chains onto Cilium's conflist → `1/1` on all nodes.

---

## Fix

### Change 1 — `scripts/lib/providers/k3s-aws.sh`: default `K3S_AMBIENT_MESH=true` for the up flow (except SSM)

Default the ambient flag to `true` so `deploy_app_cluster` installs Cilium, honoring an explicit
`K3S_AMBIENT_MESH` override from the environment, and forcing `false` under SSM to avoid the
`_ssm_bootstrap_k3s` hard-error. `_provider_k3s_aws_autoselect_tunnel_mode` (called just above)
has already exported `K3S_AWS_SSM_ENABLED` by this point.

**Exact old block (lines 169–174):**

```bash
  if [[ "${_ready_nodes}" -ge 3 ]]; then
    _info "[k3s-aws] k3s nodes already Ready (${_ready_nodes}/3) — skipping deploy_app_cluster"
  else
    _info "[k3s-aws] Installing k3s server + joining agents..."
    UBUNTU_K3S_AGENT_HOSTS="ubuntu-1,ubuntu-2" deploy_app_cluster --confirm || return 1
  fi
```

**Exact new block:**

```bash
  if [[ "${_ready_nodes}" -ge 3 ]]; then
    _info "[k3s-aws] k3s nodes already Ready (${_ready_nodes}/3) — skipping deploy_app_cluster"
  else
    _info "[k3s-aws] Installing k3s server + joining agents..."
    local _ambient_mesh="${K3S_AMBIENT_MESH:-true}"
    if [[ "${_ambient_mesh}" == "true" && "${K3S_AWS_SSM_ENABLED:-false}" == "true" ]]; then
      _info "[k3s-aws] SSM tunnel mode active — ambient mesh (Cilium) unsupported this release; provisioning with flannel"
      _ambient_mesh="false"
    fi
    UBUNTU_K3S_AGENT_HOSTS="ubuntu-1,ubuntu-2" K3S_AMBIENT_MESH="${_ambient_mesh}" deploy_app_cluster --confirm || return 1
  fi
```

Do NOT touch any other line of `_provider_k3s_aws_deploy_cluster`, any other function, any appset
YAML, `shopping_cart.sh`, or `istio_ambient.sh`.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-aws.sh` | k3s-aws up flow defaults `K3S_AMBIENT_MESH=true` (installs Cilium) for `deploy_app_cluster`, forcing `false` under SSM |

---

## Rules

- **Appearance gate:** `grep -c 'K3S_AMBIENT_MESH:-true' scripts/lib/providers/k3s-aws.sh` → **`1`**
- **Appearance gate:** `grep -c 'K3S_AMBIENT_MESH="${_ambient_mesh}"' scripts/lib/providers/k3s-aws.sh` → **`1`**
- `shellcheck -S warning scripts/lib/providers/k3s-aws.sh` — **0 warnings** (baseline on
  `origin/k3d-manager-v1.16.0` is 0; must stay 0).
- `bats scripts/tests/lib/k3s_aws_provider.bats` — all tests pass (capture the `N tests, 0 failures`
  line). Do NOT add or modify tests — the existing suite exercises the `_ready_nodes >= 3` skip
  branch; the else branch has cluster-side dependencies (autossh tunnel, a 300s node-Ready wait)
  that the "pure logic only" bats policy does not mock. Keeping the patch minimal is required.
- `./scripts/k3d-manager _agent_audit` — exit 0
- `git show --stat` shows exactly ONE file changed
- No other files touched

---

## Definition of Done

- [ ] `_provider_k3s_aws_deploy_cluster` sets `local _ambient_mesh="${K3S_AMBIENT_MESH:-true}"`,
      forces it to `false` under `K3S_AWS_SSM_ENABLED=true`, and passes
      `K3S_AMBIENT_MESH="${_ambient_mesh}"` on the `deploy_app_cluster` call
- [ ] `grep -c 'K3S_AMBIENT_MESH:-true'` → `1`; `grep -c 'K3S_AMBIENT_MESH="${_ambient_mesh}"'` → `1` (record outputs)
- [ ] `shellcheck -S warning scripts/lib/providers/k3s-aws.sh` — 0 warnings (record baseline + after)
- [ ] `bats scripts/tests/lib/k3s_aws_provider.bats` — 0 failures (record the summary line)
- [ ] `_agent_audit` exit 0
- [ ] `git show --stat` shows exactly ONE file changed
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status (separate commit)

**Commit message (exact):**
```
fix(k3s-aws): default K3S_AMBIENT_MESH=true in up flow so Cilium installs for ambient
```

### Live re-verify — Claude runs this after the push (NOT Codex)

Full **fresh** rebuild (`make down` then `make up CLUSTER_PROVIDER=k3s-aws` — the else branch only
runs when nodes are not already Ready). Confirm: Cilium pods Running on `ubuntu-k3s`; the node's
`/etc/cni/net.d` now holds a Cilium conflist; `istio-cni-node` `1/1` on all 3 nodes; ztunnel `1/1`;
and the ambient dataplane capture passes (labeled ns `istio.io/dataplane-mode=ambient`, curl
pod→pod HTTP 200, ztunnel HBONE + mTLS access log). Then re-check the two broken app services
(Frontend + Product images).

---

## What NOT to Do

- Do NOT change `ce4d83f0` / `istio-ambient.yaml` — the Cilium paths are correct for this direction.
- Do NOT modify `shopping_cart.sh`, `istio_ambient.sh`, `vars.sh`, or any appset YAML.
- Do NOT set `K3S_AMBIENT_MESH=true` unconditionally — it MUST be forced `false` under SSM
  (`_ssm_bootstrap_k3s` hard-errors otherwise).
- Do NOT add or edit BATS tests.
- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the one listed target.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
