# Bug: Hostinger lost its hub ArgoCD registration — shopping-cart workloads orphaned, and the only re-register path moves the hub's istio and edge

**Filed:** 2026-09-13
**Branch:** `k3d-manager-v1.33.0`
**Status:** DONE — `14f26f3d`; live re-registration run by user 2026-09-13, Claude-verified
**Decision (user, 2026-09-13):** re-register `ubuntu-hostinger` with the hub. This is additive: the hub stays an app cluster and keeps serving the public edge.

---

## Problem

Live read-only checks on 2026-09-13:

- The hub restore (2026-09-11) recreated only `cicd/ubuntu-k3s-app-cluster` (in-cluster). No `cluster-ubuntu-hostinger` Secret exists on the hub, so none of the `ubuntu-hostinger-*` Applications exist either.
- `ubuntu-hostinger` (node `srv1754834`, 2 CPU) still runs workloads that nothing manages now:
  - shopping-cart pods, tracking id `ubuntu-hostinger-shopping-cart-*`
  - a platform ArgoCD, release `argocd-ubuntu-hostinger`, chart `argo-cd-7.8.1`, tracking id `ubuntu-hostinger-platform:...`
  - istio, kyverno, monitoring, `secrets` and trivy-system
- `argocd-manager` SA exists on hostinger (53d).

The only code path that registers hostinger is `make refresh CLUSTER_PROVIDER=k3s-hostinger` → `_provider_k3s_hostinger_refresh_cluster` (`scripts/lib/providers/k3s-hostinger.sh:1019`). Running it now against the hub-as-app-cluster topology is unsafe:

- `_hostinger_reapply_gitops_applicationsets` re-renders `istio-ambient.yaml` with `APP_CLUSTER_NAME=ubuntu-hostinger`. That ApplicationSet has a **single** destination (`name: ${APP_CLUSTER_NAME}`), so the hub's `istiod-ubuntu-k3s` would be replaced by `istiod-ubuntu-hostinger`.
- `_hostinger_refresh_access_layer` rewrites the laptop port-forwards and restarts cloudflared toward hostinger. That moves the public edge off the hub.
- It also runs the Vault tunnel/bridge, frontend restart and tracking-id rewrite, none of which registration needs.

There is no registration-only entry point.

## Fix

Add a registration-only provider action, `refresh_registration`, that does exactly one thing: calls the existing `_hostinger_register_cluster`, always in additive mode.

Why additive is mandatory: exclusive mode (`K3DM_EXCLUSIVE_APP_CLUSTER=true`) strips `k3d-manager/role=app-cluster` from `ubuntu-k3s-app-cluster`. `services-git`/`data-git` would then delete every hub `ubuntu-k3s-*` Application, taking down the shopping cart the public edge serves.

What registering hostinger does, all intended:

- The cluster Secret gets `environment=dev`, `argocd-chart-version`, `argocd-replicas`, and `k3d-manager/role=app-cluster` (additive).
- `platform-helm` generates `ubuntu-hostinger-platform`, which adopts the existing `argocd-ubuntu-hostinger` release (same release name, same chart 7.8.1).
- `services-git`/`data-git`/`eso`/`observability-acg`/`grafana-dashboards-acg`/`hostinger-cve-inventory-reader` generate `ubuntu-hostinger-*` apps, which adopt the live resources (tracking ids already match).

### Before You Start

- `git pull origin k3d-manager-v1.33.0`; read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- Read `scripts/lib/providers/k3s-hostinger.sh` lines 132-172 (`_hostinger_register_cluster`) and 1011-1017 (`_provider_k3s_hostinger_refresh_access_layer`, the pattern to mirror).
- Read `scripts/lib/core.sh` lines 563-569.
- Read `Makefile` line 16 (`.PHONY`) and lines 130-135 (`refresh-edge`, the pattern to mirror).
- Read `scripts/tests/lib/provider_contract.bats` lines 409-460 (refresh_cluster stub test, the pattern to mirror).

### S1 — provider action (`scripts/lib/providers/k3s-hostinger.sh`)

Insert directly **after** `_provider_k3s_hostinger_refresh_access_layer` (after its closing `}` at line 1017):

