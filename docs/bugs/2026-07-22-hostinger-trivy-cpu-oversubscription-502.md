# Bugfix: v1.16.0 — hostinger node CPU oversubscription 502s the product-catalog endpoint

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/etc/helm/observability/trivy-operator-values.yaml`

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — the "OPEN AFTER THIS
  MILESTONE" section records the hostinger 2-CPU oversubscription (node ~1960m/2000m requested with
  ambient live). This spec is the fix for the user-visible symptom of that item.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/etc/helm/observability/trivy-operator-values.yaml` — the whole file. Note the existing
    `trivy:` block already sets `trivy.resources` (that is the **scan-job** pods, 50m) and
    `operator.builtInTrivyServer: true`. It does **not** set `trivy.server.resources`, so the
    built-in Trivy server StatefulSet uses the chart default (200m request).
  - `scripts/etc/argocd/applicationsets/observability.yaml` — confirm this appset renders the
    non-ACG trivy-operator chart from `trivy-operator-values.yaml` (chart `trivy-operator`,
    version `0.33.2`). Do NOT touch the ACG sibling (`observability-acg.yaml` /
    `trivy-operator-acg-values.yaml`) — that is the AWS sandbox rig, out of scope.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

On the hostinger app cluster (`ubuntu-hostinger`, a 2-CPU node = **2000m** allocatable), the sum of
pod CPU **requests** is **~1960m (98%)**. `product-catalog` requests **100m** but there is no room,
so its pod sits `Pending` with `FailedScheduling: Insufficient cpu`. With zero running
product-catalog replicas the ArgoCD/istio gateway has no backend for that route, and the webhook
Service-Health probe (`bin/k3dm-webhook`, "Product images" check → product-catalog API) returns
**HTTP 502 Bad Gateway**. Every other service is green — product-catalog is the only app whose
sole pod cannot schedule.

**Root cause:** the v1.16.0 ambient rollout added three istio-system pods to the hostinger node —
`istiod`, `ztunnel`, and `istio-cni-node` at 100m each (**+300m**) — pushing the node from ~1660m to
~1960m of reserved CPU. The single largest reclaimable non-application consumer is the **built-in
Trivy server** (`trivy-system/trivy-server-0`), which reserves **200m** CPU purely as a scheduling
reservation. Its request is the chart default because our values file never overrides
`trivy.server.resources`.

The Trivy server's `limits.cpu` stays at `1`, so lowering only the **request** does not slow real
scans — it just stops the server from reserving 200m it does not need at idle. Dropping the request
to **50m** frees **150m**, which is enough to schedule product-catalog (100m) with headroom.

### Load-bearing detail — the correct helm key

The trivy-operator chart (`0.33.2`) exposes the built-in server's resources under
**`trivy.server.resources`** — a *different* key from `trivy.resources` (scan jobs). The chart
default for `trivy.server.resources.requests.cpu` is exactly `200m` (matching the live pod). Setting
the wrong key silently no-ops. This key was verified against the chart with `helm template` (see
Reproduction).

---

## Reproduction

Static — no live cluster required. From the repo root:

**Before the fix — the server resources key is absent:**

```bash
grep -n 'server:' scripts/etc/helm/observability/trivy-operator-values.yaml
```
→ prints nothing (no `trivy.server` block).

**Helm-render gate — prove the override lands on the trivy-server StatefulSet:**

```bash
helm repo add aqua https://aquasecurity.github.io/helm-charts/ >/dev/null 2>&1
helm repo update aqua >/dev/null 2>&1
helm template trivy-operator aqua/trivy-operator --version 0.33.2 \
  -f scripts/etc/helm/observability/trivy-operator-values.yaml 2>/dev/null \
  | yq eval-all 'select(.kind=="StatefulSet" and .metadata.name=="trivy-server") | .spec.template.spec.containers[0].resources.requests.cpu' -
```

- **Before the fix:** prints `200m` (chart default).
- **After the fix:** prints `50m`.

