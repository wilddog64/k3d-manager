# Bug: Hostinger services not green — app-cluster role label stuck on dead ubuntu-k3s + stale green1 preflight stack

**Date:** 2026-06-25
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`
**Affects:** `k3d-manager` (ArgoCD GitOps wiring, `k3s-hostinger` provider)
**Files (code):** `scripts/lib/providers/k3s-hostinger.sh`, `scripts/plugins/argocd.sh`, `scripts/tests/lib/provider_contract.bats`
**Operator runbook (live, Claude-run on hub):** hub ArgoCD `k3d-k3d-cluster` namespace `cicd`

> Decision (user, 2026-06-25): **cut over to `ubuntu-hostinger`**. The ACG sandbox
> (`ubuntu-k3s`) is **NOT** removed — its cluster secret stays registered; the role
> label is a movable pointer and can be returned to `ubuntu-k3s` by redeploying the
> sandbox and re-running the provider refresh.

---

## Symptom (live `make status CLUSTER_PROVIDER=k3s-hostinger`, 2026-06-25)

```
✅ ArgoCD / Keycloak / Prometheus: HTTP 200
❌ Frontend / Grafana / Product images: HTTP 502 Bad Gateway
✅ ESO ClusterSecretStore: Ready=True   ✅ ESO ExternalSecrets: 17/17 synced (on ubuntu-hostinger host)
❌ Data layer: postgresql-orders, postgresql-payment not ready
```

These are the "open runtime follow-ups" recorded after Codex's 2026-06-25 PARTIAL
(`1a7ddbc4`). This spec closes them.

---

## Root cause (verified on the live hub `k3d-k3d-cluster` / `cicd`)

The hub ArgoCD straddles three clusters; none fully works:

| Stack | targetRevision | Destination | Live status |
|---|---|---|---|
| `green1-preflight-*` (currently fronting the public hostnames) | `k3d-manager-v1.7.1` | `cluster-green1` (`srv1754834.hstgr.cloud:32341`) | `ComparisonError` — `unable to resolve 'k3d-manager-v1.7.1' to a commit SHA` |
| `green1-preflight-data-layer` | `15fa072d…` | `cluster-green1` | `SyncError` — "one or more synchronization tasks are not valid" |
| `shopping-cart-*` / `data-layer` (permanent stack) | `feat/v1.8.0-acg-absorb-phase2-agy` | `ubuntu-k3s` | `Unknown` — targets dead `host.k3d.internal:6443` |

### Fault 1 — role label stuck on the dead cluster

Live cluster-secret labels (hub `cicd`):

```
cluster-ubuntu-k3s        -> {... k3d-manager/role: app-cluster}   # DEAD (host.k3d.internal:6443)
cluster-ubuntu-hostinger  -> {... (no role label)}                 # https://2.25.146.252:6443 — LIVE
cluster-green1            -> {... (no role label)}                 # preflight vcluster
```

`data-git` / `services-git` / `eso` use a `clusters` generator selecting
`k3d-manager/role: app-cluster`, so they generate Applications pointed at the dead
`ubuntu-k3s`. This is the documented-but-never-applied post-#97 operator step.

### Fault 2 — stale preflight vcluster serving production

`green1` is the ephemeral v1.7.1 PR preflight vcluster. Its `green1-preflight-*`
ApplicationSets pin `revision: k3d-manager-v1.7.1` — a branch that **no longer exists** —
so ArgoCD cannot render manifests (`ComparisonError`) and the stack is dead while still
fronting `frontend.3ai-talk.org`.

### Fault 3 (CODE) — Hostinger refresh relabel silently no-ops

`scripts/lib/providers/k3s-hostinger.sh:157-173` calls
`_argocd_set_active_app_cluster "${_HOSTINGER_KUBE_CONTEXT}"` (and a fallback `_kubectl
label`) to move the role to `ubuntu-hostinger`. But the ArgoCD cluster secrets live on
the **hub** (`k3d-k3d-cluster` / `cicd`), and the relabel runs against whatever context
`_kubectl` currently points at, with `|| true` swallowing failure. If the refresh context
is `ubuntu-hostinger` (not the hub), the relabel finds no cluster secrets and the label
stays on `ubuntu-k3s`. That is why `1a7ddbc4` did not actually move the label.

### Grafana 502 (symptom C) is downstream of Fault 1

Grafana is healthy (HTTP 200 `/api/health`, 3/3 pods) — it only exists **inside green1**
(`green1-preflight-acg-kube-prometheus-stack-grafana`). cloudflared routes
`grafana.3ai-talk.org → localhost:3001`, but the `com.k3d-manager.grafana-port-forward`
LaunchAgent is dead (last exit `1`) because it targets `svc/acg-kube-prometheus-stack-grafana`
in `monitoring` on the **host** context, which does not exist there. Once `observability-acg`
deploys to `ubuntu-hostinger` (via the cutover), that exact service appears in the host
`monitoring` namespace and the port-forward target becomes valid — 3001 listens, 502 clears.
No separate Grafana code change is required by the cutover; **verify** as a DoD step.

---

## Part A — Operator runbook (LIVE, Claude-run on hub — reversible, ACG preserved)

> Context for every step: `kubectl --context k3d-k3d-cluster -n cicd`.
> These are live hub mutations — run only after the user approves. They do **not** delete
> the `cluster-ubuntu-k3s` secret.

1. **Move the active app-cluster role to `ubuntu-hostinger`:**
   ```
   kubectl --context k3d-k3d-cluster -n cicd label secret cluster-ubuntu-hostinger \
     k3d-manager/role=app-cluster --overwrite
   kubectl --context k3d-k3d-cluster -n cicd label secret cluster-ubuntu-k3s \
     k3d-manager/role-          # clear from the dead cluster (secret retained)
   ```
2. **Confirm regeneration** — `data-git` / `services-git` / `eso` Applications now resolve
   destination `ubuntu-hostinger`; hard-refresh/sync:
   ```
   kubectl --context k3d-k3d-cluster -n cicd get application data-layer \
     -o jsonpath='{.spec.destination.name}'   # expect: ubuntu-hostinger
   ```
3. **Retire the stale green1 preflight stack** (pinned to the deleted branch):
   ```
   kubectl --context k3d-k3d-cluster -n cicd delete applicationset \
     green1-preflight-services-git green1-preflight-platform-helm green1-preflight-observability-acg
   kubectl --context k3d-k3d-cluster -n cicd delete application -l '<green1-preflight selector>'
   kubectl --context k3d-k3d-cluster -n cicd delete secret cluster-green1
   ```
   (Confirm the exact green1-preflight Application set/labels live before deleting.)
4. **Verify** (see DoD).

---

## Part A — EXECUTED (Claude, 2026-06-25, live on hub)

| Step | Result |
|---|---|
| Move role label → `cluster-ubuntu-hostinger`, clear from `cluster-ubuntu-k3s` | ✅ done; `cluster-ubuntu-k3s` secret **preserved** (unlabeled) |
| ApplicationSets regenerate | ✅ `data-git`/`services-git`/`eso`/`observability-acg` now target `ubuntu-hostinger`; all **Synced** |
| Retire green1 preflight | ✅ deleted appsets `green1-preflight-{observability-acg,platform-helm,services-git}` + all child apps + orphan `green1-preflight-data-layer`; stripped finalizers first to avoid prune-hang on the unreachable vcluster |
| Delete `cluster-green1` secret | ✅ done |
| **Symptom C — Grafana 502** | ✅ **RESOLVED** — `acg-kube-prometheus-stack-grafana` svc now on host `monitoring` (NodePort 30030); PF LaunchAgent recovered, `localhost:3001` listens; `https://grafana.3ai-talk.org/api/health` = **200** |

