#!/usr/bin/env bats
# shellcheck disable=SC1091

setup() {
  source "${BATS_TEST_DIRNAME}/../python_yaml.bash"
  source "${BATS_TEST_DIRNAME}/../promtool.bash"
}

RULE="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/prometheusrule.yaml"

@test "positive control: promtool finds HubDataExportStale in dr.alerts" {
  rules_file="${BATS_TEST_TMPDIR}/dr-rules.yml"
  test_file="${BATS_TEST_TMPDIR}/dr.test.yml"
  "$(k3dm_python_yaml)" - "${RULE}" "${rules_file}" <<'PY'
import sys, yaml
document = next(d for d in yaml.safe_load_all(open(sys.argv[1]))
                if d and d.get("kind") == "PrometheusRule")
group = next(g for g in document["spec"]["groups"] if g["name"] == "dr.alerts")
yaml.safe_dump({"groups": [group]}, open(sys.argv[2], "w"), sort_keys=False)
PY
  cat > "${test_file}" <<EOF
rule_files:
  - ${rules_file}
evaluation_interval: 1m
tests:
  - interval: 1m
    input_series:
      - series: 'k3dm_hub_data_export_last_success_timestamp_seconds'
        values: '0+0x3000'
    alert_rule_test:
      - eval_time: 37h
        alertname: HubDataExportStale
        exp_alerts:
          - exp_labels:
              alertname: HubDataExportStale
              group: dr
              severity: warning
            exp_annotations:
              summary: 'Hub data export is stale'
              description: 'No successful hub data export has been verified for more than 36 hours.'
EOF
  run k3dm_promtool test rules "${test_file}"
  echo "$output"
  [ "${status}" -eq 0 ]
}

@test "DispatchMetricsStale alert fires when push is stale and M4 is reachable" {
  rules_file="${BATS_TEST_TMPDIR}/dispatch-rules.yml"
  test_file="${BATS_TEST_TMPDIR}/dispatch.test.yml"
  "$(k3dm_python_yaml)" - "${RULE}" "${rules_file}" <<'PY'
import sys, yaml
document = next(d for d in yaml.safe_load_all(open(sys.argv[1]))
                if d and d.get("kind") == "PrometheusRule")
groups = [g for g in document["spec"]["groups"] if g["name"] == "dispatch.alerts"]
if not groups:
    sys.exit(1)
yaml.safe_dump({"groups": groups}, open(sys.argv[2], "w"), sort_keys=False)
PY
  cat > "${test_file}" <<EOF
rule_files:
  - ${rules_file}
evaluation_interval: 1m
tests:
  # Case 1: fresh push + M4 reachable -> no alert
  - interval: 1m
    input_series:
      - series: 'push_time_seconds{job="k3dm-dispatch"}'
        values: '60000+0x100'
      - series: 'k3dm_disk_probe_success{host="m4",job="k3dm-disk",path="/System/Volumes/Data"}'
        values: '1+0x100'
    alert_rule_test:
      - eval_time: 35m
        alertname: DispatchMetricsStale
        exp_alerts: []

  # Case 2: stale push + M4 reachable -> fires after 30m hold, not before; recovers when fresh
  - interval: 1m
    input_series:
      - series: 'push_time_seconds{job="k3dm-dispatch"}'
        values: '0+0x91 100000+0x50'
      - series: 'k3dm_disk_probe_success{host="m4",job="k3dm-disk",path="/System/Volumes/Data"}'
        values: '1+0x150'
    alert_rule_test:
      - eval_time: 90m
        alertname: DispatchMetricsStale
        exp_alerts: []
      - eval_time: 91m
        alertname: DispatchMetricsStale
        exp_alerts:
          - exp_labels:
              alertname: DispatchMetricsStale
              job: k3dm-dispatch
              group: dispatch
              severity: warning
              cluster: hub
            exp_annotations:
              summary: "Dispatch metrics have not reached the hub for over 90 minutes while the M4 is reachable"
              description: "The M4 pushes dispatch metrics after dispatch ledger events and every 15 minutes (LaunchAgent com.k3d-manager.dispatch-metrics). Check ~/.local/share/k3d-manager/worktrees/metrics.log and ~/.local/share/k3d-manager/logs/dispatch-metrics.log on the M4, and the com.k3d-manager.hub-pushgateway-port-forward tunnel. See docs/bugs/2026-11-18-dispatch-metrics-push-times-out-silently.md."
      # Recovery when fresh push arrives
      - eval_time: 95m
        alertname: DispatchMetricsStale
        exp_alerts: []

  # Case 3: absent series + M4 reachable -> fires after 30m
  - interval: 1m
    input_series:
      - series: 'k3dm_disk_probe_success{host="m4",job="k3dm-disk",path="/System/Volumes/Data"}'
        values: '1+0x60'
    alert_rule_test:
      - eval_time: 30m
        alertname: DispatchMetricsStale
        exp_alerts:
          - exp_labels:
              alertname: DispatchMetricsStale
              job: k3dm-dispatch
              group: dispatch
              severity: warning
              cluster: hub
            exp_annotations:
              summary: "Dispatch metrics have not reached the hub for over 90 minutes while the M4 is reachable"
              description: "The M4 pushes dispatch metrics after dispatch ledger events and every 15 minutes (LaunchAgent com.k3d-manager.dispatch-metrics). Check ~/.local/share/k3d-manager/worktrees/metrics.log and ~/.local/share/k3d-manager/logs/dispatch-metrics.log on the M4, and the com.k3d-manager.hub-pushgateway-port-forward tunnel. See docs/bugs/2026-11-18-dispatch-metrics-push-times-out-silently.md."

  # Case 4: stale push + M4 unreachable (probe 0) -> no alert
  - interval: 1m
    input_series:
      - series: 'push_time_seconds{job="k3dm-dispatch"}'
        values: '0+0x100'
      - series: 'k3dm_disk_probe_success{host="m4",job="k3dm-disk",path="/System/Volumes/Data"}'
        values: '0+0x100'
    alert_rule_test:
      - eval_time: 95m
        alertname: DispatchMetricsStale
        exp_alerts: []
EOF
  run k3dm_promtool test rules "${test_file}"
  echo "$output"
  [ "${status}" -eq 0 ]
}
