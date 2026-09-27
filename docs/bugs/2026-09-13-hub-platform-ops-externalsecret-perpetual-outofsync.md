# Bug: `hub-platform-ops` stays OutOfSync on ExternalSecret `platform-ops/app-cluster-kubeconfig` after every successful sync

**Filed:** 2026-09-13
**Branch:** `k3d-manager-v1.33.0`
**Status:** DONE `79b8a10e` — live AppSet reapplied 2026-09-13 15:15Z, hub-platform-ops Synced

---

## Problem

After the 2026-09-13 hub reconcile, `hub-platform-ops` reports `OutOfSync` / `Healthy`. Its only OutOfSync resource is `ExternalSecret platform-ops/app-cluster-kubeconfig`. Observed at 14:40Z:

- A sync operation finished `Succeeded` ("successfully synced (all tasks run)"), and the app was still OutOfSync two minutes later.
- The ExternalSecret is `Ready=True` / `SecretSynced`, so it is not failing.
- The live spec carries ESO API-server defaults that the git manifest omits:
  - `remoteRef.conversionStrategy: Default`, `decodingStrategy: None` and `metadataPolicy: None` on each of the three `data[]` entries
  - `target.deletionPolicy: Retain`
  - `target.template.mergePolicy: Replace`
  - `target.template.metadata: {}`
- `kubectl diff --server-side` of `scripts/etc/argocd/platform-ops/app-cluster-kubeconfig-externalsecret.yaml` against the live object shows **no spec difference**. Only the ArgoCD tracking annotation differs, and that is expected because kubectl does not add it. Server-side, git and live agree.

Cause: the `platform-ops` ApplicationSet (`scripts/etc/argocd/applicationsets/platform-ops.yaml`) syncs with `ServerSideApply=true` but does not enable server-side diff. ArgoCD (hub v3.5.2) then uses its structured-merge client-side diff, which counts server-defaulted CRD fields as drift. selfHeal re-applies, nothing changes, and the app stays OutOfSync.

The repo already fixed this symptom for Istio: `scripts/etc/argocd/applicationsets/istio-ambient.yaml:51-54` sets `argocd.argoproj.io/compare-options: ServerSideDiff=true` on the Application template. That file includes a comment explaining the same default-value false drift.

## Fix

### Before You Start

- `git pull origin k3d-manager-v1.33.0`; read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- Read `scripts/etc/argocd/applicationsets/platform-ops.yaml` in full and `scripts/etc/argocd/applicationsets/istio-ambient.yaml` lines 45-58.
- Read `scripts/tests/plugins/grafana_dashboard_appsets.bats` for the AppSet YAML test idiom.

### P1 — `scripts/etc/argocd/applicationsets/platform-ops.yaml`

Old:

```yaml
  template:
    metadata:
      name: '{{.name}}-platform-ops'
      labels:
        app-type: platform
```

New:

```yaml
  template:
    metadata:
      name: '{{.name}}-platform-ops'
      annotations:
        argocd.argoproj.io/compare-options: ServerSideDiff=true
      labels:
        app-type: platform
```

Do NOT change `syncOptions`, the source, or the ExternalSecret manifest. Do NOT add `ignoreDifferences`. Server-side diff is the fix, so masking fields is not needed.

### Tests — new `scripts/tests/plugins/platform_ops_appset_diff.bats`

1. The `platform-ops.yaml` Application template enables server-side diff. Use `yq`, or `awk` to extract the `template:` → `metadata:` block, so the match is scoped to the template. Assert that block contains `argocd.argoproj.io/compare-options` and `ServerSideDiff=true`.
2. The file still contains `ServerSideApply=true`. This guards against the fix being "made" by dropping SSA.
3. `app-cluster-kubeconfig-externalsecret.yaml` has no `ignoreDifferences`, and `platform-ops.yaml` contains `ignoreDifferences` 0 times (`grep -c` outputs `0`).

Assert on tokens, not whole source lines.

## Definition of Done

- [ ] P1 implemented exactly; only `scripts/etc/argocd/applicationsets/platform-ops.yaml`, the new BATS file and `CHANGELOG.md` changed
- [ ] `bats scripts/tests/plugins/platform_ops_appset_diff.bats scripts/tests/plugins/argocd_platform_ops_bootstrap.bats` green — paste the summary
- [ ] CHANGELOG `## [Unreleased]` → `### Fixed`: "`platform-ops` ApplicationSet enables `ServerSideDiff=true` so `hub-platform-ops` no longer sits OutOfSync on ESO-defaulted ExternalSecret fields"
- [ ] Commit message verbatim: `fix(argocd): server-side diff for platform-ops so ESO defaults are not drift`
- [ ] Pushed to `origin/k3d-manager-v1.33.0`; report the SHA