### Two issues discovered during Part A (NOT yet fixed)

**Discovery 1 — `platform-helm` appset is selected by the `environment` label, not the role label.**
`platform-helm`'s generator is `clusters.selector.matchExpressions: environment In [dev,infra,prod]`.
`cluster-ubuntu-k3s` carries `environment: dev`, `argocd-chart-version: 7.8.1`, `argocd-replicas: 2`;
`cluster-ubuntu-hostinger` carries **only** `k3d-manager/role: app-cluster`. Consequences:
- the `platform-helm` stack does **not** follow the active app-cluster to `ubuntu-hostinger`;
- `ubuntu-k3s-platform` keeps regenerating against the dead cluster (force-delete just loops — left in place as harmless `OutOfSync` noise).
→ Folded into **Part B Change 4**: provider registration/refresh must stamp the full set of
appset-selector labels onto the active app-cluster secret, not just `role`.

**Discovery 2 — Hostinger node CPU ceiling (infra, not wiring).**
`minio-0`, `postgresql-orders-0`, `postgresql-payment-0` are `Pending`:
`0/1 nodes are available: 1 Insufficient cpu`. PVCs are `WaitForFirstConsumer` so they stay
`Pending` behind the unschedulable pods. `frontend.3ai-talk.org` stays 502 until these
schedule. This is a Hostinger VM capacity limit — **separate from this cutover** (resize node
or trim CPU requests on the data layer). Tracked as a follow-up, not part of Part B code.

---

## Part B — Code changes (Codex)

