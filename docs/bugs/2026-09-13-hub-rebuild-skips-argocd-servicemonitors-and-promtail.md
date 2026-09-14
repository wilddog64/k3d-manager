# Bug: a fresh hub never gets ArgoCD ServiceMonitors or promtail

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-13
**Status:** FIXED `42c8723d` (Codex; Claude verified + committed) — operator: `make observability`
**Files:** `scripts/plugins/observability.sh`, `scripts/tests/plugins/observability_hub_ordering.bats` (new), `CHANGELOG.md`

## Problem

After the 2026-09-10 hub rebuild, the Grafana "ArgoCD / Image Updater" dashboard showed "No data" for every `argocd_*` panel and every Loki panel.

**1. ArgoCD ServiceMonitors were never created.**
- `bin/cluster-up` runs `deploy_argocd` at Step 3.6.
- `deploy_argocd` calls `_argocd_ensure_servicemonitors`, which returns early when `servicemonitors.monitoring.coreos.com` is absent. That is always the case on a fresh hub.
- kube-prometheus-stack, which owns that CRD, is installed later by ArgoCD itself, via the `observability` ApplicationSet applied in `deploy_argocd_bootstrap`.
- Live evidence: ArgoCD Helm rev 3 was deployed at 2026-09-10T23:57:36Z; the CRD was created at 23:58:39Z. `serviceMonitor.enabled: true` was set for all four components, yet zero ServiceMonitors existed in `cicd`.
- Nothing re-runs the ensure step once the CRD exists.

**2. `deploy_observability` did not complete on the hub.**
- `bin/cluster-up` never calls it; it is a manual `make observability` step.
- Its idempotent, credential-free steps come last: the ArgoCD dashboard and `_deploy_promtail_acg`. Before them run Vault reads and `_kubectl` calls without `--no-exit`, any of which aborts the function.
- Live evidence (2026-09-13), all absent on the hub:
  - promtail DaemonSet;
  - `monitoring/shopping-cart-apps` PrometheusRule;
  - Istio Gateway/VirtualServices in `monitoring`;
  - `monitoring/alertmanager-smtp-secret`.
- As a result, Loki received no logs.

## Fix

### S1 — `scripts/plugins/observability.sh`: ensure ArgoCD ServiceMonitors from the live release

Add a helper after `_observability_apply_argocd_dashboard`. It renders from the **live** release values, so it needs neither `argocd.sh` (the dispatcher lazy-loads only this plugin) nor the LDAP envsubst values file:

```bash
function _observability_ensure_argocd_servicemonitors() {
  local _ctx="${1:-k3d-k3d-cluster}"
  local _ns="${ARGOCD_NAMESPACE:-cicd}"
  local _release="${ARGOCD_HELM_RELEASE:-argocd}"
  local _chart_ref="${ARGOCD_HELM_CHART_REF:-argo/argo-cd}"
  local _waited=0 _timeout="${OBSERVABILITY_CRD_WAIT_SECONDS:-300}"
  while ! _kubectl --no-exit --context "${_ctx}" get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; do
    if (( _waited >= _timeout )); then
      _warn "[observability] ServiceMonitor CRD not present after ${_timeout}s; ArgoCD ServiceMonitors NOT ensured"
      return 0
    fi
    sleep 10
    _waited=$((_waited + 10))
  done

  local _chart_version _values _rendered
  _chart_version="$(_helm --kube-context "${_ctx}" -n "${_ns}" list --filter "^${_release}\$" -o json 2>/dev/null \
    | jq -r '.[0].chart // "" | sub("^argo-cd-"; "")')"
  if [[ -z "${_chart_version}" ]]; then
    _warn "[observability] ArgoCD release ${_ns}/${_release} not found; skipping ServiceMonitor ensure"
    return 0
  fi
  _values="$(mktemp)"
  if ! _helm --kube-context "${_ctx}" -n "${_ns}" get values "${_release}" -o yaml > "${_values}" 2>/dev/null; then
    rm -f "${_values}"
    _warn "[observability] could not read ArgoCD release values; skipping ServiceMonitor ensure"
    return 0
  fi
  _rendered="$(_helm template "${_release}" "${_chart_ref}" -n "${_ns}" --version "${_chart_version}" \
    -f "${_values}" --api-versions monitoring.coreos.com/v1 \
    | yq eval-all 'select(.kind == "ServiceMonitor")' -)"
  rm -f "${_values}"
  if [[ -z "${_rendered}" ]]; then
    _info "[observability] No ArgoCD ServiceMonitors rendered; skipping apply"
    return 0
  fi
  printf '%s\n' "${_rendered}" | _kubectl --context "${_ctx}" apply -f - >/dev/null \
    && _info "[observability] ArgoCD ServiceMonitors ensured on ${_ctx}"
}
```

- The values file holds release values (possibly credentials). It lives only in `mktemp` and is removed on every path.
- Use `kubectl apply`, not `helm upgrade`. `helm upgrade` conflicts under server-side apply with other field managers on `argocd-cm`/`argocd-secret`; see `docs/issues/2026-06-29-argocd-helm-ssa-conflict-sso-cm.md` and the live failure below.

### S2 — `deploy_observability`: run credential-free steps before the Vault-dependent ones