## Rollout (operator step — NOT for Codex)

The ApplicationSet must be reapplied on the hub, per the CLAUDE.md "reapply the ApplicationSets on every release" rule, before the Application picks up the annotation. Afterwards, confirm with `kubectl --context k3d-k3d-cluster -n cicd get application hub-platform-ops -o jsonpath='{.status.sync.status}'` that it shows `Synced`.

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`
- Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, or any file outside the targets
- Do NOT apply anything to a live cluster (no `kubectl apply`, no `argocd` CLI)

---

## Recurrence 2026-09-26 — `hub-vectordb`, same cause, new ApplicationSet

The v1.39.0 WS1 vector-store ApplicationSet (`scripts/etc/argocd/applicationsets/vectordb.yaml`)
reproduced this exactly: `hub-vectordb` sat `OutOfSync` with `ExternalSecret vectordb/vectordb-postgres`
as its only OutOfSync resource, while every sync operation reported `Succeeded` /
`serverside-applied`. The other three resources (PVC, Service, StatefulSet) were `Synced`.

Confirmed the same fingerprint:

- A server-side dry-run apply as field manager `argocd-controller` produced **no diff** against
  live — `NO DIFF live vs predicted`. Git and live agree.
- Field ownership was byte-identical to the Synced `platform-ops/app-cluster-kubeconfig`:
  `argocd-controller` (Apply) owning `spec.{data,refreshInterval,secretStoreRef,target}`,
  `external-secrets` (Update) owning the finalizer and `spec.target.template.metadata`.
- The controller log showed the self-heal loop this bug describes: apply succeeds, the next
  comparison is OutOfSync again, `SelfHealAttemptsCount: 5`, then
  `Skipping auto-sync: already attempted sync ... (retrying in 2m41s)`.

The discriminator is the Application template annotation this doc's fix added, and nothing else:

| ApplicationSet | `compare-options` on the live Application | sync |
|---|---|---|
| `platform-ops` | `ServerSideDiff=true` | `Synced` |
| `vectordb` (before fix) | `None` | `OutOfSync` |

### Hypotheses tested and refuted

Recording these so the next recurrence goes straight to the annotation:

- **CRD-defaulted fields are the drift** — refuted. The Synced `platform-ops` ExternalSecret
  carries the identical defaults (`deletionPolicy`, `mergePolicy`, `template.metadata`,
  `conversionStrategy`, `decodingStrategy`, `metadataPolicy`).
- **`SecretSyncedError` causes OutOfSync** — refuted. The three `identity` ExternalSecrets are
  `SecretSynced` and still OutOfSync (that app is blocked by the separate `Replace=true` bound-PVC
  bug, so its sync op never completes).
- **A missing `kubectl.kubernetes.io/last-applied-configuration` annotation** — refuted. No
  ExternalSecret on the hub has one, including the Synced `platform-ops` object.
- **An undeclared `target.template.engineVersion`** — refuted by experiment. Declaring it
  explicitly (`afed4ec9`) changed nothing; `hub-vectordb` picked the commit up and stayed
  OutOfSync. Reverted in the fix commit.
- **A poisoned comparison cache from the `InvalidSpecError` period** — not the cause;
  `status.sync.comparedTo` matched `spec.source` exactly and the revision was current.

### Fix applied

`scripts/etc/argocd/applicationsets/vectordb.yaml` gained the same annotation on its Application
template, plus two gates in `scripts/tests/plugins/argocd_vectordb.bats` (server-side diff
enabled; SSA retained and `ignoreDifferences` absent, so the gate cannot be satisfied by dropping
SSA or by masking fields). The first gate was mutation-checked: removing the annotation turns
test 8 red.

### Latent gap — not fixed here

`observability.yaml` and `data-git.yaml` also lack the annotation. Neither currently shows the
symptom (their ExternalSecrets live on `ubuntu-hostinger` and report `Synced`), so this is a
latent exposure rather than an active bug — but any ESO resource added to those sets will drift
the same way. The durable fix is to make the annotation part of the ApplicationSet template
convention rather than adding it per set after each recurrence; this is now the third set to need
it (`istio-ambient`, `platform-ops`, `vectordb`).
