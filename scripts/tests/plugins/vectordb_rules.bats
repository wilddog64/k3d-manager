#!/usr/bin/env bats

RULES="${BATS_TEST_DIRNAME}/../../etc/prometheus/rules/vectordb.yaml"

@test "vectordb rules target the hub prometheus stack" {
  run grep -F -- 'release: kube-prometheus-stack' "${RULES}"
  [ "${status}" -eq 0 ]
}

@test "both vectordb alerts are present" {
  local _alert
  for _alert in VectorDBMetricsStale VectorDBIndexStale; do
    run grep -F -- "alert: ${_alert}" "${RULES}"
    [ "${status}" -eq 0 ]
  done
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
