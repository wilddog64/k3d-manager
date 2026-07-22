# Bugfix: v1.16.0 — `make status` reports no service-mesh or CNI health

**Branch:** `k3d-manager-v1.16.0`
**Files:** `bin/cluster-status`

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — the Hostinger ambient
  section records the incident this spec prevents recurring.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `bin/cluster-status` — the whole file. Note the section convention
    (`echo ""` then `echo "=== <Name> (${APP_CONTEXT}) ==="`), how `APP_CONTEXT` / `INFRA_CONTEXT`
    are resolved, and how existing sections degrade when a resource is absent (they print a short
    note, they do not `exit`).
  - The `=== App Observability (${APP_CONTEXT}) ===` section (currently ~lines 134–165) — the new
    section goes immediately after it and must match its style.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

`bin/cluster-status` (435 lines) contains **no** check for istio, ztunnel, istio-cni, Cilium, or
ambient namespace enrollment — `grep -n 'istio\|cilium\|ztunnel\|ambient' bin/cluster-status`
returns nothing. `make status` therefore reports a cluster as healthy while its service mesh is
entirely broken.

This is not hypothetical. On `ubuntu-hostinger` the mesh was non-functional for **~3 days** and
`make status` never indicated a problem. Two distinct faults were invisible:

1. **`istio-cni-node` stuck `0/1`** — the ApplicationSet pinned Cilium's CNI paths on a
   bare-flannel k3s host, so istio-cni never chained.
   (See `docs/bugs/2026-07-21-istio-ambient-cni-dirs-not-substrate-aware.md`.)
2. **Namespace carried both `istio-injection=enabled` and `istio.io/dataplane-mode=ambient`** —
   mutually exclusive. Sidecars kept being injected, adding 100m CPU per pod until the node hit
   `1860m (93%)` requests and pods went `Pending` on `Insufficient cpu` — while real usage was
   only `408m (20%)`.
   (See `docs/bugs/2026-07-21-shopping-cart-ns-sidecar-blocks-ambient.md`.)

**Root cause:** `cluster-status` grew sections for nodes, pods, API health, observability, ArgoCD,
and Trivy, but the mesh was never added when the ambient milestone landed.

---

## Reproduction

1. Point at a cluster whose ambient mesh is broken (e.g. `istio-cni-node` `0/1`).
2. `make status CLUSTER_PROVIDER=k3s-hostinger`.
3. Output contains no mesh information; nothing signals the mesh is down.

Expected: a `Service Mesh` section that names the CNI substrate, shows the three ambient component
ready-counts, lists ambient-enrolled namespaces, and loudly flags the injection/ambient conflict.

---

## Fix

### Change 1 — `bin/cluster-status`: add a Service Mesh section after App Observability

Insert immediately **after** the existing `=== App Observability (${APP_CONTEXT}) ===` section ends
and **before** the `echo ""` that precedes
`=== Hub ArgoCD Registration (${INFRA_CONTEXT}, ns ${ARGOCD_NAMESPACE}) ===`.

**Exact new block to insert:**

