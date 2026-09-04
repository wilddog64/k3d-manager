#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
  source "${BATS_TEST_DIRNAME}/../plugins/observability.sh"
}

@test "keep-list predicate: in-list returns 0" {
  run _observability_workload_in_keep_list kube-prometheus-stack-grafana "kube-prometheus-stack-grafana"
  [ "${status}" -eq 0 ]
}

@test "keep-list predicate: not-in-list returns 1" {
  run _observability_workload_in_keep_list prometheus-kube-prometheus-stack-prometheus-0 "kube-prometheus-stack-grafana"
  [ "${status}" -eq 1 ]
}

@test "keep-list predicate: empty keep-list returns 1" {
  run _observability_workload_in_keep_list kube-prometheus-stack-grafana ""
  [ "${status}" -eq 1 ]
}

@test "keep-list predicate: whole-word guard returns 1 both directions" {
  run _observability_workload_in_keep_list grafana "kube-prometheus-stack-grafana"
  [ "${status}" -eq 1 ]
  run _observability_workload_in_keep_list kube-prometheus-stack-grafana "grafana"
  [ "${status}" -eq 1 ]
}

@test "keep-list predicate: multi-entry list returns 0" {
  run _observability_workload_in_keep_list loki-0 "kube-prometheus-stack-grafana loki-0"
  [ "${status}" -eq 0 ]
}
