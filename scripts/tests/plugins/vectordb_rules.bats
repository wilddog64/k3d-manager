#!/usr/bin/env bats

RULES="${BATS_TEST_DIRNAME}/../../etc/prometheus/rules/vectordb.yaml"
DASHBOARD="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-vectordb.yaml"
OLD_DASHBOARD="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/k3dm-vectordb-configmap.yaml"

@test "vectordb rules target the hub prometheus stack" {
  run grep -F -- 'release: kube-prometheus-stack' "${RULES}"
  [ "${status}" -eq 0 ]
}

@test "both vectordb alerts are present" {
  local _alert
  for _alert in VectorDBMetricsStale VectorDBIndexStale VectorDBIndexDrift VectorDBIndexFailing; do
    run grep -F -- "alert: ${_alert}" "${RULES}"
    [ "${status}" -eq 0 ]
  done
}

@test "automatic indexing alerts use the requested windows" {
  run grep -A4 -F -- 'alert: VectorDBIndexDrift' "${RULES}"
  [[ "${output}" == *"for: 2h"* ]]
  run grep -A4 -F -- 'alert: VectorDBIndexFailing' "${RULES}"
  [[ "${output}" == *"for: 30m"* ]]
}

@test "VectorDBMetricsStale watches push age, not absence alone" {
  run grep -F -- 'push_time_seconds{job="k3dm-vectordb"}' "${RULES}"
  [ "${status}" -eq 0 ]
  run grep -F -- '> 3600' "${RULES}"
  [ "${status}" -eq 0 ]
}

@test "VectorDBMetricsStale still covers the never-published case" {
  run grep -F -- 'absent(k3dm_vectordb_last_index_timestamp_seconds)' "${RULES}"
  [ "${status}" -eq 0 ]
}

@test "absence alone is not the whole staleness expression" {
  local _expr
  _expr="$(python3 -c '
import sys, yaml
with open(sys.argv[1]) as handle:
    document = yaml.safe_load(handle)
for group in document["spec"]["groups"]:
    for rule in group["rules"]:
        if rule.get("alert") == "VectorDBMetricsStale":
            print(" ".join(rule["expr"].split()))
' "${RULES}")"

  if [ "${_expr}" = 'absent(k3dm_vectordb_last_index_timestamp_seconds)' ]; then
    printf 'VectorDBMetricsStale is absent() alone.\n' >&2
    printf 'Pushgateway retains gauges after a publisher stops, so absent() can\n' >&2
    printf 'never go true once one publish has happened — the alert becomes dead.\n' >&2
    printf 'Compare the push time against now instead.\n' >&2
    return 1
  fi

  case "${_expr}" in
    *push_time_seconds*) ;;
    *) printf 'VectorDBMetricsStale does not reference push_time_seconds: %s\n' "${_expr}" >&2
       return 1 ;;
  esac
}

@test "VectorDBIndexStale keeps the seven-day index threshold" {
  run grep -F -- '7 * 86400' "${RULES}"
  [ "${status}" -eq 0 ]
}

@test "dashboard has six ingestion panels using emitted metrics" {
  run python3 -c '
import json, re, sys
text = open(sys.argv[1]).read()
payload = text.split("k3dm-vectordb.json: |", 1)[1]
dashboard = json.loads(payload)
panels = dashboard["panels"]
row = next(panel for panel in panels if panel.get("title") == "Ingestion")
assert row.get("collapsed") is False and row.get("panels") == [], "an expanded row must not nest its panels"
below = [p for p in panels if p is not row and p["gridPos"]["y"] > row["gridPos"]["y"]]
assert len(below) == 6, len(below)
assert all(p.get("gridPos") for p in panels)
for stat in (p for p in below if p["type"] == "stat"):
    assert all(target.get("instant") is True for target in stat["targets"]), stat["title"]
queries = " ".join(target["expr"] for panel in below for target in panel["targets"])
metrics = open("bin/k3dm-hermes").read()
for name in re.findall(r"k3dm_vectordb_[a-z_]+", queries):
    assert name in metrics or name == "k3dm_vectordb_drift_docs", name
' "${DASHBOARD}"
  [ "${status}" -eq 0 ]
}

@test "vectordb dashboard is no longer in the app-cluster dashboard folder" {
  [ ! -e "${OLD_DASHBOARD}" ]
}

@test "every rule keeps string labels and its own annotations" {
  run python3 -c '
import sys, yaml
document = yaml.safe_load(open(sys.argv[1]))
for group in document["spec"]["groups"]:
    for rule in group["rules"]:
        labels = rule.get("labels", {})
        assert all(isinstance(v, str) for v in labels.values()), (rule["alert"], labels)
        assert "annotations" not in labels, rule["alert"]
        assert rule.get("annotations", {}).get("summary"), rule["alert"]
' "${RULES}"
  [ "${status}" -eq 0 ]
}
