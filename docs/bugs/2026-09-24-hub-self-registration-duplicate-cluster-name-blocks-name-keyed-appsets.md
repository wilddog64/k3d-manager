# Bug: the hub self-registration claims the cluster name `ubuntu-k3s`, so every name-keyed ApplicationSet refuses to generate for the ACG cluster

**Branch:** `k3d-manager-v1.37.0`
**Filed:** 2026-09-24
**Status:** OPEN — root cause confirmed; the remedy needs an owner decision (live registration Secret)
**Files:** `scripts/plugins/hub_recovery.sh:252` (source of the collision)
**Related:**
- `2026-09-24-cluster-up-registration-omits-provider-and-shopping-cart-labels.md` — the label fix (`ffe954a1`) that exposed this
- `2026-07-19-services-git-appset-duplicate-application-names.md` — duplicate *Application* names; this is duplicate *cluster* names
- `2026-07-18-hub-infra-registration-blocked-platform-helm-selfheal.md` — why a hub cluster Secret is hazardous
- memory `reference_hub_app_cluster_registration_is_load_bearing_for_eso`, `reference_preserveresourcesondeletion_rename_trap`

## Symptom

`make up CLUSTER_PROVIDER=k3s-aws` fails at Step 10b/14 for the third consecutive run:

```
ERROR: [acg-up] data-layer ArgoCD Application did not reach Synced after force-sync + 180s retry
```

`ffe954a1` corrected the cluster-secret labels, and they are correct on the live hub:

```
NAME                       ROLE          SC       PROVIDER
cluster-ubuntu-hostinger   app-cluster   true     k3s-hostinger
cluster-ubuntu-k3s         app-cluster   true     k3s-aws
ubuntu-k3s-app-cluster     app-cluster   <none>   k3d
```

`ubuntu-k3s-data-layer` is still `NotFound`. The ApplicationSet says why:

```
ParametersGenerated  True   Successfully generated parameters for all Applications
ErrorOccurred        True   application destination spec is invalid: there are 2 clusters
                            with the same name: [https://kubernetes.default.svc
                                                  https://host.k3d.internal:6443]
```

Generation succeeds; **creation** is rejected.

## Root cause

Two cluster Secrets carry the same `name`, pointing at different servers:

| Secret | `name` | `server` | provider |
|---|---|---|---|
| `cluster-ubuntu-k3s` | `ubuntu-k3s` | `https://host.k3d.internal:6443` | `k3s-aws` |
| `ubuntu-k3s-app-cluster` | `ubuntu-k3s` | `https://kubernetes.default.svc` | `k3d` |

The second is the hub registering **itself** under the ACG cluster's name, from
`scripts/plugins/hub_recovery.sh:252` (`hub_recovery_reconcile` step 4, "Hub registration",
added in v1.33.0 `4b6ce874`):

```bash
ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc ARGOCD_APP_CLUSTER_NAME=ubuntu-k3s \
  ARGOCD_APP_CLUSTER_SECRET_NAME=ubuntu-k3s-app-cluster ARGOCD_APP_CLUSTER_PROVIDER=k3d \
  ARGOCD_NAMESPACE=cicd register_app_cluster || return 1
```

It deliberately omits an `environment` label, which is what keeps it clear of the
`platform-helm` selector trap documented in `2026-07-18`. But `destination.name` resolution in
ArgoCD is **global across every cluster Secret**, not scoped to the generator's selector. Two
Secrets claiming `ubuntu-k3s` therefore make *any* name-based destination for that cluster
unresolvable.

### This is not limited to the data layer

Read off the live hub — every cluster-generator ApplicationSet, grouped by how it addresses
its destination:

| ApplicationSet | destination | state |
|---|---|---|
| `eso` | `server: {{.server}}` | generated |
| `platform-helm` | `server: {{.server}}` | generated |
| `data-git` | `name: {{.name}}` | **ErrorOccurred** |
| `services-git` | `name: {{.name}}` | **ErrorOccurred** (`and 5 more`) |
| `grafana-dashboards-acg` | `name: {{.name}}` | **ErrorOccurred** |

