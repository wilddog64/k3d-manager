#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2016

APPSET="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/observability-acg.yaml"
HUB_APPSET="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/observability.yaml"
VALUES="${BATS_TEST_DIRNAME}/../../etc/helm/observability/loki-values.yaml"
PROM_VALUES="${BATS_TEST_DIRNAME}/../../etc/helm/observability/kube-prometheus-stack-values.yaml"
PROMTAIL="${BATS_TEST_DIRNAME}/../../etc/observability/promtail.yaml"
PLUGIN="${BATS_TEST_DIRNAME}/../../plugins/observability.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../python_yaml.bash"

LOKI_CHART_FIXTURE="${BATS_TEST_DIRNAME}/../fixtures/helm/loki-18.2.0.tgz"
LOKI_CHART_SHA256="b68d1323113018dfabb7c8d9f86f14f37cdcd955a9f80c032ddd184cf1409ff2"

# Chart pulled 2026-11-10 by Claude on the M4: helm pull --repo https://grafana-community.github.io/helm-charts --version 18.2.0 loki
_ensure_loki_chart_18_2_0() {
  if ! command -v helm >/dev/null 2>&1; then
    skip "helm is missing: required to render loki chart"
  fi
  [ -f "${LOKI_CHART_FIXTURE}" ]
  local sum
  sum="$(shasum -a 256 "${LOKI_CHART_FIXTURE}" 2>/dev/null || sha256sum "${LOKI_CHART_FIXTURE}")"
  [ "${sum%% *}" = "${LOKI_CHART_SHA256}" ]
  LOKI_CHART="${LOKI_CHART_FIXTURE}"
}

@test "loki: observability-acg includes a loki application" {
  run grep -nF -- 'app: loki' "${APPSET}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'chart: loki' "${APPSET}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'grafana-community.github.io/helm-charts' "${APPSET}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'loki-values.yaml' "${APPSET}"
  [ "${status}" -eq 0 ]
}

@test "loki: hub observability includes a loki application" {
  run grep -nF -- 'name: hub-loki' "${HUB_APPSET}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'chart: loki' "${HUB_APPSET}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'grafana-community.github.io/helm-charts' "${HUB_APPSET}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'loki-values.yaml' "${HUB_APPSET}"
  [ "${status}" -eq 0 ]
}

@test "loki: hub observability forces the helm release name back to loki" {
  run grep -nF -- "releaseName: '{{if eq .name \"hub-loki\"}}loki{{else}}{{.name}}{{end}}'" "${HUB_APPSET}"
  [ "${status}" -eq 0 ]
}

@test "loki: values pin monolithic filesystem mode" {
  run grep -nF -- 'deploymentMode: Monolithic' "${VALUES}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'type: filesystem' "${VALUES}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'replication_factor: 1' "${VALUES}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'enabled: true' "${VALUES}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'storageClassName: local-path' "${VALUES}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'size: 10Gi' "${VALUES}"
  [ "${status}" -eq 0 ]
}

@test "loki: hub grafana provisions a loki datasource" {
  run grep -nF -- 'name: Loki' "${PROM_VALUES}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'uid: loki' "${PROM_VALUES}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'url: http://loki-gateway.monitoring.svc.cluster.local' "${PROM_VALUES}"
  [ "${status}" -eq 0 ]
}

@test "loki: promtail ships pod logs to Loki" {
  run grep -nF -- 'fluent/fluent-bit:3.1.9' "${PROMTAIL}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'Host          loki.monitoring.svc.cluster.local' "${PROMTAIL}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'fluent-bit.conf' "${PROMTAIL}"
  [ "${status}" -eq 0 ]
}

@test "loki: observability deploy applies promtail manifest" {
  run grep -nF -- '_deploy_promtail_acg' "${PLUGIN}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'Loki/Promtail log shipper applied' "${PLUGIN}"
  [ "${status}" -eq 0 ]
}

@test "loki: hub observability deploy applies the argocd image updater dashboard" {
  run grep -nF -- '_observability_apply_argocd_dashboard "${_hub_context}"' "${PLUGIN}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'ArgoCD/Image Updater dashboard applied on' "${PLUGIN}"
  [ "${status}" -eq 0 ]
}