```bash

function _provider_k3s_hostinger_refresh_registration() {
  _hostinger_require_host >/dev/null || return 1
  if [[ "${K3DM_EXCLUSIVE_APP_CLUSTER:-false}" == "true" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] refresh_registration is additive-only; K3DM_EXCLUSIVE_APP_CLUSTER=true would strip the app-cluster role from the hub registration" >&2
    return 1
  fi
  _info "[k3s-hostinger] Refreshing ArgoCD registration only (additive) — no GitOps reapply, no edge changes"
  K3DM_EXCLUSIVE_APP_CLUSTER=false _hostinger_register_cluster || return 1
  _info "[k3s-hostinger] Registration refresh complete"
  printf '%s\n' "__WEBHOOK_SUCCESS__"
}
```

### S2 — public dispatcher entry (`scripts/lib/core.sh`)

Old:

```bash
function refresh_access_layer() {
   _cluster_provider_call refresh_access_layer "$@"
}
```

New:

```bash
function refresh_access_layer() {
   _cluster_provider_call refresh_access_layer "$@"
}

function refresh_registration() {
   _cluster_provider_call refresh_registration "$@"
}
```

### S3 — Makefile target

1. Append ` refresh-registration` to the end of the `.PHONY` line (line 16).
2. Insert directly after the `refresh-edge` recipe (after line 135):

```make

## Re-register k3s-hostinger with the hub ArgoCD only (additive) — no GitOps reapply, no edge changes
refresh-registration:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-hostinger) CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager refresh_registration ;; \
	  *) echo "refresh-registration is k3s-hostinger-only (CLUSTER_PROVIDER=$(CLUSTER_PROVIDER))"; exit 1 ;; \
	esac
```

Recipe lines must be indented with a TAB.

### Tests — `scripts/tests/lib/provider_contract.bats`

Add three tests after the existing `_provider_k3s_hostinger_refresh_cluster ...` test. Stub the same way that test does, logging to `${BATS_TEST_TMPDIR}/refresh.log`.

1. **`_provider_k3s_hostinger_refresh_registration registers only and never touches gitops, edge, or vault`**
   - Stub `_hostinger_require_host`, `_hostinger_register_cluster` (log `register exclusive=${K3DM_EXCLUSIVE_APP_CLUSTER:-unset}`), and every other step `_provider_k3s_hostinger_refresh_cluster` calls (`_hostinger_merge_kubeconfig`, `deploy_observability_acg`, `_hostinger_reapply_gitops_applicationsets`, `_hostinger_clear_stale_platform_tracking_ids`, `_hostinger_reconcile_vault_cluster_store`, `_hostinger_refresh_frontend_dns`, `_hostinger_refresh_access_layer`), each logging its own token.
   - Unset `K3DM_EXCLUSIVE_APP_CLUSTER`.
   - Assert status 0, output contains `__WEBHOOK_SUCCESS__`, the log contains `register exclusive=false`, and the log does **not** contain any of `merge`, `gitops-appsets`, `access`, `vault`, `frontend-dns`, `tracking-fix`, `observability`.
2. **`_provider_k3s_hostinger_refresh_registration refuses exclusive mode`**
   - Set `K3DM_EXCLUSIVE_APP_CLUSTER=true`.
   - Assert status non-zero, output contains `additive-only`, and the register stub was never called (log file absent or lacks `register`).
3. **`_provider_k3s_hostinger_refresh_registration propagates register failure`**
   - Make the `_hostinger_register_cluster` stub `return 1`.
   - Assert status non-zero and output lacks `__WEBHOOK_SUCCESS__`.

Assert on tokens, not whole source lines.

## Definition of Done

- [ ] S1-S3 implemented exactly; only `scripts/lib/providers/k3s-hostinger.sh`, `scripts/lib/core.sh`, `Makefile`, `scripts/tests/lib/provider_contract.bats` and `CHANGELOG.md` changed
- [ ] `grep -c '_provider_k3s_hostinger_refresh_registration' scripts/lib/providers/k3s-hostinger.sh` outputs `1`
- [ ] `shellcheck -x scripts/lib/providers/k3s-hostinger.sh scripts/lib/core.sh`: no new warnings vs `HEAD~` (paste both counts)
- [ ] `bats scripts/tests/lib/provider_contract.bats` green; paste the summary
- [ ] `make -n refresh-registration CLUSTER_PROVIDER=k3s-hostinger` prints the `refresh_registration` command; `make refresh-registration CLUSTER_PROVIDER=k3d` prints the k3s-hostinger-only message and exits non-zero (both are safe; neither runs the dispatcher)
- [ ] CHANGELOG `## [Unreleased]` → `### Added`: "`make refresh-registration CLUSTER_PROVIDER=k3s-hostinger` re-registers Hostinger with the hub ArgoCD only (additive; no GitOps reapply, no edge changes) — restores the `ubuntu-hostinger-*` apps lost in the hub restore". Create the `### Added` heading above `### Fixed` if it does not exist.
- [ ] Commit message verbatim: `feat(hostinger): registration-only refresh to re-attach hostinger to the hub additively`
- [ ] Pushed to `origin/k3d-manager-v1.33.0`; `git rev-parse origin/k3d-manager-v1.33.0` equals the commit SHA; report the SHA

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, or use `--no-verify`
- Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, or any file outside the targets
- Do NOT change `_hostinger_register_cluster`, `register_app_cluster`, `_provider_k3s_hostinger_refresh_cluster`, or any ApplicationSet
- Do NOT run anything against a live cluster, including `make refresh-registration` without `-n`

