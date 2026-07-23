# Bugfix: v1.16.0 — shopping-cart namespace is sidecar-enrolled, blocking ambient

**Branch:** `k3d-manager-v1.16.0`
**Files:** `services/shopping-cart-namespace/namespace.yaml`

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — the Hostinger ambient
  section records the live evidence behind this spec.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `services/shopping-cart-namespace/namespace.yaml` — the whole `metadata.labels` block.
  - `services/shopping-cart-namespace/kustomization.yaml` — confirm `namespace.yaml` is the only
    resource contributing namespace labels.
  - `docs/bugs/2026-07-21-istio-ambient-cni-dirs-not-substrate-aware.md` — the companion spec; the
    ambient control plane must be healthy before this change has any visible effect.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

`services/shopping-cart-namespace/namespace.yaml` labels the app namespace for **sidecar** mesh:

```yaml
    istio-injection: enabled
```

This is the v1.16.0 **ambient** milestone. Ambient enrollment uses
`istio.io/dataplane-mode: ambient` and requires that `istio-injection` be **absent** — the two are
mutually exclusive. While `istio-injection=enabled` is present, istiod's
`namespace.sidecar-injector.istio.io` webhook matches the namespace and injects an `istio-proxy`
sidecar into every pod, so the workloads never enter the ambient dataplane at all.

**Root cause:** the namespace manifest was written for the sidecar mesh and was never migrated when
the milestone moved to ambient.

### Secondary effect — this is what actually wedges the node

Each injected `istio-proxy` adds a **100m CPU request**. On the single 2-CPU `ubuntu-hostinger`
node this doubles the app tier's requests and pushes the node past schedulable capacity:

```
Allocated resources:
  cpu  1860m (93%)

Warning  FailedScheduling  0/1 nodes are available: 1 Insufficient cpu.
```

…while **actual** node usage is only `408m (20%)`. The pods are blocked by *requests*, not load —
so the historical "hostinger is CPU-starved" reading was a symptom of sidecar injection, not a
genuine capacity problem. Removing injection reclaims ~100m per pod; ztunnel (already deployed,
one per node) carries the dataplane instead.

### Why this must be fixed in git, not live

Live remediation was attempted and **cannot hold**. The `services-git` ApplicationSet regenerates
the `ubuntu-hostinger-shopping-cart-namespace` Application from its template, so:

- `kubectl label ns shopping-cart-apps istio-injection-` → reverted within ~15s by ArgoCD sync.
- Patching the Application's `syncPolicy` to disable `selfHeal`, then removing `automated`
  entirely → **both reverted**, because the ApplicationSet controller rewrites `.spec` from the
  generator template.

The manifest in git is the only durable point of control.

---

## Reproduction

1. Ambient control plane healthy on `ubuntu-hostinger` (istio-cni/istiod/ztunnel all `1/1`).
2. `kubectl --context ubuntu-hostinger get ns shopping-cart-apps --show-labels`
   → shows `istio-injection=enabled`.
3. `kubectl --context ubuntu-hostinger get pods -n shopping-cart-apps`
   → pods are `x/2` (app container + `istio-proxy`), several `Pending` on `Insufficient cpu`.

Expected: pods are `1/1` (no sidecar), namespace carries `istio.io/dataplane-mode=ambient`, and
ztunnel handles L4 for the namespace.

---

## Fix

### Change 1 — `services/shopping-cart-namespace/namespace.yaml`: sidecar label → ambient label

**Exact old block (lines 7–10):**

```yaml
  labels:
    app.kubernetes.io/part-of: shopping-cart
    app.kubernetes.io/managed-by: argocd
    istio-injection: enabled
```

**Exact new block:**

```yaml
  labels:
    app.kubernetes.io/part-of: shopping-cart
    app.kubernetes.io/managed-by: argocd
    istio.io/dataplane-mode: ambient
```

> `istio-injection` must be **removed**, not set to `disabled`. A leftover
> `istio-injection: disabled` key is harmless to the injector but leaves the manifest ambiguous
> about which mesh mode the namespace is in; ambient enrollment is expressed solely by
> `istio.io/dataplane-mode: ambient`.

---

## Files Changed

| File | Change |
|------|--------|
| `services/shopping-cart-namespace/namespace.yaml` | replace `istio-injection: enabled` with `istio.io/dataplane-mode: ambient` |

---

## Rules

- YAML must still parse:
  `python3 -c 'import yaml; print(yaml.safe_load(open("services/shopping-cart-namespace/namespace.yaml"))["metadata"]["labels"])'`
- The other two labels and the `argocd.argoproj.io/sync-wave: "-1"` annotation must be unchanged.
- Do NOT touch `ghcr-pull-secret-externalsecret.yaml` or `kustomization.yaml`.
- Do NOT change any Deployment's CPU requests to work around scheduling — removing the sidecar is
  the fix.

---

## Definition of Done

- [ ] `namespace.yaml` has `istio.io/dataplane-mode: ambient` and **no** `istio-injection` key.
- [ ] Sync-wave annotation and the two `app.kubernetes.io/*` labels untouched.
- [ ] YAML parses clean.
- [ ] Committed and pushed to `k3d-manager-v1.16.0`; push verified with
      `git log origin/k3d-manager-v1.16.0 --oneline -1` (paste the output).
- [ ] memory-bank updated with commit SHA and task status — as a **separate commit**, never
      bundled with `namespace.yaml`.

**Commit message (exact):**
```
fix(mesh): enroll shopping-cart namespace in ambient instead of sidecar injection
```

### Live re-verify — Claude runs this after the push (NOT Codex)

Sync the namespace Application, restart the app deployments, then confirm:
pods are `1/1` with no `istio-proxy` container; node CPU requests drop back under capacity and the
`Pending` pods schedule; ztunnel access log shows HBONE (`dst.hbone_addr=…:80`, port 15008) with
mutual SPIFFE identities on a curl between two workloads in the namespace.

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than `services/shopping-cart-namespace/namespace.yaml`.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
- Do NOT also relabel `shopping-cart-payment` or `shopping-cart-data` in this change — those
  namespaces are out of scope here and need their own decision.
- Do NOT attempt to hold the fix with `kubectl label` or by editing the Application/ApplicationSet
  in-cluster — it will be reverted by the ApplicationSet controller.
