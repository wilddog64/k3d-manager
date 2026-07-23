# Bug: istiod cannot schedule on the 2-CPU hostinger node — right-size istiod + ztunnel requests

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/etc/argocd/applicationsets/istio-ambient.yaml` (ONLY)
**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "istio-ambient istiod/ztunnel CPU right-size" item on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/etc/argocd/applicationsets/istio-ambient.yaml` — the whole file (the list
    generator's per-element `values` blocks are what you edit).
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

On the parked `ubuntu-hostinger` app cluster, `istiod` has been `0/1 Pending` for ~13h:

```
FailedScheduling: 0/1 nodes are available: 1 Insufficient cpu (x162 over 12h)
```

The node `srv1754834` has **2 CPU total**. Measured live 2026-07-19:

- CPU **requests** bound to the node: **1710m / 2000m (85%)** — only ~290m free.
- istiod requests **500m** (the istiod-1.24.2 chart default) → cannot fit → Pending.
- **Actual CPU usage on the node: 338m (16%)** — the node is nearly idle. The data-layer +
  monitoring + trivy pods *reserve* far more CPU than they use, and that reservation blocks
  istiod's 500m request.

With no istiod endpoints, the `namespace.sidecar-injector.istio.io` admission webhook fails
(`no endpoints available for service "istiod"`), so no new pod can be created in the
mesh-injected `shopping-cart-apps` namespace. `ztunnel` (200m) is likewise stuck.

istiod's 500m/2Gi and ztunnel's 200m/512Mi are the **chart defaults** — they are not set
anywhere in this repo. For a small dev cluster managing a handful of workloads, they are
grossly over-provisioned. Right-sizing the requests lets istiod schedule into the existing
headroom (no CPU limit is set, so istiod can still burst above the request under real load).

Live values confirmed before writing this spec:
- istiod Deployment: `requests: {cpu: 500m, memory: 2Gi}`, chart `istiod-1.24.2`, path `pilot.resources`.
- ztunnel DaemonSet: `requests: {cpu: 200m, memory: 512Mi}`, chart `ztunnel-1.24.2`, top-level `resources`.

---

## Fix

### Change 1 — add a `pilot.resources` request to the `istiod` element's Helm values

**Exact old block:**

```yaml
          - name: istiod
            chart: istiod
            wave: "1"
            values: |
              profile: ambient
```

**Exact new block:**

```yaml
          - name: istiod
            chart: istiod
            wave: "1"
            values: |
              profile: ambient
              pilot:
                resources:
                  requests:
                    cpu: 100m
                    memory: 512Mi
```

### Change 2 — add a top-level `resources` request to the `ztunnel` element's Helm values

**Exact old block:**

```yaml
          - name: ztunnel
            chart: ztunnel
            wave: "3"
            values: ""
```

**Exact new block:**

```yaml
          - name: ztunnel
            chart: ztunnel
            wave: "3"
            values: |
              resources:
                requests:
                  cpu: 100m
                  memory: 256Mi
```

Do NOT change any other element. The `istiod` values path is `pilot.resources`; the `ztunnel`
values path is a top-level `resources` — these differ by chart and must not be swapped.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/applicationsets/istio-ambient.yaml` | istiod `pilot.resources` 100m/512Mi; ztunnel `resources` 100m/256Mi |

---

## Rules

- `yq eval '.' scripts/etc/argocd/applicationsets/istio-ambient.yaml >/dev/null` — parses clean
  (this box's `python3` has no PyYAML; use `yq`, which is installed).
- **Presence gate:** `grep -c 'cpu: 100m' scripts/etc/argocd/applicationsets/istio-ambient.yaml` → **`2`**
- **Presence gate:** `grep -c 'pilot:' scripts/etc/argocd/applicationsets/istio-ambient.yaml` → **`1`**
- **Presence gate:** `grep -c 'memory: 512Mi' scripts/etc/argocd/applicationsets/istio-ambient.yaml` → **`1`**
- **Presence gate:** `grep -c 'memory: 256Mi' scripts/etc/argocd/applicationsets/istio-ambient.yaml` → **`1`**
- **Disappearance gate:** `grep -c 'values: ""' scripts/etc/argocd/applicationsets/istio-ambient.yaml` → **`0`**
  (the ztunnel empty-string values became a block).
- **Unchanged gate:** `grep -c 'profile: ambient' scripts/etc/argocd/applicationsets/istio-ambient.yaml`
  must be the SAME before and after — record both numbers. Both the istiod and istio-cni
  elements carry `profile: ambient`; neither is touched.
- **Unchanged gate:** `grep -c 'targetRevision: ${AMBIENT_ISTIO_VERSION}' scripts/etc/argocd/applicationsets/istio-ambient.yaml`
  must be the SAME before and after — record both numbers. Do NOT touch the `targetRevision`
  line — the `${AMBIENT_ISTIO_VERSION}` envsubst behavior is a separate, already-filed bug.
- `./scripts/k3d-manager _agent_audit` — exit 0
- No other files touched

---

## Definition of Done

- [ ] istiod element has `pilot.resources.requests` cpu `100m` / memory `512Mi`
- [ ] ztunnel element has top-level `resources.requests` cpu `100m` / memory `256Mi`
- [ ] `profile: ambient` count unchanged (gate recorded both counts)
- [ ] `targetRevision: ${AMBIENT_ISTIO_VERSION}` count unchanged (gate recorded both counts)
- [ ] `yq eval` parses clean
- [ ] `git show --stat` shows exactly ONE file changed
- [ ] `_agent_audit` exit 0
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(mesh): right-size istiod and ztunnel CPU requests for the 2-CPU hostinger node
```

---

## What NOT to Do

- Do NOT change the `targetRevision: ${AMBIENT_ISTIO_VERSION}` line — the empty-var envsubst
  issue is a separate bug (`2026-07-18-appset-envsubst-empty-var-substitution.md`).
- Do NOT add resource *limits* — only `requests`. istiod must remain able to burst.
- Do NOT touch the `istio-base` or `istio-cni` elements, or the `cniConfDir`/`cniBinDir`
  values. (The missing `istio-cni` plugin binary on the node is a separate node-level
  problem, NOT fixed here.)
- Do NOT change the generator structure, sync waves, `syncPolicy`, or the `template`.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the single listed target
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Claude-only (do NOT delegate)

Live re-sync + verification. Agents do not touch the live cluster. After the commit lands,
Claude re-applies / hard-refreshes `istiod-ubuntu-hostinger` (and `ztunnel-ubuntu-hostinger`)
on the hub and confirms:

- the istiod Deployment's container request drops to `cpu: 100m` (catches a wrong Helm values
  path — if it stays 500m, the `pilot.resources` path was wrong).
- istiod schedules (`Running`), `endpoints/istiod` is non-empty, the sidecar-injector webhook
  works again.
- Note the SEPARATE, still-open blockers this spec does NOT resolve: (1) the missing
  `istio-cni` plugin binary (`failed to find plugin "istio-cni" in path
  /var/lib/rancher/k3s/data/cni`), and (2) whether the full app tier fits once istiod is up
  (the data-layer/monitoring requests may also need right-sizing). File those separately if
  they still block after istiod schedules.
