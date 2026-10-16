#!/usr/bin/env bats

EXPORTER="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml"
DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-e2e.yaml"
HERMES_DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-hermes.yaml"
RULE="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/prometheusrule.yaml"
ARGOCD="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
AM_TMPL="${BATS_TEST_DIRNAME}/../../etc/prometheus/alertmanager.yaml.tmpl"

@test "exporter declares the e2e reader and label selector" {
  run grep -F -- 'refresh_e2e_events' "${EXPORTER}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'k3dm.k3d.io%2Fe2e-result%3Dtrue' "${EXPORTER}"
  echo "$output"; [ "${status}" -eq 0 ]
  run grep -F -- 'refresh_e2e_events()' "${EXPORTER}"
  echo "$output"; [ "${status}" -eq 0 ]
}

@test "Hermes dashboard exposes current findings and history" {
  run grep -F -- 'hermes_sensor_status' "${HERMES_DASH}"
  echo "$output"; [ "${status}" -eq 0 ]
  run grep -F -- '"title": "Current Hermes findings"' "${HERMES_DASH}"
  echo "$output"; [ "${status}" -eq 0 ]
  run grep -F -- '"title": "Sensor status history"' "${HERMES_DASH}"
  echo "$output"; [ "${status}" -eq 0 ]
}

@test "Hermes dashboard exposes failure evidence and status meanings" {
  for field in 'failed_hosts' 'ci_run_url' 'Failed hosts' 'CI run' 'Open GitHub Actions run'; do
    run grep -F -- "${field}" "${HERMES_DASH}"
    echo "$output"; [ "${status}" -eq 0 ]
  done
  run grep -F -- '0 = healthy, 1 = degraded, 2 = unknown' "${HERMES_DASH}"
  echo "$output"; [ "${status}" -eq 0 ]
  run grep -F -- '{{sensor}} ({{status}}): {{evidence}}' "${HERMES_DASH}"
  echo "$output"; [ "${status}" -eq 0 ]
  run grep -F -- 'run_url' "${EXPORTER}"
  echo "$output"; [ "${status}" -eq 0 ]
}

@test "exporter emits all five e2e_* gauges" {
  for metric in e2e_run_info e2e_last_run_pass e2e_last_run_timestamp_seconds \
                e2e_last_run_duration_seconds e2e_last_success_timestamp_seconds; do
    run grep -F -- "${metric}{" "${EXPORTER}"
    echo "$output"; [ "${status}" -eq 0 ]
  done
}

@test "exporter emits grouped e2e failure metric and dashboard table" {
  run grep -F -- 'e2e_failure_group_info{' "${EXPORTER}"
  echo "$output"; [ "${status}" -eq 0 ]
  run grep -F -- '"title": "Failure groups"' "${DASH}"
  echo "$output"; [ "${status}" -eq 0 ]
}

@test "exporter emits test-level failure metric and dashboard table" {
  run grep -F -- 'e2e_failure_info{' "${EXPORTER}"
  echo "$output"; [ "${status}" -eq 0 ]
  run grep -F -- '"title": "Failure details"' "${DASH}"
  echo "$output"; [ "${status}" -eq 0 ]
}

