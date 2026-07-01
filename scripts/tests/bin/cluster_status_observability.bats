#!/usr/bin/env bats

@test "cluster-status surfaces app-cluster Prometheus health and OOM evidence" {
  run grep -nF '=== App Observability (${APP_CONTEXT}) ===' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'get prometheus "${_prom_cr}"' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'operator.prometheus.io/name=${_prom_cr}' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'OOMKilled' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'Grafana panels may be blank until Prometheus stays ready' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status surfaces Alertmanager Cloudflare health" {
  run grep -nF 'https://alertmanager.3ai-talk.org/api/v2/status' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'Alertmanager: HTTP 200' bin/cluster-status
  [ "$status" -eq 0 ]
}