---

## Live runbook (operator — needs the user's go; hub + hostinger mutation)

Run only after the code is merged to the branch and verified.

1. **Pre-check (read-only).** The hub has exactly one cluster Secret, `ubuntu-k3s-app-cluster`, with `k3d-manager/role=app-cluster`. Record the `ubuntu-k3s-*` Application count.
   ```
   kubectl --context k3d-k3d-cluster -n cicd get secret -l argocd.argoproj.io/secret-type=cluster -L k3d-manager/role,environment
   kubectl --context k3d-k3d-cluster -n cicd get applications --no-headers | grep -c '^ubuntu-k3s-'
   ```
2. **Register.**
   ```
   make refresh-registration CLUSTER_PROVIDER=k3s-hostinger
   ```
3. **Verify (read-only).**
   - `cluster-ubuntu-hostinger` exists with `k3d-manager/role=app-cluster` and `environment=dev`.
   - `ubuntu-k3s-app-cluster` **still** has `role=app-cluster` and **no** `environment` label.
   - The `ubuntu-k3s-*` count is unchanged.
   - `ubuntu-hostinger-*` Applications are generated and reach Synced/Healthy.
   - `ubuntu-hostinger-platform` is Synced, the hostinger `argocd-ubuntu-hostinger-server` still has chart `argo-cd-7.8.1`, and no pods were recreated beyond normal rollouts.
   - Hub `istiod-ubuntu-k3s` is unchanged, and `bin/smoke-test-cluster-health` still reports 9/0.

### Risks and out of scope

- **Auto-sync converges hostinger to the branch's git state.** If its live images or manifests lag git, rollouts follow on a 2-CPU node. See the `maxSurge=0` stopgap note (`reference_hostinger_maxsurge_rollout_deadlock`). Watch for Pending pods.
- **Hostinger ExternalSecrets depend on the Vault bridge/tunnel**, which this action deliberately does not touch. If ESO stores go NotReady, that is a separate follow-up, not a reason to run `make refresh`.
- **`istio-ambient` stays single-destination (hub).** Hostinger istio remains unmanaged. Making `istio-ambient` multi-cluster is out of scope.
- **Rollback:** `kubectl --context k3d-k3d-cluster -n cicd label secret cluster-ubuntu-hostinger k3d-manager/role- environment-`, and only **after** confirming the generated apps preserve resources on deletion (see `reference_appset_generated_app_cleanup_ordering`, `reference_preserveresourcesondeletion_rename_trap`). Otherwise hostinger workloads would be pruned.

## Live Result (2026-09-13)

- `cluster-ubuntu-hostinger` created (role=app-cluster, environment=dev); hub `ubuntu-k3s-app-cluster` unchanged; 9 `ubuntu-k3s-*` apps unchanged.
- 12 `ubuntu-hostinger-*` apps plus `observability-acg` apps (`acg-kube-prometheus-stack`, `acg-trivy-operator`, `loki`) generated and adopted the existing hostinger workloads — all Synced/Healthy, no pod restarts. `loki` ran one sync that pruned `loki-canary`.
- Hub istiod unchanged (HPA 2-3 replicas); `bin/smoke-test-cluster-health` 9 passed / 0 failed.
- Deviation from spec: `_hostinger_register_cluster` also (re)configures the Vault app-cluster auth mount `kubernetes-ubuntu-hostinger` + `app-cluster-reader` policy + `eso-app-cluster` role. Idempotent and required by hostinger ESO, but the spec's "no Vault" claim was wrong — the BATS stub of `_hostinger_register_cluster` hid it.