Addressing by `server` is unambiguous and unaffected. Addressing by `name` is broken. So the
blocked set is the data layer **plus all six shopping-cart services plus the ACG Grafana
dashboards** — the entire ACG application tier, not one Application.

`ubuntu-hostinger` is unaffected only because nothing else claims its name.

### Pre-existing evidence nobody read

`ubuntu-k3s-grafana-dashboards` has been sitting at `Unknown/Unknown` on the hub — the same
ambiguity, already failing before this release. The collision predates the label fix; the
label fix merely removed the earlier excuse (`shopping-cart: "false"`) and let the real
blocker surface.

## Second, separate finding: the hub's ESO is orphaned

The `eso` ApplicationSet templates `metadata.name: {{.name}}-eso`. Both the hub
self-registration and the real ACG registration are named `ubuntu-k3s`, so both generate the
single Application `ubuntu-k3s-eso` — and only one server can win.

Live state:

| Cluster | `secrets` ns deployments | age | tracking-id |
|---|---|---|---|
| hub (`k3d-k3d-cluster`) | `external-secrets{,-cert-controller,-webhook}` | 4d3h | `ubuntu-k3s-eso:…` |
| ACG (`ubuntu-k3s`) | `external-secrets{,-cert-controller,-webhook}` | 33m | `ubuntu-k3s-eso:…` |

`ubuntu-k3s-eso.spec.destination.server` is now `https://host.k3d.internal:6443`. The ACG
registration won, so the Application that installed the hub's ESO four days ago has been
**retargeted away from the hub**. The hub's ESO pods still run, still carry the tracking
annotation, and are managed by nothing. This is the concrete form of the standing
"ESO re-homing" item, and it is a direct consequence of the same name collision.

## Remedy — needs an owner decision

All three options mutate a live registration Secret that four ApplicationSets select on, so
none may be applied without the owner's word.

1. **Delete `ubuntu-k3s-app-cluster`.** Smallest change; clears the ambiguity immediately.
   Cost: the hub loses its `role: app-cluster` registration, so nothing re-adopts the hub's
   ESO — it stays orphaned — and `hub_recovery_reconcile` recreates the Secret on its next run
   unless the code is fixed too.
2. **Rename the hub registration to a distinct cluster name** (e.g. `k3d-cluster`) in
   `hub_recovery.sh:252`, then replace the Secret. Clears the ambiguity *and* gives the hub
   its own `k3d-cluster-eso` Application, which re-adopts the hub's ESO. Cost: it is a rename
   of an AppSet-generated Application — `preserveResourcesOnDeletion` must be verified on the
   `eso` set **before** the rename, per the rename-trap memory, or the hub's ESO is deleted
   rather than re-adopted.
3. **Leave the Secret and stop addressing by name** — switch `data-git`, `services-git` and
   `grafana-dashboards-acg` to `server: {{.server}}`. Touches no live Secret and no recovery
   path, and matches what `eso`/`platform-helm` already do. Cost: the hub keeps a registration
   whose name lies about which cluster it is, and the ESO orphan is untouched.

Option 2 is the only one that fixes both the collision and the orphan, and it is also the only
one carrying the rename trap.

## Lesson

A selector scopes *generation*; it does not scope *destination resolution*. `ubuntu-k3s-app-cluster`
was carefully built to stay out of one selector (`environment`) while still colliding globally
on a field no selector controls. When a registration is crafted to be invisible to a generator,
check what else resolves the same field cluster-wide — and never give two registrations the
same `name`.

Secondary: `ParametersGenerated=True` next to `ErrorOccurred=True` is the signature of
"generated but rejected". The wait loop in `bin/cluster-up` polls the Application's sync status
and never reads the parent ApplicationSet's conditions, so it burned 480s on a rejection that
was printed in full on the AppSet the whole time.
