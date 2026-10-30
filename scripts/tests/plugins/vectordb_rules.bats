#!/usr/bin/env bats

RULES="${BATS_TEST_DIRNAME}/../../etc/prometheus/rules/vectordb.yaml"
DASHBOARD="${DASHBOARD:-${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-vectordb.yaml}"
OLD_DASHBOARD="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/k3dm-vectordb-configmap.yaml"

@test "vectordb rules target the hub prometheus stack" {
  run grep -F -- 'release: kube-prometheus-stack' "${RULES}"
  [ "${status}" -eq 0 ]
}

@test "vectordb alerts are present" {
  local _alert
  for _alert in VectorDBMetricsStale VectorDBIndexStale VectorDBIndexDrift VectorDBIndexFailing \
    VectorDBRetrievalRecallBelowFloor VectorDBRetrievalReturnsOutdatedDocs VectorDBRetrievalProbeStale; do
    run grep -F -- "alert: ${_alert}" "${RULES}"
    [ "${status}" -eq 0 ]
  done
}

@test "automatic indexing alerts use the requested windows" {
  run grep -A4 -F -- 'alert: VectorDBIndexDrift' "${RULES}"
  [[ "${output}" == *"oldest_drift_age_seconds"* ]]
  run grep -A5 -F -- 'alert: VectorDBIndexDrift' "${RULES}"
  [[ "${output}" != *"for:"* ]]
  run grep -A4 -F -- 'alert: VectorDBIndexFailing' "${RULES}"
  [[ "${output}" == *"for: 30m"* ]]
}

@test "drift alert uses kind counts and first-seen age" {
  run python3 -c '
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
rule = next(r for g in doc["spec"]["groups"] for r in g["rules"] if r.get("alert") == "VectorDBIndexDrift")
expr = " ".join(rule["expr"].split())
assert "sum(k3dm_vectordb_drift_docs_by_kind) > 0" in expr, expr
assert "max(k3dm_vectordb_oldest_drift_age_seconds) > 7200" in expr, expr
assert "k3dm_vectordb_drift_docs != 0" not in expr, expr
assert "for" not in rule, rule
' "${RULES}"
  [ "${status}" -eq 0 ]
}

@test "drift dashboard panels show kind counts and oldest age without overlaps" {
  run python3 -c '
import json, sys
doc = json.loads(open(sys.argv[1]).read().split("k3dm-vectordb.json: |", 1)[1])
panels = doc["panels"]
by_id = {p["id"]: p for p in panels}
assert len(by_id) == len(panels), "duplicate panel ids"
p2, p5 = by_id[2], by_id[5]
assert p2["targets"][0]["expr"] == "k3dm_vectordb_drift_docs_by_kind"
assert p2["gridPos"] == {"x": 12, "y": 10, "w": 8, "h": 8}
assert p5["targets"][0]["expr"] == "max(k3dm_vectordb_oldest_drift_age_seconds)"
assert p5["fieldConfig"]["defaults"]["unit"] == "s"
assert p5["gridPos"] == {"x": 20, "y": 10, "w": 4, "h": 8}
for i, a in enumerate(panels):
  ga = a["gridPos"]
  for b in panels[i + 1:]:
    gb = b["gridPos"]
    overlap = ga["x"] < gb["x"] + gb["w"] and gb["x"] < ga["x"] + ga["w"] and ga["y"] < gb["y"] + gb["h"] and gb["y"] < ga["y"] + ga["h"]
    assert not overlap, (a["id"], b["id"])
' "${DASHBOARD}"
  [ "${status}" -eq 0 ]
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
assert {p["id"] for p in below} == {11, 12, 16, 13, 15}
assert all(p.get("gridPos") for p in panels)
for stat in (p for p in below if p["type"] == "stat"):
    assert all(target.get("instant") is True for target in stat["targets"]), stat["title"]
queries = " ".join(target["expr"] for panel in below for target in panel["targets"])
metrics = open("bin/k3dm-hermes").read() + open("scripts/lib/hermes/retrieval_eval.py").read()
for name in re.findall(r"k3dm_vectordb_[a-z_]+", queries):
    assert name in metrics or name == "k3dm_vectordb_drift_docs", name
' "${DASHBOARD}"
  [ "${status}" -eq 0 ]
}

