# Bug: promoted PrometheusRule changes never reach the hub Prometheus; `K3dmPromoteWaiting` is not loaded

**Status:** LANDED — `a4460629` (Luna; Claude review fixes). Offline: independent Opus verifier pass (M1-M5, N1-N4 with positive controls), pre-fix 3/3 red, 11 appset mutants red, Fable review nothing above medium. Live E5-E7 pending
**Priority:** P2 (new and changed alerts silently absent after a promote; workaround `make prometheus-rules` on the M5)
**Waiting on:** live check — since 2026-11-14 (promote incl. a4460629, then `make appsets-reapply APPSETS_STAGE=hub`, E5/E6)
**Intent approved:** operator ("go ahead"), 2026-11-14
**Introduced by:** pre-existing (rules apply only through `make prometheus-rules` / observability deploy); exposed by `c763e239` (v1.44.0 plan 3)
**Should have been caught by:** spec (plan 3 lists no deploy step for its rule; E6 is the first live check that needs it)
**Prior art:** exact-slug glob: none; `docs/bugs/2026-10-03-sandbox-make-up-host-alias-and-rules-crd-race.md` (title only, different). `make find-similar-docs` not run

## Symptom

Read-only probes of the M5 on 2026-11-13, 14:30Z:
- deploy/hub = `e6b62305`, and `git show e6b62305:scripts/etc/prometheus/rules/repo-sync.yaml` has four alerts: K3dmRepoSyncStale, K3dmDeployPending, K3dmPromoteWaiting, K3dmPromoteLookupFailed.
- The hub Prometheus (`127.0.0.1:19091/api/v1/rules`) group `repo.sync` has only `K3dmRepoSyncStale` and `K3dmDeployPending`.
- The metric is there: Pushgateway has `k3dm_repo_sync_promotable{sha="e9c375c",instance="m5-air"} 1` since 14:27:58Z. So the alert can never fire.

## Root cause

- PrometheusRules are not GitOps-managed. They reach the cluster only via `make prometheus-rules` (`Makefile:1367`) or a full observability deploy (`scripts/plugins/observability.sh:58`).
- The promote sequence (`make hub-promote`, `make appsets-check`, `make platform-ops`) does not include it.
- repo-sync's `deploy_pending` steps are `platform-ops`, `appsets-reapply` and `webhook-restart` (`bin/k3dm-repo-sync` ~499). A promote that changes `scripts/etc/prometheus/rules/` therefore raises no `K3dmDeployPending`.

## Options (operator decision)

1. Add a `prometheus-rules` deploy_pending step to repo-sync, keyed on `scripts/etc/prometheus/rules/` changes, with a marker the way platform-ops has one, so `K3dmDeployPending` names it.
2. Manage the hub rules through an ArgoCD Application reading deploy/hub (like platform-ops), which removes the manual step.
3. Make `make platform-ops` also apply the rules.

## Unblock E6 now

The operator runs `make prometheus-rules` on the M5. It is additive `kubectl apply` of the rule files.

## Decision 2026-11-14

Operator, 2026-11-14: "go with your recommendations" — **option 2**: manage the hub PrometheusRules through an ArgoCD Application that reads `deploy/hub` (like platform-ops), so a promote applies rule changes with no manual step.

## Spec (2026-11-14; drafted by Sonnet, reviewed by Claude)

## Findings (read-only investigation, 2026-11-14)