@test "exporter normalizes nested JSON and skips invalid E2E payloads" {
  run python3 - "${EXPORTER}" <<'PY'
import sys, yaml
docs = list(yaml.safe_load_all(open(sys.argv[1])))
cm = next(d for d in docs if d and d.get("kind") == "ConfigMap"
          and d["metadata"]["name"] == "vulnerability-inventory-exporter")
src = cm["data"]["exporter.py"]
assert 'if isinstance(payload, str):' in src
assert 'if not payload.get("run_id"):' in src
assert 'continue' in src
print("ok")
PY
  echo "$output"; [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

@test "exporter labels e2e gauges with the runner dimension" {
  if ! command -v python3 >/dev/null 2>&1; then skip "python3 not installed"; fi
  run python3 - "${EXPORTER}" <<'PY'
import sys, yaml
docs = list(yaml.safe_load_all(open(sys.argv[1])))
cm = next(d for d in docs if d and d.get("kind") == "ConfigMap"
          and d["metadata"]["name"] == "vulnerability-inventory-exporter")
src = cm["data"]["exporter.py"]
# event carries a runner (defaulting to local-m4 for legacy events)
assert 'payload.get("runner") or "local-m4"' in src, "event runner default missing"
# runner is part of the per-run metric dimensions and the emitted label body
assert 'event["runner"]' in src, "runner not in metric dims"
assert 'runner="%s"' in src, "runner not in emitted label body"
# e2e_run_info info tuple includes runner
assert '"run_id", "tier", "runner", "service"' in src, "runner not in e2e_run_info"
print("ok")
PY
  echo "$output"; [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

@test "exporter synthesizes one failure group for a test-less failed run" {
  run python3 - "${EXPORTER}" <<'PY'
import ast, sys, yaml
docs = list(yaml.safe_load_all(open(sys.argv[1])))
cm = next(d for d in docs if d and d.get("kind") == "ConfigMap"
          and d["metadata"]["name"] == "vulnerability-inventory-exporter")
src = cm["data"]["exporter.py"]
tree = ast.parse(src)
node = next(n for n in tree.body
            if isinstance(n, ast.FunctionDef) and n.name == "e2e_failure_groups")
ns = {}
exec(compile(ast.Module(body=[node], type_ignores=[]), "exporter", "exec"), ns)
groups = ns["e2e_failure_groups"]
assert groups({"phase": "installing-argocd"}, False, "product-catalog") == [{
    "kind": "aborted at installing-argocd", "target": "installing-argocd",
    "service": "product-catalog", "count": 1,
}]
assert groups({}, False, "product-catalog")[0]["kind"] == "aborted at unknown"
assert groups({}, True, "product-catalog") == []
existing = [{"kind": "auth", "target": "api", "service": "basket", "count": 2}]
assert groups({"failure_groups": existing}, False, "product-catalog") is existing
assert groups({"failure_details": [{"file": "api/cart.spec.ts"}]}, False, "product-catalog") == []
print("ok")
PY
  echo "$output"; [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

@test "embedded exporter.py compiles cleanly" {
  if ! command -v python3 >/dev/null 2>&1; then skip "python3 not installed"; fi
  run python3 - "${EXPORTER}" <<'PY'
import sys, yaml, tempfile, py_compile, os
docs = list(yaml.safe_load_all(open(sys.argv[1])))
cm = next(d for d in docs if d and d.get("kind") == "ConfigMap"
          and d["metadata"]["name"] == "vulnerability-inventory-exporter")
src = cm["data"]["exporter.py"]
f = tempfile.NamedTemporaryFile("w", suffix=".py", delete=False); f.write(src); f.close()
try:
    py_compile.compile(f.name, doraise=True)
finally:
    os.unlink(f.name)
print("ok")
PY
  echo "$output"; [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

@test "exporter RBAC is not widened (still get,list on configmaps only)" {
  run python3 - "${EXPORTER}" <<'PY'
import sys, yaml
docs = list(yaml.safe_load_all(open(sys.argv[1])))
role = next(d for d in docs if d and d.get("kind") == "Role"
            and d["metadata"]["name"] == "vulnerability-inventory-exporter-events")
rules = role["rules"]
assert len(rules) == 1, rules
r = rules[0]
assert r["resources"] == ["configmaps"], r["resources"]
assert sorted(r["verbs"]) == ["get", "list"], r["verbs"]
print("ok")
PY
  echo "$output"; [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

@test "exporter maps UNKNOWN Trivy severity from CVSS score" {
  run python3 - "${EXPORTER}" <<'PY'
import sys, yaml
docs = list(yaml.safe_load_all(open(sys.argv[1])))
cm = next(d for d in docs if d and d.get("kind") == "ConfigMap"
          and d["metadata"]["name"] == "vulnerability-inventory-exporter")
src = cm["data"]["exporter.py"]
assert 'def severity_for(finding):' in src
assert 'if score >= 9.0:' in src
assert '"severity": severity_for(finding)' in src
print("ok")
PY
  echo "$output"; [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

@test "exporter preserves remediation cache when refresh fails" {
  run python3 - "${EXPORTER}" <<'PY'
import sys, yaml
docs = list(yaml.safe_load_all(open(sys.argv[1])))
cm = next(d for d in docs if d and d.get("kind") == "ConfigMap"
          and d["metadata"]["name"] == "vulnerability-inventory-exporter")
src = cm["data"]["exporter.py"]
start = src.index('def refresh_remediation_events():')
end = src.index('def refresh_e2e_events():', start)
block = src[start:end]
assert 'except Exception:\n        # Preserve the last successful cache' in block
assert 'remediation_state = []' not in block
print('ok')
PY
  echo "$output"; [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

@test "terminal remediation outcomes are excluded from current status" {
  run python3 - "${EXPORTER}" <<'PY'
import sys, yaml
docs = list(yaml.safe_load_all(open(sys.argv[1])))
cm = next(d for d in docs if d and d.get("kind") == "ConfigMap"
          and d["metadata"]["name"] == "vulnerability-inventory-exporter")
src = cm["data"]["exporter.py"]
assert 'if event["display_state"] in ("superseded", "deployment_advanced"):' in src
assert 'event["current"] = False' in src
print("ok")
PY
  echo "$output"; [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

@test "e2e dashboard CM parses and its embedded JSON references e2e_* metrics" {
  run python3 - "${DASH}" <<'PY'
import sys, yaml, json
d = yaml.safe_load(open(sys.argv[1]))
assert d["kind"] == "ConfigMap"
assert d["metadata"]["namespace"] == "monitoring"
assert d["metadata"]["labels"]["grafana_dashboard"] == "1"
blob = d["data"]["e2e.json"]
dash = json.loads(blob)
assert dash["uid"] == "e2e-verification"
for m in ("e2e_last_run_pass", "e2e_last_success_timestamp_seconds",
          "e2e_last_run_duration_seconds", "e2e_run_info"):
    assert m in blob, "dashboard missing " + m
vars = {v["name"]: v for v in dash["templating"]["list"]}
assert "runner" in vars, "dashboard missing runner template variable"
assert vars["runner"]["current"]["value"] == "$__all", "runner var must default to All"
for p in dash["panels"]:
    for t in p.get("targets", []):
        assert 'runner=~"$runner"' in t["expr"], "panel %s not filtered by runner" % p["id"]
print("ok")
PY
  echo "$output"; [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

@test "prometheusrule defines the e2e alerts group and all alerts" {
  run python3 - "${RULE}" <<'PY'
import sys, yaml
r = list(yaml.safe_load_all(open(sys.argv[1])))[0]
groups = {g["name"]: g for g in r["spec"]["groups"]}
assert "e2e.alerts" in groups, list(groups)
rules = groups["e2e.alerts"]["rules"]
alerts = [rule["alert"] for rule in rules]
assert alerts == ["E2EVerificationFailing", "E2EVerificationStale", "E2EResultsMissing"], alerts
for rule in rules:
    if rule["alert"] == "E2EResultsMissing":
        continue
    has_runner = "$labels.runner" in rule["annotations"]["summary"]
    assert has_runner == (rule["alert"] == "E2EVerificationFailing"), rule["alert"]
print("ok")
PY
  echo "$output"; [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

@test "e2e alerts aggregate away the scrape target and name the exported service" {
  run python3 - "${RULE}" <<'PY'
import sys, yaml
r = list(yaml.safe_load_all(open(sys.argv[1])))[0]
groups = {g["name"]: g for g in r["spec"]["groups"]}
for rule in groups["e2e.alerts"]["rules"]:
    if rule["alert"] == "E2EResultsMissing":
        continue
    expr = rule["expr"]
    want = ("max by (tier, exported_service, project)" if rule["alert"] == "E2EVerificationStale"
            else "max by (tier, exported_service, project, runner)")
    assert want + " (" in expr, (rule["alert"], expr)
    for field in ("summary", "description"):
        text = rule["annotations"][field]
        assert "$labels.service " not in text and "$labels.service}" not in text, (rule["alert"], field)
        assert "$labels.exported_service" in text, (rule["alert"], field)
print("ok")
PY
  echo "$output"; [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

@test "e2e staleness is fresh if any runner passed recently" {
  if ! command -v promtool >/dev/null 2>&1; then skip "promtool not installed"; fi
  rules_file="${BATS_TEST_TMPDIR}/e2e-rules.yml"
  test_file="${BATS_TEST_TMPDIR}/e2e-staleness.test.yml"
  python3 - "${RULE}" "${rules_file}" <<'PY'
import sys, yaml
document = next(d for d in yaml.safe_load_all(open(sys.argv[1]))
                if d and d.get("kind") == "PrometheusRule")
yaml.safe_dump({"groups": document["spec"]["groups"]}, open(sys.argv[2], "w"), sort_keys=False)
PY
  python3 - "${rules_file}" "${test_file}" <<'PY'
import sys
rules_file, test_file = sys.argv[1:]
open(test_file, "w").write(f"""rule_files:
  - {rules_file}
evaluation_interval: 1m
tests:
  - interval: 1m
    input_series:
      - series: 'e2e_last_success_timestamp_seconds{{tier=\"vcluster\", exported_service=\"product-catalog\", project=\"api+flows\", runner=\"local-m4\"}}'
        values: '0x7200'
      - series: 'e2e_last_success_timestamp_seconds{{tier=\"vcluster\", exported_service=\"product-catalog\", project=\"api+flows\", runner=\"m2\"}}'
        values: '259200x7200'
    alert_rule_test:
      - eval_time: 5d
        alertname: E2EVerificationStale
        exp_alerts: []
  - interval: 1m
    input_series:
      - series: 'e2e_last_success_timestamp_seconds{{tier=\"vcluster\", exported_service=\"product-catalog\", project=\"api+flows\", runner=\"local-m4\"}}'
        values: '0x7200'
      - series: 'e2e_last_success_timestamp_seconds{{tier=\"vcluster\", exported_service=\"product-catalog\", project=\"api+flows\", runner=\"m2\"}}'
        values: '0x7200'
    alert_rule_test:
      - eval_time: 5d
        alertname: E2EVerificationStale
        exp_alerts:
          - exp_labels:
              alertname: E2EVerificationStale
              exported_service: product-catalog
              project: api+flows
              tier: e2e
              group: e2e
              severity: warning
            exp_annotations:
              summary: 'no passing e2e for product-catalog/vcluster on any runner in >3d'
              description: 'No passing e2e run for product-catalog on the vcluster substrate on any runner in over 3 days; the verification signal is stale.'
""")
PY
  run promtool test rules "${test_file}"
  echo "$output"; [ "${status}" -eq 0 ]
}

@test "E2EResultsMissing fires only when the hub has no e2e results" {
  if ! command -v promtool >/dev/null 2>&1; then skip "promtool not installed"; fi
  rules_file="${BATS_TEST_TMPDIR}/e2e-rules-missing.yml"
  test_file="${BATS_TEST_TMPDIR}/e2e-missing.test.yml"
  python3 - "${RULE}" "${rules_file}" <<'PY'
import sys, yaml
document = next(d for d in yaml.safe_load_all(open(sys.argv[1]))
                if d and d.get("kind") == "PrometheusRule")
group = next(g for g in document["spec"]["groups"] if g["name"] == "e2e.alerts")
yaml.safe_dump({"groups": [group]}, open(sys.argv[2], "w"), sort_keys=False)
PY
  {
    printf '%s\n' 'rule_files:' "  - ${rules_file}" 'evaluation_interval: 1m' 'tests:'
    printf '%s\n' '  - interval: 1m' '    input_series: []' '    alert_rule_test:'
    printf '%s\n' '      - eval_time: 7h' '        alertname: E2EResultsMissing' '        exp_alerts:'
    printf '%s\n' '          - exp_labels:' '              alertname: E2EResultsMissing' '              group: e2e' '              severity: warning'
    printf '%s\n' '            exp_annotations:' "              summary: 'no e2e results on the hub'" "              description: 'The hub has no e2e result ConfigMaps (k3dm.k3d.io/e2e-result=true), so E2EVerificationStale cannot fire. After a hub rebuild run make e2e-republish RUNNER=m2; otherwise check vulnerability-inventory-exporter in platform-ops.'"
    printf '%s\n' '  - interval: 1m' '    input_series:' '      - series: '\''e2e_last_run_pass{tier="vcluster", exported_service="basket", project="api+flows", runner="m2"}'\''' '        values: '\''0x420'\''' '    alert_rule_test:'
    printf '%s\n' '      - eval_time: 7h' '        alertname: E2EResultsMissing' '        exp_alerts: []'
  } > "${test_file}"
  run promtool test rules "${test_file}"
  echo "$output"; [ "${status}" -eq 0 ]
}

@test "argocd platform-ops deploy applies the e2e dashboard" {
  run grep -F -- 'grafana-dashboard-e2e.yaml' "${ARGOCD}"
  echo "$output"; [ "${status}" -eq 0 ]
}

@test "Alertmanager has a non-null severity warning route" {
  run yq -r '.route.routes[] | select(.matchers[] == "severity = warning") | .receiver' "${AM_TMPL}"
  echo "$output"; [ "${status}" -eq 0 ]
  [ -n "${output}" ]
  [ "${output}" != "null" ]
}

@test "Alertmanager warning catch-all follows the named allowlist" {
  allow="$(yq -r '.route.routes | to_entries | map(select(.value.matchers[] | contains("alertname =~"))) | .[0].key' "${AM_TMPL}")"
  warning="$(yq -r '.route.routes | to_entries | map(select(.value.matchers[] | contains("severity = warning"))) | .[0].key' "${AM_TMPL}")"
  [[ "${allow}" =~ ^[0-9]+$ ]]
  [[ "${warning}" =~ ^[0-9]+$ ]]
  [ "${warning}" -gt "${allow}" ]
}

@test "e2e runs carry a run date and say whether a failure was fixed later" {
  run python3 - "${EXPORTER}" "${DASH}" <<'PY'
import ast, json, sys, time, yaml
docs = list(yaml.safe_load_all(open(sys.argv[1])))
cm = next(d for d in docs if d and d.get("kind") == "ConfigMap"
          and d["metadata"]["name"] == "vulnerability-inventory-exporter")
src = cm["data"]["exporter.py"]
tree = ast.parse(src)
ns = {"time": time}
for node in ast.walk(tree):
    if isinstance(node, ast.FunctionDef) and node.name in ("e2e_utc", "e2e_run_status"):
        exec(compile(ast.Module(body=[node], type_ignores=[]), "exporter", "exec"), ns)
def ev(seconds, passed, service="product-catalog"):
    return {"tier": "vcluster", "service": service, "project": "api+flows",
            "runner": "local-m4", "run_seconds": seconds, "passed": passed}
old_fail = ev(1791290346, False)
fix = ev(1791290881, True)
open_fail = ev(1791400000, False)
other = ev(1791500000, True, service="basket")
events = [old_fail, fix, open_fail, other]
assert ns["e2e_utc"](1791290346) == "2026-10-06 12:39 UTC", ns["e2e_utc"](1791290346)
assert ns["e2e_run_status"](fix, events) == "passed"
assert ns["e2e_run_status"](old_fail, events) == "fixed: passed 2026-10-06 12:48 UTC", ns["e2e_run_status"](old_fail, events)
assert ns["e2e_run_status"](open_fail, events) == "still failing"
assert 'info["run_date"]' in src and 'info["run_status"]' in src
dash = json.loads(yaml.safe_load(open(sys.argv[2]))["data"]["e2e.json"])
panel = next(p for p in dash["panels"] if p["title"] == "Recent runs")
org = panel["transformations"][0]["options"]
assert org["indexByName"]["run_date"] == 0 and org["indexByName"]["run_status"] == 1
assert org["renameByName"]["run_status"] == "Status now"
assert panel["options"]["sortBy"][0] == {"displayName": "Run date", "desc": True}
print("ok")
PY
  echo "$output"; [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}