### Change 1 — `scripts/lib/providers/k3s-hostinger.sh`: relabel against the hub, not the app context

The role-label reassignment must target the **hub** ArgoCD cluster (where the cluster
secrets live), not the Hostinger app context. Pin the relabel `_kubectl`/`_argocd_set_active_app_cluster`
calls to the hub context explicitly (the cluster running ArgoCD `cicd`), and drop the
silent `|| true` on the authoritative path so a failed relabel surfaces.

> Codex: read `scripts/lib/providers/k3s-hostinger.sh:150-175` and
> `scripts/plugins/argocd.sh:1126-1144` first. Provide exact old/new blocks. Do not change
> the exclusivity semantics of `_argocd_set_active_app_cluster`.

### Change 2 — preflight cleanup path — MOVED

**Relocated to its own spec:** `docs/bugs/2026-06-25-retire-orphaned-green1-vcluster-host-cpu-ceiling.md`.
The preflight hub-cleanup belongs in `scripts/plugins/vcluster.sh` (`vcluster_destroy`),
alongside the host-side `vcluster delete`, not in the hostinger provider. Implement it there.
**Do NOT implement Change 2 in this spec** — only Changes 1, 3, 4 below.

### Change 4 — stamp ALL appset-selector labels on the active app-cluster secret

(Discovered during Part A.) The hub cluster secret for the active app-cluster must carry
every label the ApplicationSet generators select on — not just `k3d-manager/role`. Today
`register_app_cluster` / the Hostinger refresh set only the role label, so the
`platform-helm` appset (`environment In [dev,infra,prod]`, with values keyed off
`argocd-chart-version` / `argocd-replicas`) never generates a platform app for
`ubuntu-hostinger`.

**Note (verified 2026-06-25):** `register_app_cluster` (`argocd.sh:1185-1196`) ALREADY stamps
`environment` / `argocd-chart-version` / `argocd-replicas` on the cluster secret. So this is
NOT a missing-label bug in `register_app_cluster` — `cluster-ubuntu-hostinger` was created
through a path that bypassed it (it carries only `cluster-name` + the `role` label). The fix:
ensure the Hostinger provider's app-cluster registration/relabel path goes through
`register_app_cluster` (or otherwise stamps the same three labels) so the active app-cluster
secret carries `environment In [dev,infra,prod]` and the `platform-helm` appset follows it.

Codex: read `register_app_cluster` (`argocd.sh:1145-1216`) and the Hostinger registration/
relabel path in `k3s-hostinger.sh:150-175`. Provide exact old/new blocks. Derive label values
from provider config/env — do not hardcode a single provider's values. Do not change generator
selectors.

### Change 3 — `scripts/tests/lib/provider_contract.bats`

Add coverage: (a) the Hostinger refresh relabel targets the hub context; (b) the active
app-cluster secret receives the `environment`/`argocd-chart-version`/`argocd-replicas` labels
(Change 4). *(Preflight-cleanup coverage moved to the green1-vcluster spec.)*

---

## Definition of Done

- [x] **Part A:** `data-layer` (and `shopping-cart-*`) destination = `ubuntu-hostinger`;
      `green1-preflight-*` apps + `cluster-green1` secret removed; `cluster-ubuntu-k3s` secret
      still present. *(Done 2026-06-25. Data-layer pods: products/rabbitmq/redis Ready;
      minio/postgresql-orders/postgresql-payment Pending on **node CPU ceiling** — Discovery 2,
      not a wiring fault.)*
- [x] **Symptom C:** `com.k3d-manager.grafana-port-forward` healthy, `localhost:3001`
      listening, `https://grafana.3ai-talk.org` returns 200. *(Verified 2026-06-25.)*
- [ ] `make status CLUSTER_PROVIDER=k3s-hostinger` — Frontend / Product images 200 *(blocked on
      Discovery 2 CPU ceiling, not Part B)*; Grafana 200 ✅.
- [ ] **Part B:** Changes 1–4; `shellcheck -S warning` clean on changed files; `bats
      scripts/tests/lib/provider_contract.bats` passes; `./scripts/k3d-manager _agent_audit`
      exit 0; committed + pushed to `feat/v1.8.0-acg-absorb-phase2-agy`; memory-bank updated.

**Commit message (Part B, exact):**
```
fix(hostinger): relabel app-cluster role on hub + retire stale preflight stack
```

---

## What NOT to Do

- Do NOT delete the `cluster-ubuntu-k3s` secret or otherwise tear down the ACG sandbox.
- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the listed targets.
- Do NOT commit to `main` — work on `feat/v1.8.0-acg-absorb-phase2-agy`.
- Do NOT change `_argocd_set_active_app_cluster` exclusivity semantics.
