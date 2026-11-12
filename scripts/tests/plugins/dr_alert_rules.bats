#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../python_yaml.bash"
}

@test "DR rules: failed and stale alerts are warning alerts in dr.alerts" {
  run "$(k3dm_python_yaml)" - scripts/etc/argocd/platform-ops/prometheusrule.yaml <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
rules = next(g['rules'] for g in doc['spec']['groups'] if g['name'] == 'dr.alerts')
assert {r['alert'] for r in rules} == {'DRDrillFailed', 'DRDrillStale', 'HubDataExportFailed', 'HubDataExportStale', 'HubDataExportNeverRan'}
assert all(r['labels']['severity'] == 'warning' for r in rules)
PY
  [ "$status" -eq 0 ]
}

@test "DR rules: rendered Alertmanager routes both alerts to platform-warning" {
  run "$(k3dm_python_yaml)" - scripts/etc/prometheus/alertmanager.yaml.tmpl <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
routes = doc['route']['routes']
route = next(r for r in routes if 'DRDrillFailed' in r['matchers'][0])
assert route['receiver'] == 'platform-warning'
assert 'DRDrillStale' in route['matchers'][0]
assert not any(r.get('receiver') == 'sms-critical' and 'DRDrillFailed' in str(r) for r in routes)
PY
  [ "$status" -eq 0 ]
}
