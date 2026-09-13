# Bug: in-cluster `register_app_cluster` labels make `platform-helm` install a second ArgoCD on the hub

**Filed:** 2026-09-13
**Branch:** `k3d-manager-v1.33.0`
**Status:** OPEN

---

## Problem

`hub_recovery_reconcile` step 3 (`scripts/plugins/hub_recovery.sh:175`) registers the hub as its own app cluster: `ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc`. That registration is intended.

`register_app_cluster` (`scripts/plugins/argocd.sh`) always renders three labels on the cluster Secret:

```yaml
    environment: "${app_cluster_environment}"     # "infra" for in-cluster
    argocd-chart-version: "${ARGOCD_CHART_VERSION}" # default 7.8.1
    argocd-replicas: "2"
```

The `platform-helm` ApplicationSet (`scripts/etc/argocd/applicationsets/platform-helm.yaml`) selects clusters with `environment In [dev, infra, prod]`. It installs the `argo-cd` chart at `argocd-chart-version` into namespace `cicd` of the selected cluster. For the in-cluster Secret, that cluster is the hub itself.

On 2026-09-13 at 13:39Z, a reconcile run generated `ubuntu-k3s-platform`. That Application installed ArgoCD v2.14.2 (release `argocd-ubuntu-k3s`) into hub `cicd`, alongside the real v3.5.2 release. The second install took over the shared ConfigMaps, `argocd-secret`, ServiceAccounts and the Argo CRDs. It downgraded the CRDs, wiped `argocd-rbac-cm` policy, and pointed `argocd-cmd-params-cm` at the second install's repo-server and redis.

The hub already runs ArgoCD, so an in-cluster registration must never match `platform-helm`. Remote registrations (a real app cluster) keep the current labels.

## Fix

### Before You Start

- `git pull origin k3d-manager-v1.33.0`; read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- Read `scripts/plugins/argocd.sh` `register_app_cluster` in full (starts around line 1322).
- Read `scripts/etc/argocd/applicationsets/platform-helm.yaml`.
- Read the existing test `register_app_cluster: permits token-less in-cluster registration` in `scripts/tests/plugins/argocd.bats` (around line 263). The new tests follow its stub pattern.

### S1 — compute the platform labels only for remote clusters

In `register_app_cluster`, replace:

```bash
  local app_cluster_environment="${ARGOCD_APP_CLUSTER_ENVIRONMENT:-dev}"
  if [[ "${ARGOCD_APP_CLUSTER_SERVER}" == "https://kubernetes.default.svc" ]]; then
    app_cluster_environment="${ARGOCD_APP_CLUSTER_ENVIRONMENT:-infra}"
  fi
```

with:

```bash
  local _platform_labels=""
  if (( ! _in_cluster )); then
    printf -v _platform_labels '    environment: "%s"\n    argocd-chart-version: "%s"\n    argocd-replicas: "2"\n' \
      "${ARGOCD_APP_CLUSTER_ENVIRONMENT:-dev}" "${ARGOCD_CHART_VERSION}"
  fi
```

### S2 — heredoc uses the computed block

In the Secret heredoc, replace these three lines:

```yaml
    environment: "${app_cluster_environment}"
    argocd-chart-version: "${ARGOCD_CHART_VERSION}"
    argocd-replicas: "2"
    k3d-manager/managed: "${_managed}"
```

with:

```yaml
${_platform_labels}    k3d-manager/managed: "${_managed}"
```

`_platform_labels` ends with a newline when non-empty, so the remote render is unchanged byte-for-byte. When it is empty, the line starts directly with the 4-space indent of `k3d-manager/managed`.

No other lines change. Do not rename or remove `ARGOCD_APP_CLUSTER_ENVIRONMENT`.

### Tests — `scripts/tests/plugins/argocd.bats`

Add two tests immediately after `register_app_cluster: permits token-less in-cluster registration`, using the same `_kubectl` / `_argocd_set_active_app_cluster` stubs that copy the rendered file.

1. **`register_app_cluster: in-cluster secret does not match platform-helm`**: run with `ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc`, token unset, and `ARGOCD_APP_CLUSTER_ENVIRONMENT=infra` exported. Assert:
   - status 0
   - `grep -c '^    environment:'` on the rendered file outputs `0`
   - `grep -c 'argocd-chart-version'` outputs `0`
   - `grep -c 'argocd-replicas'` outputs `0`
   - `grep -c '^    k3d-manager/managed:'` outputs `1`
   - `grep -c 'argocd.argoproj.io/secret-type: cluster'` outputs `1`
   - `python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$RENDERED_FILE"` exits 0, if `python3` has `yaml`; otherwise skip that assertion with `command -v`/import guard, not by deleting it.
2. **`register_app_cluster: remote secret keeps platform-helm labels`**: run with `ARGOCD_APP_CLUSTER_SERVER=https://remote.example.invalid`, `ARGOCD_APP_CLUSTER_TOKEN=dummy-token`, `ARGOCD_CHART_VERSION=9.9.9`, and `ARGOCD_APP_CLUSTER_ENVIRONMENT` unset. Assert:
   - status 0
   - `grep -c '^    environment: "dev"'` outputs `1`
   - `grep -c '^    argocd-chart-version: "9.9.9"'` outputs `1`
   - `grep -c '^    argocd-replicas: "2"'` outputs `1`
   - `grep -c '^    k3d-manager/managed:'` outputs `1`

Do not print the rendered file in test output: the remote render contains the dummy bearer token.

## Operational warning (for the operator, not for Codex)

Once this lands, the next `hub_recovery_reconcile` client-side apply removes the three labels from the live `cicd/ubuntu-k3s-app-cluster` Secret. `platform-helm` then deletes `ubuntu-k3s-platform`. If that Application still carries `resources-finalizer.argocd.argoproj.io`, the deletion cascades. It would remove `argocd-cm`, `argocd-secret` and the Argo CRDs, and with them every Application.

Run the hub remediation runbook first: strip the finalizer, drop the labels, remove `argocd-ubuntu-k3s-*`, and restore the v3.5.2 CRDs and ConfigMaps. Only then run a reconcile with this fix.

## Definition of Done

- [ ] S1-S2 implemented exactly; only `scripts/plugins/argocd.sh`, `scripts/tests/plugins/argocd.bats` and `CHANGELOG.md` changed
- [ ] `grep -c 'app_cluster_environment' scripts/plugins/argocd.sh` outputs `0`
- [ ] `shellcheck -x scripts/plugins/argocd.sh`: no new warnings; compare `shellcheck -f gcc scripts/plugins/argocd.sh | wc -l` before and after the change and paste both counts
- [ ] `bats scripts/tests/plugins/argocd.bats` green; paste the summary line
- [ ] CHANGELOG `## [Unreleased]` → `### Fixed`: "`register_app_cluster` no longer labels in-cluster registrations for `platform-helm`, which had installed a second ArgoCD into the hub `cicd` namespace"
- [ ] Commit message verbatim: `fix(argocd): in-cluster app-cluster registration no longer matches platform-helm`
- [ ] Pushed to `origin/k3d-manager-v1.33.0`; `git rev-parse origin/k3d-manager-v1.33.0` equals the commit SHA; report the SHA

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, or use `--no-verify`
- Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, `scripts/plugins/hub_recovery.sh`, `platform-helm.yaml`, or any file outside the targets
- Do NOT run `hub_recovery_reconcile`, `register_app_cluster`, `kubectl` or anything else against a live cluster
- Do NOT assert with `grep -F` on whole source lines