@test "loki: values configure compactor retention and limits_config (M1, M2)" {
  run "$(k3dm_python_yaml)" - "${VALUES}" <<'PY'
import sys, yaml

values = yaml.safe_load(open(sys.argv[1]))
loki = values.get("loki") or {}
compactor = loki.get("compactor") or {}
assert compactor.get("retention_enabled") is True, f"retention_enabled not True: {compactor}"
assert compactor.get("delete_request_store") == "filesystem", f"delete_request_store not filesystem: {compactor}"

limits = loki.get("limits_config") or {}
assert limits.get("retention_period") == "336h", f"retention_period not 336h: {limits}"

expected_streams = {
    '{job="k3dm-dispatch-run"}': {"period": "720h", "priority": 1},
    '{namespace="trivy-system"}': {"period": "720h", "priority": 1},
    '{namespace="cicd"}': {"period": "720h", "priority": 1},
}
streams = limits.get("retention_stream") or []
stream_map = {s.get("selector"): s for s in streams}
for sel, exp in expected_streams.items():
    assert sel in stream_map, f"missing stream rule: {sel}"
    assert stream_map[sel].get("period") == exp["period"], f"{sel} period mismatch: {stream_map[sel]}"
    assert stream_map[sel].get("priority") == exp["priority"], f"{sel} priority mismatch: {stream_map[sel]}"
PY
  [ "${status}" -eq 0 ]
}

@test "loki: values never leave retention disabled or set retention_period to 0 (N2)" {
  run "$(k3dm_python_yaml)" - "${VALUES}" <<'PY'
import sys, yaml

values = yaml.safe_load(open(sys.argv[1]))
loki = values.get("loki") or {}
compactor = loki.get("compactor") or {}
retention_enabled = compactor.get("retention_enabled")
assert retention_enabled is True, f"N2 violation: retention is disabled or not set (got {retention_enabled})"

limits = loki.get("limits_config") or {}
period = str(limits.get("retention_period", "")).strip()
assert period and period not in ("0", "0s", "0h", "0m", "0d"), f"N2 violation: retention_period is 0 or unset (got '{period}')"
PY
  [ "${status}" -eq 0 ]
}

@test "loki: rendered config enables compactor retention with filesystem store and 14-day default (M1)" {
  local chart
  _ensure_loki_chart_18_2_0
  chart="${LOKI_CHART}"
  run helm template loki "${chart}" -s templates/config.yaml -f "${VALUES}"
  [ "${status}" -eq 0 ]
  local rendered="${output}"

  run "$(k3dm_python_yaml)" - "${rendered}" <<'PY'
import sys, yaml

docs = list(yaml.safe_load_all(sys.argv[1]))
cm = [d for d in docs if d and d.get("kind") == "ConfigMap" and d.get("metadata", {}).get("name") == "loki"][0]
cfg = yaml.safe_load(cm["data"]["config.yaml"])

compactor = cfg.get("compactor") or {}
assert compactor.get("retention_enabled") is True, f"M1: compactor.retention_enabled not True: {compactor}"
assert compactor.get("delete_request_store") == "filesystem", f"M1: delete_request_store not filesystem: {compactor}"

limits = cfg.get("limits_config") or {}
assert limits.get("retention_period") == "336h", f"M1: limits_config.retention_period not 336h: {limits}"
PY
  [ "${status}" -eq 0 ]
}

@test "loki: rendered config keeps 30-day retention for dashboard streams (M2)" {
  local chart
  _ensure_loki_chart_18_2_0
  chart="${LOKI_CHART}"
  run helm template loki "${chart}" -s templates/config.yaml -f "${VALUES}"
  [ "${status}" -eq 0 ]
  local rendered="${output}"

  run "$(k3dm_python_yaml)" - "${rendered}" <<'PY'
import sys, yaml

docs = list(yaml.safe_load_all(sys.argv[1]))
cm = [d for d in docs if d and d.get("kind") == "ConfigMap" and d.get("metadata", {}).get("name") == "loki"][0]
cfg = yaml.safe_load(cm["data"]["config.yaml"])

limits = cfg.get("limits_config") or {}
streams = limits.get("retention_stream") or []

expected = {
    '{job="k3dm-dispatch-run"}': {"period": "720h", "priority": 1},
    '{namespace="trivy-system"}': {"period": "720h", "priority": 1},
    '{namespace="cicd"}': {"period": "720h", "priority": 1},
}

stream_map = {s.get("selector"): s for s in streams}
for sel, exp in expected.items():
    assert sel in stream_map, f"M2: missing retention_stream rule for {sel}"
    assert stream_map[sel].get("period") == exp["period"], f"M2: {sel} period mismatch: {stream_map[sel]}"
    assert stream_map[sel].get("priority") == exp["priority"], f"M2: {sel} priority mismatch: {stream_map[sel]}"
PY
  [ "${status}" -eq 0 ]
}