```bash
echo ""
echo "=== Service Mesh / CNI (${APP_CONTEXT}) ==="
if kubectl --context "${APP_CONTEXT}" get ns istio-system >/dev/null 2>&1; then
  if kubectl --context "${APP_CONTEXT}" -n kube-system get daemonset cilium >/dev/null 2>&1; then
    _mesh_cni_ready=$(kubectl --context "${APP_CONTEXT}" -n kube-system get daemonset cilium \
      -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}' 2>/dev/null)
    echo "CNI substrate:    cilium (${_mesh_cni_ready} ready)"
  else
    echo "CNI substrate:    flannel (no cilium daemonset)"
  fi

  for _mesh_ds in istio-cni-node ztunnel; do
    if kubectl --context "${APP_CONTEXT}" -n istio-system get daemonset "${_mesh_ds}" >/dev/null 2>&1; then
      _mesh_ready=$(kubectl --context "${APP_CONTEXT}" -n istio-system get daemonset "${_mesh_ds}" \
        -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}' 2>/dev/null)
      printf '%-18s%s ready\n' "${_mesh_ds}:" "${_mesh_ready}"
    else
      printf '%-18s%s\n' "${_mesh_ds}:" "ABSENT"
    fi
  done

  if kubectl --context "${APP_CONTEXT}" -n istio-system get deployment istiod >/dev/null 2>&1; then
    _mesh_istiod=$(kubectl --context "${APP_CONTEXT}" -n istio-system get deployment istiod \
      -o jsonpath='{.status.readyReplicas}/{.spec.replicas}' 2>/dev/null)
    printf '%-18s%s ready\n' "istiod:" "${_mesh_istiod}"
  else
    printf '%-18s%s\n' "istiod:" "ABSENT"
  fi

  _mesh_ambient_ns=$(kubectl --context "${APP_CONTEXT}" get ns \
    -l istio.io/dataplane-mode=ambient -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' 2>/dev/null)
  echo "ambient ns:       ${_mesh_ambient_ns:-<none>}"

  _mesh_conflict=$(kubectl --context "${APP_CONTEXT}" get ns \
    -l istio.io/dataplane-mode=ambient,istio-injection=enabled \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' 2>/dev/null)
  if [[ -n "${_mesh_conflict}" ]]; then
    echo "CONFLICT:         ${_mesh_conflict}— has BOTH istio-injection=enabled and dataplane-mode=ambient"
    echo "                  sidecars are still being injected; ambient will not take effect"
  fi
else
  echo "istio-system namespace absent — service mesh not deployed"
fi
```

> Every lookup is guarded and degrades to `ABSENT` / a short note, matching how the existing
> sections behave on a partially-provisioned cluster. The section must never `exit` non-zero — a
> missing mesh is information, not a status-tool failure.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/cluster-status` | add `Service Mesh / CNI` section: CNI substrate, istio-cni/ztunnel/istiod ready counts, ambient-enrolled namespaces, injection-vs-ambient conflict warning |

---

## Rules

- `shellcheck -S warning bin/cluster-status` — zero new warnings. Quote every expansion; the new
  locals use the `_mesh_`/`_mesh_cni_` prefix to avoid colliding with existing names — verify with
  `grep -n '_mesh' bin/cluster-status` that no prior variable of that name exists.
- No other section touched; no reordering of existing output.
- Must not change `bin/cluster-status` exit status in any scenario.
- `bash -n bin/cluster-status` — the file must still parse.
- Do NOT run `bin/cluster-status` or `make status` against a live cluster. Codex has no
  live-cluster verification role here; static gates only. Claude runs the live check (below).

---

## Definition of Done

- [ ] `Service Mesh / CNI` section present, placed after App Observability.
- [ ] Reports cilium-vs-flannel substrate; ready counts for istio-cni-node, ztunnel, istiod.
- [ ] Lists ambient-enrolled namespaces; prints `<none>` when there are none.
- [ ] Prints the CONFLICT warning when a namespace has both labels.
- [ ] Degrades cleanly (`ABSENT` / note) when istio-system or a component is missing.
- [ ] `shellcheck -S warning bin/cluster-status` clean; `bash -n bin/cluster-status` clean.
- [ ] Exit status unchanged; existing sections untouched.
- [ ] Committed and pushed to `k3d-manager-v1.16.0`; push verified with
      `git log origin/k3d-manager-v1.16.0 --oneline -1` (paste the output).
- [ ] memory-bank updated with commit SHA and task status — as a **separate commit**, never
      bundled with `bin/cluster-status`.

**Commit message (exact):**
```
feat(status): report service mesh, CNI substrate, and ambient enrollment
```

### Live re-verify — Claude runs this after the push (NOT Codex)

`make status CLUSTER_PROVIDER=k3s-hostinger` must print the new section without error, report
`flannel` as the substrate, show `istio-cni-node`/`ztunnel`/`istiod` ready counts, and — until spec
`2026-07-21-shopping-cart-ns-sidecar-blocks-ambient.md` lands — is expected to print the CONFLICT
line for `shopping-cart-apps`.

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than `bin/cluster-status`.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
- Do NOT make the mesh section fatal or add `set -e`-sensitive bare command substitutions that
  abort the script when a resource is missing.
- Do NOT add mesh checks to the Hub section — the hub does not run the ambient dataplane.