- Today the rules reach the hub only by `make prometheus-rules` (`Makefile:1367-1373`: loops `scripts/etc/prometheus/rules/*.yaml`, `envsubst '$CF_DOMAIN'`, `kubectl --context $(INFRA_CONTEXT) apply -f -`) or by a full `deploy_observability` (`scripts/plugins/observability.sh:58-75`, same envsubst + `_kubectl apply`). The promote sequence (`Makefile:493-498`: hub-promote, appsets-check, platform-ops) does neither.
- Nine files in `scripts/etc/prometheus/rules/`. Eight are plain `PrometheusRule` manifests, `namespace: monitoring`, `labels: release: kube-prometheus-stack` (e.g. `repo-sync.yaml:1-7`), which is the label the Prometheus ruleSelector needs. One, `public-endpoint-probes.yaml`, is two `kind: Probe` documents with seven `${CF_DOMAIN}` placeholders (`public-endpoint-probes.yaml:20-23,44-46`). It is the ONLY file with a placeholder (grep `\${` over the directory). ArgoCD cannot envsubst, so a directory source would apply the literal text `https://argocd.${CF_DOMAIN}/` as a probe target. It must stay out of the Application.
- Model to mirror: `scripts/etc/argocd/applicationsets/grafana-dashboards-hub.yaml` (hub list generator, `project: platform`, destination `monitoring` on `https://kubernetes.default.svc`, `targetRevision: '${K3D_MANAGER_BRANCH}'`, `directory`, automated prune+selfHeal, `ServerSideApply=true`) and `applicationsets/platform-ops.yaml:20,40` (`argocd.argoproj.io/compare-options: ServerSideDiff=true` on the template, per the SSA perpetual-OutOfSync note; pinned by `scripts/tests/plugins/platform_ops_appset_diff.bats`). `K3D_MANAGER_BRANCH` is `deploy/hub` when `make appsets-reapply` runs (`Makefile:468-470`); `${...}` vars in appset files are envsubst'd per file (`scripts/plugins/argocd.sh:1538-1542`).
- AppProject `platform` already allows `monitoring` on the in-cluster server and any namespaced kind (`scripts/etc/argocd/projects/platform.yaml.tmpl:80-81,127-129`): no AppProject change.
- Every ApplicationSet file needs `k3dm.k3d.io/rollout-stage: hub|app-cluster` at 4-space indent in `metadata.labels` (`argocd.sh:1213-1225`; `argocd_appset_rollout_stage.bats:33-39`). `appsets-check` (`Makefile:473-474`) reports Applications of those sets not reading the expected branch.
- repo-sync: `deploy_pending` tracks only `platform-ops`, `appsets-reapply`, `webhook-restart` (`bin/k3dm-repo-sync:499`); the platform-ops diff is limited to `scripts/etc/argocd/platform-ops` (`:411`). Once ArgoCD syncs rules on its own there is nothing pending: no repo-sync change. A NEW ApplicationSet file is picked up by the existing `appsets-reapply` pending step (appset drift, `:435`) only if drift shows; the operator applies it once (see Rollout).

- **Adoption proof (external behaviour, Claude, 2026-11-14).** Hub ArgoCD is `quay.io/argoproj/argocd:v3.5.5` (`cicd/argocd-server`). The hub's own PrometheusRules (`repo-sync`, `host-disk`, read with `kubectl get prometheusrule -n monitoring --show-managed-fields` over ssh to m5-air) are managed only by `kubectl-client-side-apply` (operation Update) and carry `last-applied-configuration`. Upstream `docs/user-guide/sync-options.md` at tag `v3.5.5`: `ServerSideApply=true` applies with `kubectl apply --server-side --force-conflicts` (:296), and "Client-Side Apply Migration ... moving a resource's managed fields from one manager to Argo CD's manager ... By default, client-side apply migration is enabled" (:360-366). So adoption needs no extra option; E6 confirms it live.

## Fix

1. Add `scripts/etc/argocd/applicationsets/prometheus-rules-hub.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: prometheus-rules-hub
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    managed-by: k3d-manager
    app-type: observability
    k3dm.k3d.io/rollout-stage: hub
spec:
  generators:
    - list:
        elements:
          - name: hub-prometheus-rules
  goTemplate: true
  template:
    metadata:
      name: '{{.name}}'
      annotations:
        argocd.argoproj.io/compare-options: ServerSideDiff=true
      labels:
        app-type: observability
    spec:
      project: platform
      destination:
        server: https://kubernetes.default.svc
        namespace: monitoring
      source:
        repoURL: https://github.com/wilddog64/k3d-manager
        targetRevision: '${K3D_MANAGER_BRANCH}'
        path: scripts/etc/prometheus/rules
        directory:
          recurse: false
          include: '*.yaml'
          exclude: 'public-endpoint-probes.yaml'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
          allowEmpty: false
        syncOptions:
          - ServerSideApply=true
```

   - `exclude` (not an include list) so a new rule file is picked up with no appset edit; the Probe file is the one templated file and stays on `make prometheus-rules` / `deploy_observability`.
   - `prune: true` matches platform-ops and grafana-dashboards-hub: a rule file deleted on deploy/hub is deleted from the cluster. `allowEmpty: false` stops an empty path from pruning every rule.
   - No `ignoreDifferences` (platform_ops_appset_diff.bats precedent); `ServerSideDiff=true` is the SSA/OutOfSync mitigation.
   - No `CreateNamespace` (monitoring exists from the kube-prometheus-stack Application).
2. Rule files that gain a `${...}` placeholder must be added to the exclude list, or the guard test below fails. Say so in a comment-free way: the test message names this.
3. `make prometheus-rules` and the `deploy_observability` rules loop stay unchanged (bootstrap before ArgoCD exists, non-hub clusters, and the Probe file). Add one line to `docs/howto/public-endpoint-alerts.md` (after its `deploy_observability` sentence): on the hub the PrometheusRule files are applied by ArgoCD from deploy/hub; only `public-endpoint-probes.yaml` still needs `make prometheus-rules`. Add a row to the Makefile help text for `prometheus-rules` only if one exists (none found near `Makefile:1804-1836`; do not add).
4. Update bug doc Status/Waiting-on as the Claude lander does; the worker does not touch `docs/bugs/`.