@test "loki: rendered config preserves chart limits_config defaults (M3)" {
  local chart
  _ensure_loki_chart_18_2_0
  chart="${LOKI_CHART}"
  run helm template loki "${chart}" -s templates/config.yaml -f "${VALUES}"
  [ "${status}" -eq 0 ]
  local rendered="${output}"

  run "$(k3dm_python_yaml)" - "${rendered}" <<'PY'
import sys, yaml

docs = list(yaml.safe_load_all(sys.argv[1]))
cm = [d for d in docs if d and d.get("kind") == "ConfigMap" and d.get("metadata", {}).get("name") == "loki"][0]
cfg = yaml.safe_load(cm["data"]["config.yaml"])

limits = cfg.get("limits_config") or {}
assert limits.get("reject_old_samples") is True, f"M3: reject_old_samples not True: {limits}"
assert limits.get("reject_old_samples_max_age") == "168h", f"M3: reject_old_samples_max_age not 168h: {limits}"
PY
  [ "${status}" -eq 0 ]
}

@test "loki: rendered config never enables retention without a delete_request_store (N1)" {
  local chart
  _ensure_loki_chart_18_2_0
  chart="${LOKI_CHART}"
  run helm template loki "${chart}" -s templates/config.yaml -f "${VALUES}"
  [ "${status}" -eq 0 ]
  local rendered="${output}"

  run "$(k3dm_python_yaml)" - "${rendered}" <<'PY'
import sys, yaml

docs = list(yaml.safe_load_all(sys.argv[1]))
cm = [d for d in docs if d and d.get("kind") == "ConfigMap" and d.get("metadata", {}).get("name") == "loki"][0]
cfg = yaml.safe_load(cm["data"]["config.yaml"])

compactor = cfg.get("compactor") or {}
retention_enabled = compactor.get("retention_enabled", False)
store = compactor.get("delete_request_store")

if retention_enabled and not store:
    sys.exit("N1 violation: retention_enabled is True but delete_request_store is not configured")

assert retention_enabled is True and store == "filesystem", (
    f"N1: expected retention_enabled True and delete_request_store filesystem, got retention={retention_enabled}, store={store}"
)
PY
  [ "${status}" -eq 0 ]
}

@test "loki: rendered config never leaves retention disabled or set retention_period to 0 (N2)" {
  local chart
  _ensure_loki_chart_18_2_0
  chart="${LOKI_CHART}"
  run helm template loki "${chart}" -s templates/config.yaml -f "${VALUES}"
  [ "${status}" -eq 0 ]
  local rendered="${output}"

  run "$(k3dm_python_yaml)" - "${rendered}" <<'PY'
import sys, yaml

docs = list(yaml.safe_load_all(sys.argv[1]))
cm = [d for d in docs if d and d.get("kind") == "ConfigMap" and d.get("metadata", {}).get("name") == "loki"][0]
cfg = yaml.safe_load(cm["data"]["config.yaml"])

compactor = cfg.get("compactor") or {}
retention_enabled = compactor.get("retention_enabled")
assert retention_enabled is True, f"N2 violation: rendered retention_enabled is not True: {compactor}"

limits = cfg.get("limits_config") or {}
period = str(limits.get("retention_period", "")).strip()
assert period and period not in ("0", "0s", "0h", "0m", "0d"), f"N2 violation: rendered retention_period is 0 or unset (got '{period}')"
PY
  [ "${status}" -eq 0 ]
}