@test "rows and corpus panel formats document counts as whole documents" {
  run python3 -c '
import json, sys
text = open(sys.argv[1]).read()
dashboard = json.loads(text.split("k3dm-vectordb.json: |", 1)[1])
panel = next(panel for panel in dashboard["panels"] if panel.get("id") == 1)
defaults = panel["fieldConfig"]["defaults"]
assert defaults.get("unit") == "none", defaults
assert defaults.get("decimals") == 0, defaults
assert all(target["expr"] in {"k3dm_vectordb_rows", "k3dm_vectordb_corpus_docs"} for target in panel["targets"])
assert len(panel["targets"]) == 2
' "${DASHBOARD}"
  [ "${status}" -eq 0 ]
}

@test "rows and corpus remain distinguishable when their values overlap" {
  run python3 -c '
import json, sys
text = open(sys.argv[1]).read()
dashboard = json.loads(text.split("k3dm-vectordb.json: |", 1)[1])
panel = next(panel for panel in dashboard["panels"] if panel.get("id") == 1)
styles = {}
for override in panel.get("fieldConfig", {}).get("overrides", []):
    name = override.get("matcher", {}).get("options")
    styles[name] = {prop["id"]: prop.get("value") for prop in override.get("properties", [])}
rows = styles.get("rows (last published)", {})
corpus = styles.get("corpus docs (last published)", {})
assert rows.get("color") == {"mode": "fixed", "fixedColor": "green"}, rows
assert rows.get("custom.drawStyle") == "line", rows
assert rows.get("custom.lineWidth") == 3, rows
assert rows.get("custom.showPoints") == "never", rows
assert corpus.get("color") == {"mode": "fixed", "fixedColor": "yellow"}, corpus
assert corpus.get("custom.drawStyle") == "points", corpus
assert corpus.get("custom.showPoints") == "always", corpus
assert corpus.get("custom.pointSize") == 4, corpus
assert corpus.get("custom.lineWidth") == 0, corpus
assert panel.get("options", {}).get("tooltip", {}).get("mode") == "multi", panel.get("options")
assert panel.get("options", {}).get("legend", {}).get("showLegend") is True, panel.get("options")
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

@test "dashboard has four ordered rows and unique panel ids" {
  run python3 -c '
import json, sys
d = json.loads(open(sys.argv[1]).read().split("k3dm-vectordb.json: |", 1)[1])
p = d["panels"]
rows = [x for x in p if x["type"] == "row"]
assert [x["title"] for x in rows] == ["Infrastructure health — is pgvector available and accepting queries?", "Data consistency — are indexed documents synchronized with the repository?", "Retrieval quality — do agents retrieve the correct, current documents?", "Ingestion"]
by = {x["id"]: x for x in p}
assert len(by) == len(p)
assert all(by[i].get("description") for i in (20, 21, 22, 23))
for i, a in enumerate(p):
  ga = a["gridPos"]
  for b in p[i + 1:]:
    gb = b["gridPos"]
    assert not (ga["x"] < gb["x"] + gb["w"] and gb["x"] < ga["x"] + ga["w"] and ga["y"] < gb["y"] + gb["h"] and gb["y"] < ga["y"] + ga["h"]), (a["id"], b["id"])
' "${DASHBOARD}"
  [ "${status}" -eq 0 ]
}

@test "retrieval alerts use the specified expressions and windows" {
  run python3 -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
r = {x["alert"]: x for g in d["spec"]["groups"] for x in g["rules"]}
expected = {"VectorDBRetrievalRecallBelowFloor": ("k3dm_vectordb_retrieval_recall_at5 < on(directory) k3dm_vectordb_retrieval_recall_floor", "1h"), "VectorDBRetrievalReturnsOutdatedDocs": ("(k3dm_vectordb_retrieval_stale_hits + k3dm_vectordb_retrieval_deleted_hits) > 0", "1h"), "VectorDBRetrievalProbeStale": ("time() - k3dm_vectordb_retrieval_probe_last_success_timestamp_seconds > 172800", "30m")}
for name, (expr, window) in expected.items():
  assert r[name]["expr"] == expr and r[name]["for"] == window, r[name]
  assert r[name]["labels"] == {"severity": "warning", "cluster": "hub"}
  assert "K3DM_RETRIEVAL_EVAL_LIVE=1 pytest scripts/tests/bin/test_find_similar_docs.py -k live" in r[name]["annotations"]["description"]
assert "make index-docs DRY_RUN=1" in r["VectorDBRetrievalReturnsOutdatedDocs"]["annotations"]["description"]
' "${RULES}"
  [ "${status}" -eq 0 ]
}

@test "retrieval probe age panel keeps a daily probe green and matches the stale alert boundary" {
  run python3 -c '
import json, sys, yaml
text = open(sys.argv[1]).read()
dashboard = json.loads(text.split("k3dm-vectordb.json: |", 1)[1])
panel = next(p for p in dashboard["panels"] if p["id"] == 23)
defaults = panel["fieldConfig"]["defaults"]
steps = defaults["thresholds"]["steps"]
assert defaults["thresholds"]["mode"] == "absolute", defaults["thresholds"]
assert steps == [
    {"color": "green", "value": None},
    {"color": "yellow", "value": 86400},
    {"color": "red", "value": 172800},
], steps
assert defaults["unit"] == "s", defaults
assert panel["targets"][0]["expr"] == "time() - k3dm_vectordb_retrieval_probe_last_success_timestamp_seconds"
assert panel["options"]["colorMode"] == "background"
assert 3.25 * 3600 < 86400 < 172800
rules = yaml.safe_load(open(sys.argv[2]))
rule = next(r for g in rules["spec"]["groups"] for r in g["rules"] if r.get("alert") == "VectorDBRetrievalProbeStale")
assert rule["expr"] == "time() - k3dm_vectordb_retrieval_probe_last_success_timestamp_seconds > 172800", rule
assert rule["for"] == "30m", rule
' "${DASHBOARD}" "${RULES}"
  [ "${status}" -eq 0 ]
}

@test "existing dashboard panel queries and presentation are unchanged" {
  run python3 -c '
import hashlib, json, sys
d = json.loads(open(sys.argv[1]).read().split("k3dm-vectordb.json: |", 1)[1])
expected = {1:"7f6ea5cb20329d56bb522cd5219f4e606e011b9fbc6eb7d940fa309e719c70f7", 2:"0c93c17f4c3fa87d86a63864db7f2798311c19097530ef7a6a1bad5c658d53e5", 3:"e4c7b45ffaf97d1f08c4b50fed271b9b9ba7f9f3a977de39b61266d7dbe6e1e4", 4:"5a7f0363b16d68abee61b324d884c110bbfcfc95336b4a5c49302ca7d62ced1c", 5:"8ddb381ddcc5c8efd42abc902e24d1331cf54410eb34799eec59aff19d13030c", 10:"689bec316858eaefeab9f16224fa64747893ae45b7468d11a1cb95b53a5c2b0b", 11:"bbfece3dcb2f7b405102897d33adbedd982205dc37b1e285ee7b0ff7e2bde64c", 12:"a49266f4cd87b889fb474aa6bb11bdcf9e91b5c239a85fe7314c910c0b4849d9", 13:"6ccef05b3eef9dd87baa50684e08191ae447eb366e42a7f48e34297906d446a8", 14:"e4bee98f895f14d73d11803cfa404346ef538a4059b8ed9174d2e01b60f25cc3", 15:"6dff8369e533917c2ba866634b173875e0fba760a7e13fc885dc975708ab3c86", 16:"afb10cd117b5f00e095383e82df2dc463dab5843f7637881a68bf00e907f0aca"}
panels = {p["id"]: p for p in d["panels"]}
for ident, digest in expected.items():
  fields = {key: panels[ident].get(key) for key in ("targets", "fieldConfig", "options")}
  actual = hashlib.sha256(json.dumps(fields, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
  assert actual == digest, (ident, actual)
' "${DASHBOARD}"
  [ "${status}" -eq 0 ]
}
