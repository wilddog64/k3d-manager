# BLOCKED: registering the Hub as `environment=infra` would self-destruct ArgoCD

**Branch:** `k3d-manager-v1.16.0`
**Status:** **DO NOT EXECUTE.** Decision required from the repo owner.
**Supersedes:** the "Phase 2 — Claude-only" section of
`docs/bugs/2026-07-18-argocd-cve-scan-silent-exit-missing-infra-secret.md`

---

## Summary

Phase 2 was scoped as "create an `in-cluster` cluster Secret labelled `environment=infra` so
`argocd-cve-scan` can read a chart version." Investigation on 2026-07-18 shows that action
would take ArgoCD down on the hub. It must not be performed as designed, by Claude or
anyone else, until one of the options below is chosen.

---

## Why it breaks

`platform-helm.yaml` uses a **clusters generator** whose selector is:

```yaml
matchExpressions:
  - key: environment
    operator: In
    values: [dev, infra, prod]
```

Creating any cluster Secret labelled `environment=infra` therefore causes `platform-helm` to
generate a new Application immediately. Its sync policy has no human gate:

```yaml
syncPolicy:
  automated:
    prune: false
    selfHeal: true
```

The generated Application would deploy:

```yaml
repoURL: https://argoproj.github.io/argo-helm
chart: argo-cd
targetRevision: '{{.values.chartVersion}}'   # from the argocd-chart-version label
helm:
  releaseName: argocd-{{.name}}              # → argocd-in-cluster
destination:
  namespace: cicd                            # the namespace ArgoCD itself runs in
```

Measured hub state, 2026-07-18:

```
$ helm -n cicd list
NAME     NAMESPACE  REVISION  STATUS   CHART            APP VERSION
argocd   cicd       3         failed   argo-cd-9.5.15   v3.4.2

$ kubectl -n cicd get secrets -l argocd.argoproj.io/secret-type=cluster
cluster-ubuntu-hostinger   environment=dev   argocd-chart-version=7.8.1
cluster-ubuntu-k3s         environment=dev   argocd-chart-version=7.8.1
```

Combining these, the planned action would have:

1. Created a **second `argo-cd` Helm release** (`argocd-in-cluster`) in `cicd`, alongside
   the existing `argocd` release, both managing the same workloads.
2. **Downgraded the chart from 9.5.15 to 7.8.1** — the value copied from the app clusters —
   spanning CRD and Deployment changes across a major version gap.
3. Done so **automatically**, because `selfHeal: true` means the sync needs no approval and
   will fight any manual correction.
4. Applied all of it on top of a release whose Helm status is already **`failed`**.

The original spec warned that "a malformed `config` block takes down every in-cluster
Application." The real hazard is worse and does not require any malformation — a correctly
formed Secret is sufficient.

### What is NOT affected

Four of the five cluster-generator ApplicationSets select on
`matchLabels: {k3d-manager/role: app-cluster}` and would ignore the new Secret:
`data-git.yaml`, `eso.yaml`, `grafana-dashboards-acg.yaml`, `services-git.yaml`.
`platform-helm` is the only one that matches `infra`.

---

## The underlying design conflict

Two features want the same label to mean different things:

- `cve-scan.sh` wants `environment=infra` as **metadata** — a place to read and patch a
  chart version for the promotion pipeline's middle stage.
- `platform-helm.yaml` treats `environment` as an **instruction** — any matching cluster
  gets the ArgoCD platform chart deployed to it.

On app clusters those coincide harmlessly. On the hub they collide, because the hub is where
ArgoCD already runs. `infra` appears in the `platform-helm` selector, which suggests someone
intended the hub to be self-managed, but it never was — no `infra` Secret has ever existed.

---

## Options (owner decision required)

**Option A — decouple the metadata from the selector.** Change `_chart_label` in
`cve-scan.sh` to read the hub's chart version from something `platform-helm` does not select
on: a plain ConfigMap, or the Helm release itself
(`helm -n cicd list -o json`). No cluster Secret is created, so no Application is generated.
*Assessment: lowest risk, keeps the promotion pipeline intact, touches one function. This is
the recommended default.*

**Option B — narrow the `platform-helm` selector to `[dev, prod]`.** Makes `infra` pure
metadata and allows the Secret to be created safely. *Assessment: small diff, but it changes
ApplicationSet behaviour for every cluster and needs a check that nothing currently relies
on `infra` being selectable. `provider_contract.bats` asserts on this file — derive the gate
list with `grep -rln 'platform-helm' scripts/tests/`.*

**Option C — genuinely self-manage the hub.** Create the Secret with
`argocd-chart-version=9.5.15` to match reality, accept `argocd-in-cluster` as a real
Application, and reconcile the duplicate-release problem by adopting the existing `argocd`
release name. *Assessment: highest risk and largest scope. Also requires fixing the `failed`
Helm release first. Not a bugfix — this is a project.*

**Option D — leave `argocd-cve-scan` red.** `5fcc3f89` already makes it fail loudly. Do
nothing further until the promotion pipeline's infra stage is actually needed.
*Assessment: valid. The job is now honest about being broken, which was the real defect.*

---

## Separate finding — the hub's Helm release is `failed`

`helm -n cicd list` reports the `argocd` release at revision 3 with status **`failed`**,
dated 2026-06-29. This is unrelated to the CVE scan work and predates it by ~3 weeks. The
hub is functioning, so this is likely a partially-applied upgrade that left the release
metadata inconsistent. It should be investigated on its own before any option above that
touches Helm state (B or C). Not filed as a separate bug yet — needs triage first to
determine whether it is cosmetic or real.

---

## What NOT to do

- Do NOT create a cluster Secret labelled `environment=infra` on the hub under any
  circumstances until an option is chosen. This is the specific action that triggers the
  failure.
- Do NOT copy `argocd-chart-version=7.8.1` from the app-cluster Secrets. The hub runs
  9.5.15. That mismatch is what turns the mistake into a downgrade.
- Do NOT add `k3d-manager/role: app-cluster` to any hub Secret — that would pull the hub
  into the other four ApplicationSets as well.
- Do NOT set `selfHeal: false` on `platform-helm` as a workaround. It would mask this
  hazard while changing sync behaviour for the real app clusters.
- Do NOT delegate any of this to an agent. Every option touches live ArgoCD state.