## Contract readers

Contract: who applies the hub PrometheusRules from `scripts/etc/prometheus/rules/`.

Writers (apply the files to the hub cluster):
- `Makefile:1367-1373` `prometheus-rules`: unchanged; now a second writer on the hub. Same files, but from the operator checkout (release branch) not deploy/hub, so running it can briefly revert a promoted rule until ArgoCD selfHeal re-syncs. Documented, not changed.
- `scripts/plugins/observability.sh:58-75` `deploy_observability` rules loop: unchanged; same caveat; runs at bootstrap/rebuild.
- NEW `scripts/etc/argocd/applicationsets/prometheus-rules-hub.yaml`: the ArgoCD writer.
- Not a writer: `observability.sh:760` applies `rules-acg/` (ACG sandbox, different directory, not in scope).

Readers (consume the directory or its files):
- `Makefile:1542` `VALIDATE_MANIFESTS_DEFAULT` includes `scripts/etc/prometheus/rules/*.yaml` and `applicationsets/*.yaml`: the new appset is validated automatically; no change.
- `scripts/tests/plugins/observability_public_endpoint_probes.bats:27-47,50`: allowlist and Probe guards; unchanged, still green.
- `scripts/tests/bin/test_cni_ipam_rules.py:9`, `test_host_disk_rules.py:11`, `test_orbstack_metrics.py:76,126`, `test_dashboard_queries.py:23`, `scripts/tests/plugins/vectordb_rules.bats:7`: parse single files; unchanged.
- `scripts/tests/plugins/argocd_appset_rollout_stage.bats:33-39` and `appset_envsubst_coverage.bats` (every `${VAR}` in an appset is defaulted in `argocd/vars.sh` or `argocd.sh`): the new file uses only `ARGOCD_NAMESPACE` and `K3D_MANAGER_BRANCH`; both already defaulted. No change.
- `scripts/plugins/argocd.sh:1217-1225,1503-1560` appset deploy loop and `:2054` `argocd_check_values_branch`: enumerate appset files generically; the new file is picked up with no code change.
- `bin/k3dm-repo-sync:411,435,499`: no path under `scripts/etc/prometheus/rules` is tracked; no change (ArgoCD auto-syncs).
- `docs/howto/public-endpoint-alerts.md:9-11`: doc line changes (Fix 3).
- `memory-bank/activeContext.md` lines naming `make prometheus-rules` as the E6 unblock: historical, not edited by the worker.

## Acceptance

```yaml
must:
  M1: scripts/etc/argocd/applicationsets/prometheus-rules-hub.yaml exists, kind ApplicationSet, carries label k3dm.k3d.io/rollout-stage hub, and its Application reads path scripts/etc/prometheus/rules at targetRevision ${K3D_MANAGER_BRANCH} (rendered with deploy/hub, it reads deploy/hub)
  M2: the Application is project platform, destination namespace monitoring on the in-cluster server, with automated prune and selfHeal, ServerSideApply=true, and the ServerSideDiff=true compare-options annotation
  M3: every rule file the Application would apply (directory listing minus its exclude) is a PrometheusRule in namespace monitoring with label release kube-prometheus-stack and contains no ${...} placeholder
  M4: public-endpoint-probes.yaml is excluded by the Application
  M5: the repo's own offline checks stay green (appset rollout-stage, envsubst-coverage, platform-ops diff, public-endpoint-probes suites)
must_not:
  N1: the Application applies any file with an unrendered ${...} placeholder (guard: needs a positive control, see E3)
  N2: the Application source reads a hardcoded branch (main or a release branch) instead of ${K3D_MANAGER_BRANCH} (guard with positive control, E3)
  N3: the Application sets ignoreDifferences or omits allowEmpty false
  N4: any existing file under scripts/etc/prometheus/rules/ or the Makefile prometheus-rules / observability.sh rules loop is modified
evidence:
  - {id: E1, proves: [M1, M2, M4], kind: offline, intent: "You will see a test that renders the new ApplicationSet with deploy/hub and reads back the repo path, the deploy/hub revision, the hub stage label, server-side diff and apply, prune and self-heal, and the Probe file excluded. Today the file does not exist, so it fails."}
  - {id: E2, proves: [M3, N3], kind: offline, intent: "You will see a test that lists the files the Application would apply and shows each one parses as a PrometheusRule in monitoring with the release label and no unrendered placeholder, and that the appset never masks differences. Today there is no Application to list, so it fails."}
  - {id: E3, proves: [N1, N2], kind: offline, intent: "You will see the guard prove it can fail: a scratch copy of the rules directory with an added placeholder file, and a scratch appset pinned to a branch name, each make the same checks go red; the real tree stays green. Without this the guard could pass for the wrong reason."}
  - {id: E4, proves: [M5, N4], kind: offline, intent: "You will see the existing rollout-stage, envsubst-coverage, platform-ops diff and public-endpoint-probes suites pass unchanged, and git showing none of the rule files, the Makefile or observability.sh edited."}
  - {id: E5, proves: [M1, M2], kind: live, intent: "You will see, after the promote and one appset apply, the Application hub-prometheus-rules Synced and Healthy on the hub, and the Prometheus rules API listing K3dmPromoteWaiting and K3dmPromoteLookupFailed in group repo.sync without anyone running make prometheus-rules. Run by operator or Claude."}
  - {id: E6, proves: [M3], kind: live, intent: "You will see the already-applied PrometheusRules adopted without recreation: same objects, now carrying ArgoCD tracking, and the Application stays Synced (no perpetual OutOfSync) five minutes later. Run by operator or Claude."}
  - {id: E7, proves: [M1], kind: live, intent: "You will see a trivial rule edit (for example an annotation) promoted to deploy/hub and appearing in the Prometheus rules API within a few minutes with no manual step, then reverted the same way. Run by operator or Claude; optional if E5 and E6 pass."}
interface:
  - "scripts/etc/argocd/applicationsets/prometheus-rules-hub.yaml (ApplicationSet prometheus-rules-hub, Application hub-prometheus-rules)"
  - "make appsets-reapply / make appsets-check (unchanged)"
```