In `deploy_observability`, immediately after the `grafana-dashboards-hub` ApplicationSet `if … fi` block, insert:

```bash
  _observability_apply_argocd_dashboard "${_hub_context}"
  _deploy_promtail_acg "${_hub_context}"
  _observability_ensure_argocd_servicemonitors "${_hub_context}"
```

Then delete the two original trailing lines (`_observability_apply_argocd_dashboard "${_hub_context}"` and `_deploy_promtail_acg "${_hub_context}"`) at the end of the function. Change nothing else in `deploy_observability`.

### S3 — tests: `scripts/tests/plugins/observability_hub_ordering.bats` (new)

Stub `_kubectl`, `_helm`, `yq`, `jq`, `sleep`, `_info` and `_warn`, logging calls to `$BATS_TEST_TMPDIR`.

1. **CRD present:** helm list returns `[{"chart":"argo-cd-10.8.4"}]` and template returns one ServiceMonitor plus one ConfigMap.
   - Assert the helm template call has `--version 10.8.4` and `--api-versions monitoring.coreos.com/v1`.
   - Assert kubectl `apply` receives the ServiceMonitor, not the ConfigMap.
   - Assert no `upgrade` call to helm.
2. **CRD never appears:** set `OBSERVABILITY_CRD_WAIT_SECONDS=20`.
   - Status 0; output contains `NOT ensured`; no `template` call to helm.
3. **Release missing:** helm list returns `[]`.
   - Status 0; output contains `not found`; no `apply`.
4. **Ordering:** extract the `deploy_observability` body with `sed`.
   - Assert the line number of `_deploy_promtail_acg` is less than the line number of `Reading Alertmanager credentials`.
   - Assert `_deploy_promtail_acg` appears exactly once in the body.

Assert tokens; never `grep -F` a whole source line.

## CHANGELOG

Under `## [Unreleased]` → `### Fixed`:

```
- `deploy_observability` now creates the ArgoCD ServiceMonitors from the live Helm release once the ServiceMonitor CRD exists, and applies promtail and the ArgoCD dashboard before any Vault-dependent step; on a fresh hub the CRD arrives after `deploy_argocd`, so ArgoCD metrics were never scraped and Loki received no logs
```

## Definition of Done

- [ ] S1–S3 applied; no other lines in `observability.sh` changed.
- [ ] `shellcheck -x scripts/plugins/observability.sh`: no new warnings (paste before/after counts).
- [ ] `bats scripts/tests/plugins/observability_hub_ordering.bats scripts/tests/plugins/observability_no_exit_remove.bats scripts/tests/plugins/argocd_servicemonitors_ensure.bats`: all pass (paste the summary).
- [ ] Commit message, verbatim: `fix(observability): ensure ArgoCD ServiceMonitors and promtail on a fresh hub`
- [ ] Pushed; `git rev-parse origin/k3d-manager-v1.34.0` equals the commit SHA.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT run `helm`, `kubectl`, `vault` or any `k3d-manager` command against a live cluster. Use stubs only.
- Do NOT `helm upgrade` ArgoCD in the new helper.
- Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, `scripts/plugins/argocd.sh`, `bin/cluster-up` or memory-bank.

## Live stopgap applied 2026-09-13 (operator go)

- **ArgoCD ServiceMonitors:** `helm upgrade argocd argo/argo-cd --version 10.8.4 --reuse-values` created all four, and Prometheus targets are `up` (`count(argocd_app_info)` = 37).
  - The release itself is marked **failed (rev 4)**. Rev 3 stays `deployed`, and workloads were untouched.
  - The failure is an SSA conflict: field manager `argocd-controller` owns `app.kubernetes.io/instance`, `app.kubernetes.io/version` and `helm.sh/chart` labels on the `argocd-*` ConfigMaps/Secrets.
- **promtail:** `kubectl apply -f scripts/etc/observability/promtail.yaml`. DaemonSet 4/4, and Loki now lists namespaces `cicd`, `monitoring`, `shopping-cart-apps` and others.

## Related findings (not in this fix)

- **Hub registered as its own app cluster.**
  - Cluster Secret `cicd/ubuntu-k3s-app-cluster` (created 2026-09-11T02:29Z) points at `https://kubernetes.default.svc`, i.e. the hub.
  - While it matched the `platform-helm` ApplicationSet, app `ubuntu-k3s-platform` rendered `argo-cd-7.8.1` (`instance argocd-ubuntu-k3s`, `v2.14.2`) into the hub's `cicd` namespace. It rewrote the labels on the hub's own `argocd-cm`/`argocd-secret` at 2026-09-13T13:45Z. That is why the Helm upgrade now conflicts.
  - Today the Secret has no `environment` label, so no app is generated. Deleting or relabelling the Secret and cleaning the stale labels needs its own spec and an operator go.
- **Other hub pieces missing because `deploy_observability` never completed:** `shopping-cart-apps` PrometheusRule, Istio Gateway/VirtualServices in `monitoring`, and `alertmanager-smtp-secret`. The operator runs `make observability` after reviewing (it reads the Vault root token).
- **Duplicate series on the "Image Updater Ready/Desired Replicas" stats:** kube-state-metrics restarts give each new pod IP its own series. Wrap both expressions in `max(...)` in `grafana-dashboard-argocd.yaml`.
