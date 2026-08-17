#!/usr/bin/env bats

EXPORTER="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml"
DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-e2e.yaml"
RULE="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/prometheusrule.yaml"
ARGOCD="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"

@test "exporter declares the e2e reader and label selector" {
  run grep -F -- 'refresh_e2e_events' "${EXPORTER}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'k3dm.k3d.io%2Fe2e-result%3Dtrue' "${EXPORTER}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'refresh_e2e_events()' "${EXPORTER}"
  [ "${status}" -eq 0 ]
}

@test "exporter emits all five e2e_* gauges" {
  for metric in e2e_run_info e2e_last_run_pass e2e_last_run_timestamp_seconds \
                e2e_last_run_duration_seconds e2e_last_success_timestamp_seconds; do
    run grep -F -- "${metric}{" "${EXPORTER}"
    [ "${status}" -eq 0 ]
  done
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
  [ "${status}" -eq 0 ]
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
  [ "${status}" -eq 0 ]
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
  [ "${status}" -eq 0 ]
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
print("ok")
PY
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

@test "prometheusrule defines the e2e alerts group and both alerts" {
  run python3 - "${RULE}" <<'PY'
import sys, yaml
r = list(yaml.safe_load_all(open(sys.argv[1])))[0]
groups = {g["name"]: g for g in r["spec"]["groups"]}
assert "e2e.alerts" in groups, list(groups)
alerts = [rule["alert"] for rule in groups["e2e.alerts"]["rules"]]
assert alerts == ["E2EVerificationFailing", "E2EVerificationStale"], alerts
print("ok")
PY
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}

@test "argocd platform-ops deploy applies the e2e dashboard" {
  run grep -F -- 'grafana-dashboard-e2e.yaml' "${ARGOCD}"
  [ "${status}" -eq 0 ]
}