Regression-guard note: N1 to N3 are all vacuously true on today's code (no Application exists), so they cannot be red there. They are regression guards, each with a positive control (E3: the same assertion run against a bad fixture must fail). The pre-fix red items are M1 to M4, which fail on today's tree because the file is missing.

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/applicationsets/prometheus-rules-hub.yaml` | new ApplicationSet (Fix 1) |
| `scripts/tests/plugins/prometheus_rules_appset.bats` | new: E1, E2, E3 (uses `yq` as `grafana_dashboard_appsets.bats` does; stub nothing, pure file logic) |
| `docs/howto/public-endpoint-alerts.md` | one sentence (Fix 3) |

No change to the Makefile, `observability.sh`, `bin/k3dm-repo-sync`, the AppProject or any rule file.

## Rollout

1. Land the change on the release branch, CI green; `make hub-promote REF=<commit>`; `make appsets-check`; `make platform-ops` (the usual sequence).
2. One-time: the new ApplicationSet is not on the cluster until applied. Run `make appsets-reapply APPSETS_STAGE=hub` (operator tmux; `Makefile:467-470`), then `make appsets-check`. After that, later rule changes need only the promote.
3. Live checks E5 and E6. If E6 shows OutOfSync because of field-manager conflicts with the old client-side-applied objects, force one sync (`argocd app sync hub-prometheus-rules --force`) and file a bug; do not add `ignoreDifferences`.
   Also for E6 (Fable review 2026-11-14): `kubectl get prometheusrule host-disk -n monitoring --show-managed-fields -o yaml` after the first sync; a remaining `kubectl-client-side-apply` manager means a later removed group or label can stay live. Record it; `make prometheus-rules` re-adds that manager.
4. Probes: `make prometheus-rules` (or `deploy_observability`) remains the way to change `public-endpoint-probes.yaml`.
5. Rule files removed from deploy/hub before this ships stay in the cluster untracked; delete by hand if any exist.

## Worker definition of done

- Change only the files above. Offline tests only: no cluster, no network; stub `kubectl`, `argocd`, `gh`, `ssh` on PATH if a code path reaches them; scratch HOME; `PUSHGATEWAY_URL=http://127.0.0.1:9`. Run `yq` against fixtures only.
- Show E1 and E2 red on today's tree (new file absent), then green; show the E3 bad-fixture runs red and the real tree green.
- Run, from the repo root: `bats scripts/tests/plugins/prometheus_rules_appset.bats scripts/tests/plugins/argocd_appset_rollout_stage.bats scripts/tests/plugins/appset_envsubst_coverage.bats scripts/tests/plugins/platform_ops_appset_diff.bats scripts/tests/plugins/observability_public_endpoint_probes.bats` and `make validate-manifests FILES=scripts/etc/argocd/applicationsets/prometheus-rules-hub.yaml` if kubeconform is present (report if not). Paste each command, rc and proving lines, and list every error seen.
- Leave changes uncommitted; do not push; do not run any live check (E5 to E7 belong to the operator or Claude).