(If `yq` is unavailable, install it or use the equivalent `python3 -c "import yaml,sys; ..."`
extraction — the required assertion is that the rendered `trivy-server` StatefulSet container's
`resources.requests.cpu` equals `50m`.)

---

## Fix

### Change 1 — add a `trivy.server.resources` override that trims the server CPU request

**Exact old block:**

```yaml
  resources:
    requests:
      memory: 256Mi
      cpu: 50m
    limits:
      memory: 1Gi
      cpu: 500m

operator:
```

**Exact new block:**

```yaml
  resources:
    requests:
      memory: 256Mi
      cpu: 50m
    limits:
      memory: 1Gi
      cpu: 500m
  server:
    resources:
      requests:
        cpu: 50m
        memory: 256Mi
      limits:
        cpu: "1"
        memory: 1Gi

operator:
```

> The `server:` block is nested under the existing top-level `trivy:` mapping (2-space indent,
> same level as the existing `resources:`). Do NOT create a second top-level `trivy:` key. The
> `limits` are kept at the chart default (`cpu: "1"`, `memory: 1Gi`) so real scans still burst —
> only the scheduling **request** is reduced.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/helm/observability/trivy-operator-values.yaml` | add `trivy.server.resources` overriding the built-in server request to `cpu: 50m` / `memory: 256Mi`; keep chart-default limits |

---

## Rules

- **YAML validity gate** — must parse:
  ```bash
  python3 -c "import yaml; yaml.safe_load(open('scripts/etc/helm/observability/trivy-operator-values.yaml'))" && echo OK
  ```
  → prints `OK`.
- **Helm-render gate** — the Reproduction render command must print `50m` after the fix. Paste the
  output.
- **Single-key gate** — exactly one top-level `trivy:` key (the block is nested, not duplicated):
  ```bash
  grep -c '^trivy:' scripts/etc/helm/observability/trivy-operator-values.yaml
  ```
  → must print `1`.
- Do NOT touch `trivy-operator-acg-values.yaml`, `observability-acg.yaml`, or any other file.
- Do NOT change the scan-job `trivy.resources` block or the `operator` block.
- Do NOT run any `kubectl`, `helm upgrade`, `helm install`, or `argocd` command against a live
  cluster. Codex has no live-cluster role here; static gates only. Claude runs the live check below.

---

## Definition of Done

- [ ] `trivy.server.resources` block added, nested under the existing `trivy:` key, request
      `cpu: 50m` / `memory: 256Mi`, limits `cpu: "1"` / `memory: 1Gi`.
- [ ] Helm-render gate prints `50m`.
- [ ] YAML validity gate prints `OK`.
- [ ] `grep -c '^trivy:' …` → `1`.
- [ ] No other file modified — `git show <sha> --stat` shows exactly one file.
- [ ] Committed and pushed to `k3d-manager-v1.16.0`; push verified with pasted
      `git log origin/k3d-manager-v1.16.0 --oneline -1`.
- [ ] memory-bank updated with commit SHA and task status — as a **separate commit**, never
      bundled with the code change.

**Commit message (exact):**
```
fix(observability): trim trivy-server CPU request to relieve hostinger node
```

### Live re-verify — Claude runs this after the push (NOT Codex)

After ArgoCD syncs the trimmed values, confirm on `ubuntu-hostinger` that `trivy-server-0` now
requests `50m`, the node CPU-request total drops by ~150m, and `product-catalog` leaves `Pending`
and reaches `Running`, clearing the "Product images" 502. Claude also reconciles the two stray
`Pending` rollout duplicates (frontend / order-service) created by the earlier `make refresh`.

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than `scripts/etc/helm/observability/trivy-operator-values.yaml`.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
- Do NOT touch the ACG observability path (`trivy-operator-acg-values.yaml`,
  `observability-acg.yaml`) — different cluster, out of scope.
- Do NOT lower the Trivy server `limits` — only the request. Cutting the limit would throttle real
  scans.
- Do NOT change any other pod's resources in this change — reclaiming the Trivy server's 150m is
  sufficient to unblock product-catalog; broader right-sizing, if ever needed, is a separate spec.
