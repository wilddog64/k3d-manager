# Bugfix: v1.16.0 — hostinger 502, redirect the trivy-server CPU trim to the ACG values file

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/etc/helm/observability/trivy-operator-acg-values.yaml`

---

## Why this spec exists (read first)

The earlier fix `7345b24a` (spec `docs/bugs/2026-07-22-hostinger-trivy-cpu-oversubscription-502.md`)
was implemented correctly but targeted the **wrong values file**. Claude's live verify on the
hostinger cluster found the GitOps file→cluster mapping is the inverse of what that spec assumed:

| Values file | ApplicationSet | Destination cluster |
|---|---|---|
| `trivy-operator-values.yaml` (already trimmed by `7345b24a`) | `observability.yaml` | **hub laptop** (`https://kubernetes.default.svc`) — not CPU-starved |
| `trivy-operator-acg-values.yaml` (**this spec**) | `observability-acg.yaml` | **`${APP_CLUSTER_NAME}` = ubuntu-hostinger** — the starved node |

The `acg-` prefix is a misnomer: `observability-acg.yaml` is the **app-cluster** observability path
and currently runs on hostinger. Its trivy-operator app (`acg-trivy-operator`) uses
`trivy-operator-acg-values.yaml`, which has **no `server` block**, so the built-in Trivy server on
hostinger sits at the chart default **200m** — verified live (`trivy-server-0` request `cpu: 200m`).

Do NOT revert `7345b24a`; the owner chose to keep it (harmless hub-laptop hygiene). This spec ADDS
the identical `server.resources` block to the ACG file so the trim actually reaches hostinger.
The `acg-trivy-operator` values source tracks `targetRevision: k3d-manager-v1.16.0`, so once this
lands and is pushed, ArgoCD auto-syncs it to hostinger — Claude then does the live verify.

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — the "OPEN AFTER THIS
  MILESTONE" section records the hostinger 2-CPU oversubscription and that the git-side trim landed
  in the wrong file.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/etc/helm/observability/trivy-operator-acg-values.yaml` — the whole file. It sets
    `trivy.resources` (scan-job pods, 50m) and `operator.builtInTrivyServer: true` (line 19), but
    does **not** set `trivy.server.resources`, so the built-in Trivy server StatefulSet uses the
    chart default (200m request).
- Implement exactly what is written — no interpretation, no scope expansion.
- Do NOT touch `trivy-operator-values.yaml` (already fixed in `7345b24a`), `observability.yaml`,
  `observability-acg.yaml`, or any other file.

---

## Problem

On hostinger (`ubuntu-hostinger`, a 2-CPU node = **2000m** allocatable) the sum of pod CPU
**requests** is **1960m (98%)**. `product-catalog` requests **100m** but there is no room, so its pod
sits `Pending` with `FailedScheduling: Insufficient cpu` (×254 over 21h). With zero running
product-catalog replicas the webhook Service-Health "Product images" check returns **HTTP 502**.

**Root cause of the residual 502 after `7345b24a`:** the built-in Trivy server on hostinger
(`trivy-system/trivy-server-0`) reserves **200m** CPU as a scheduling reservation, because the ACG
values file never overrides `trivy.server.resources`. `7345b24a` trimmed the *hub* server, not this
one. Dropping the hostinger server's request to **50m** frees **150m** (node → ~1810m), enough to
schedule product-catalog (100m). Limits stay at the chart default (`cpu: "1"`), so real scans still
burst — only the idle scheduling reservation shrinks.

### Load-bearing detail — the correct helm key

The trivy-operator chart (`0.33.2`) exposes the built-in server's resources under
**`trivy.server.resources`** — a *different* key from `trivy.resources` (scan jobs). The chart
default for `trivy.server.resources.requests.cpu` is exactly `200m`. Setting the wrong key silently
no-ops. Verified against the chart with `helm template` (see Reproduction).

---

## Reproduction

Static — no live cluster required. From the repo root:

**Before the fix — the server resources key is absent:**

```bash
grep -n 'server:' scripts/etc/helm/observability/trivy-operator-acg-values.yaml
```
→ prints nothing.

**Helm-render gate — prove the override lands on the trivy-server StatefulSet:**

```bash
helm repo add aqua https://aquasecurity.github.io/helm-charts/ >/dev/null 2>&1
helm repo update aqua >/dev/null 2>&1
helm template trivy-operator aqua/trivy-operator --version 0.33.2 \
  -f scripts/etc/helm/observability/trivy-operator-acg-values.yaml 2>/dev/null \
  | yq eval-all 'select(.kind=="StatefulSet" and .metadata.name=="trivy-server") | .spec.template.spec.containers[0].resources.requests.cpu' -
```

- **Before the fix:** prints `200m` (chart default).
- **After the fix:** prints `50m`.

(If `yq` is unavailable, install it or use an equivalent `python3` YAML extraction — the required
assertion is that the rendered `trivy-server` StatefulSet container's `resources.requests.cpu`
equals `50m`.)

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

> The `server:` block is nested under the existing top-level `trivy:` mapping (2-space indent, same
> level as the existing `resources:`). Do NOT create a second top-level `trivy:` key. The `limits`
> are kept at the chart default (`cpu: "1"`, `memory: 1Gi`) so real scans still burst — only the
> scheduling **request** is reduced. This block is byte-identical to the one `7345b24a` added to the
> hub values file.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/helm/observability/trivy-operator-acg-values.yaml` | add `trivy.server.resources` overriding the built-in server request to `cpu: 50m` / `memory: 256Mi`; keep chart-default limits |

---

## Rules

- **YAML validity gate** — must parse:
  ```bash
  python3 -c "import yaml; yaml.safe_load(open('scripts/etc/helm/observability/trivy-operator-acg-values.yaml'))" && echo OK
  ```
  → prints `OK`.
- **Helm-render gate** — the Reproduction render command must print `50m` after the fix. Paste the
  output.
- **Single-key gate** — exactly one top-level `trivy:` key (the block is nested, not duplicated):
  ```bash
  grep -c '^trivy:' scripts/etc/helm/observability/trivy-operator-acg-values.yaml
  ```
  → must print `1`.
- Do NOT touch `trivy-operator-values.yaml`, `observability.yaml`, `observability-acg.yaml`, or any
  other file.
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
fix(observability): trim acg trivy-server CPU request to relieve hostinger node
```

### Live re-verify — Claude runs this after the push (NOT Codex)

After ArgoCD syncs the trimmed ACG values, confirm on `ubuntu-hostinger` that `trivy-server-0` now
requests `50m`, the node CPU-request total drops by ~150m, and `product-catalog` leaves `Pending`
and reaches `Running`, clearing the "Product images" 502. Claude also reconciles the two stray
`Pending` rollout duplicates (`frontend-8bbdc8599`, `order-service-75c5b998b7`) created by the
earlier `make refresh`.

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than `scripts/etc/helm/observability/trivy-operator-acg-values.yaml`.
- Do NOT revert `7345b24a` or touch `trivy-operator-values.yaml` — the owner chose to keep it.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
- Do NOT lower the Trivy server `limits` — only the request.
- Do NOT change any other pod's resources in this change.
