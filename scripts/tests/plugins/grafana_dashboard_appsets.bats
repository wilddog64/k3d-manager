#!/usr/bin/env bats

ACG="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/grafana-dashboards-acg.yaml"
HUB="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/grafana-dashboards-hub.yaml"
PLUGIN="${BATS_TEST_DIRNAME}/../../plugins/observability.sh"
DASHBOARD="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-cve-autopatch.yaml"
OVERVIEW="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/grafana-overview-readable-configmap.yaml"
HUB_OVERVIEW="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml"
PLATFORM_OPS_DIR="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops"
DASHBOARDS_DIR="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards"

_assert_server_keyed_hub_exclude() {
  local appset="$1"
  local exclude
  exclude="$(yq -r '.spec.template.spec.source.directory.exclude // ""' "$appset")" || return 1
  [[ "$exclude" == *'{{if eq .server "https://kubernetes.default.svc"}}'* ]] || return 1
  [[ "$exclude" == *'{{end}}'* ]] || return 1
  [[ "$exclude" != *'{{if eq .name'* ]] || return 1
}

_assert_acg_excludes_hub_owned_tests() {
  local appset="$1"
  local exclude
  exclude="$(yq -r '.spec.template.spec.source.directory.exclude // ""' "$appset")" || return 1
  [[ "$exclude" == *"k3dm-tests-configmap.yaml"* ]] || return 1
}

_assert_collision_files_excluded() {
  local appset="$1"
  local platform_ops_dir="$2"
  local dashboards_dir="$3"
  local exclude platform_file dashboard_file platform_name dashboard_name dashboard_basename
  exclude="$(yq -r '.spec.template.spec.source.directory.exclude // ""' "$appset")" || return 1

  for platform_file in "$platform_ops_dir"/*.yaml; do
    platform_name="$(yq -r 'select(.kind == "ConfigMap") | .metadata.name // ""' "$platform_file")" || return 1
    [ -n "$platform_name" ] || continue
    for dashboard_file in "$dashboards_dir"/*.yaml; do
      dashboard_name="$(yq -r 'select(.kind == "ConfigMap") | .metadata.name // ""' "$dashboard_file")" || return 1
      [ "$platform_name" = "$dashboard_name" ] || continue
      dashboard_basename="$(basename "$dashboard_file")"
      [[ "$exclude" == *"$dashboard_basename"* ]] || return 1
    done
  done
}

_assert_hub_exclude_contract() {
  _assert_server_keyed_hub_exclude "$1" || return 1
  _assert_collision_files_excluded "$1" "$2" "$3" || return 1
}

_build_info_panel() {
  local dashboard_file="$1"
  yq -r '.data["grafana-overview-readable.json"]' "$dashboard_file" | jq -c '.panels[] | select(.id == 10)'
}

_assert_build_info_contract() {
  local dashboard_file="$1"
  local panel
  panel="$(_build_info_panel "$dashboard_file")" || return 1
  [ "$(jq -r '.targets[0].format' <<<"$panel")" = "table" ] || return 1
  [ "$(jq -r '.targets[0].instant' <<<"$panel")" = "true" ] || return 1
  [ "$(jq -r '.targets[0] | has("legendFormat")' <<<"$panel")" = "false" ] || return 1
  [ "$(jq -c '.transformations[0].options.include.names' <<<"$panel")" = '["version","edition","pod"]' ] || return 1
  [ "$(jq -r '[.transformations[].id] | join(",")' <<<"$panel")" = "filterFieldsByName,organize" ] || return 1
  [ "$(jq -r '[.transformations[] | select(.id == "organize") | .options.indexByName | to_entries | sort_by(.value) | .[].key] | join(",")' <<<"$panel")" = "version,edition,pod" ] || return 1
  [ "$(jq -r '[.transformations[] | select(.id == "organize") | .options.renameByName | to_entries | sort_by(.key) | .[] | (.key + "=" + .value)] | join(",")' <<<"$panel")" = "edition=Edition,pod=Pod,version=Version" ] || return 1
  [ "$(jq -e 'any(.transformations[]; .id == "labelsToFields") | not' <<<"$panel")" = "true" ] || return 1
  [ "$(jq -c '[.fieldConfig.overrides[] | select(.matcher.id == "byName" and .matcher.options == "Version") | .properties[] | select(.id == "custom.width") | .value]' <<<"$panel")" = '[90]' ] || return 1
  [ "$(jq -c '[.fieldConfig.overrides[] | select(.matcher.id == "byName" and .matcher.options == "Edition") | .properties[] | select(.id == "custom.width") | .value]' <<<"$panel")" = '[90]' ] || return 1
  jq -e 'all(.fieldConfig.overrides[]?; (.matcher.id == "byName" and .matcher.options == "Pod") | not)' <<<"$panel" >/dev/null || return 1
}

_assert_query_contract() {
  local dashboard_file="$1"
  local dashboard_json firing request
  dashboard_json="$(yq -r '.data["grafana-overview-readable.json"]' "$dashboard_file")" || return 1
  firing="$(jq -c '.panels[] | select(.id == 6)' <<<"$dashboard_json")" || return 1
  request="$(jq -c '.panels[] | select(.id == 2)' <<<"$dashboard_json")" || return 1
  jq -e '(.targets[0].expr | contains("ALERTS{alertstate=\"firing\"")) and (.targets[0].expr | contains("Watchdog|InfoInhibitor")) and (.targets[0].expr | contains("or vector(0)")) and (.targets[0].expr | contains("grafana_alerting_alerts") | not) and (.targets[0].expr | contains("grafana_alerting_result_total") | not) and (.fieldConfig.defaults.noValue == "0") and (.title == "Firing Alerts (Prometheus)") and ([.fieldConfig.defaults.thresholds.steps[] | select(.color == "red") | .value] | index(1) != null)' <<<"$firing" >/dev/null || return 1
  jq -e '(.targets[0].expr | contains("rate(")) and (.targets[0].expr | contains("[$__rate_interval]")) and (.targets[0].expr | contains("irate(") | not) and (.targets[0].expr | contains("[1m]") | not) and (.targets[0] | has("interval") | not) and (.description | contains("kubelet /api/health")) and (.description | contains("Status -1"))' <<<"$request" >/dev/null || return 1
}

_assert_category_contract() {
  local dashboard_file="$1"
  local dashboard_json category
  dashboard_json="$(yq -r '.data["grafana-overview-readable.json"]' "$dashboard_file")" || return 1
  category="$(jq -c '.panels[] | select(.id == 12)' <<<"$dashboard_json")" || return 1
  jq -e '(.type == "table") and (.targets[0].expr | contains("ALERTS{alertstate=\"firing\"")) and (.targets[0].expr | contains("Watchdog|InfoInhibitor")) and (.targets[0].expr | contains("count by (category, alertname, severity, cluster)")) and (.targets[0].expr | contains("Image vulnerabilities")) and (.targets[0].expr | contains("Trivy.*")) and (.targets[0].expr | contains("\"cluster\", \"hub\", \"cluster\", \"\"")) and (.targets[0].format == "table") and (.targets[0].instant == true) and ([.transformations[] | select(.id == "organize") | .options.renameByName.Value] | index("Count") != null)' <<<"$category" >/dev/null || return 1
}

_assert_no_panel_overlap() {
  local dashboard_file="$1"
  yq -r '.data["grafana-overview-readable.json"]' "$dashboard_file" | jq -e '
    def overlaps($a; $b):
      ($a.x < ($b.x + $b.w)) and (($a.x + $a.w) > $b.x) and
      ($a.y < ($b.y + $b.h)) and (($a.y + $a.h) > $b.y);
    .panels as $panels |
    [range(0; ($panels | length)) as $i |
     range(($i + 1); ($panels | length)) as $j |
     select(overlaps($panels[$i].gridPos; $panels[$j].gridPos))] |
    length == 0' >/dev/null
}

@test "acg dashboard appset targets app-cluster role" {
  run yq -r '.spec.generators[0].clusters.selector.matchLabels["k3d-manager/role"]' "${ACG}"
  [ "$status" -eq 0 ]
  [ "$output" = "app-cluster" ]
}

@test "acg dashboard appset syncs the dashboards directory" {
  run yq -r '.spec.template.spec.source.path' "${ACG}"
  [ "$output" = "scripts/etc/grafana/dashboards" ]
}

@test "acg dashboard appset excludes hub collisions by server" {
  _assert_hub_exclude_contract "${ACG}" "${PLATFORM_OPS_DIR}" "${DASHBOARDS_DIR}"
}

@test "acg dashboard appset does not manage the hub-owned k3dm tests dashboard" {
  _assert_acg_excludes_hub_owned_tests "${ACG}"
}

@test "acg dashboard appset collision guard rejects a missing exclude" {
  local snapshot="${BATS_TEST_TMPDIR}/grafana-dashboards-acg.yaml"
  cp "${ACG}" "$snapshot"
  yq -i 'del(.spec.template.spec.source.directory.exclude)' "$snapshot"
  run _assert_hub_exclude_contract "$snapshot" "${PLATFORM_OPS_DIR}" "${DASHBOARDS_DIR}"
  printf 'mutation (a) missing exclude: status=%s output=%s\n' "$status" "$output"
  [ "$status" -ne 0 ]
  cp "${ACG}" "$snapshot"
  cmp -s "${ACG}" "$snapshot"
  printf 'mutation (a) restore: cmp=identical\n'
}

@test "acg dashboard appset collision guard rejects a name-keyed condition" {
  local snapshot="${BATS_TEST_TMPDIR}/grafana-dashboards-acg-name.yaml"
  cp "${ACG}" "$snapshot"
  sed 's/eq \.server/eq .name/' "${ACG}" > "$snapshot"
  run _assert_hub_exclude_contract "$snapshot" "${PLATFORM_OPS_DIR}" "${DASHBOARDS_DIR}"
  printf 'mutation (b) name condition: status=%s output=%s\n' "$status" "$output"
  [ "$status" -ne 0 ]
  cp "${ACG}" "$snapshot"
  cmp -s "${ACG}" "$snapshot"
  printf 'mutation (b) restore: cmp=identical\n'
}

@test "acg dashboard appset collision guard derives a second platform collision" {
  local platform_copy="${BATS_TEST_TMPDIR}/platform-ops"
  local second_collision="${platform_copy}/grafana-dashboard-second-collision.yaml"
  local second_snapshot="${BATS_TEST_TMPDIR}/grafana-dashboard-second-collision.snapshot.yaml"
  cp -R "${PLATFORM_OPS_DIR}" "$platform_copy"
  cp "${HUB_OVERVIEW}" "$second_collision"
  yq -i '.metadata.name = "checkout-loadtest-dashboard"' "$second_collision"
  cp "$second_collision" "$second_snapshot"
  run _assert_hub_exclude_contract "${ACG}" "$platform_copy" "${DASHBOARDS_DIR}"
  printf 'mutation (c) second collision: status=%s output=%s\n' "$status" "$output"
  [ "$status" -ne 0 ]
  cp "$second_snapshot" "$second_collision"
  cmp -s "$second_snapshot" "$second_collision"
  printf 'mutation (c) restore: cmp=identical\n'
}

@test "hub dashboard appset includes all grafana-dashboard configmaps" {
  run yq -r '.spec.template.spec.sources[] | select(.path == "scripts/etc/argocd/platform-ops") | .directory.include' "${HUB}"
  [ "$output" = "grafana-dashboard-*.yaml" ]
}

@test "hub dashboard appset imports the k3dm tests dashboard" {
  run yq -r '.spec.template.spec.sources[] | select(.path == "scripts/etc/grafana/dashboards") | .directory.include' "${HUB}"
  [ "$status" -eq 0 ]
  [ "$output" = "k3dm-tests-configmap.yaml" ]
}

@test "k3dm tests dashboard uses the hub Prometheus datasource" {
  local tests_dashboard="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/k3dm-tests-configmap.yaml"
  run yq -r '.data["k3dm-tests.json"]' "${tests_dashboard}"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'all(.panels[] | .targets[]?; .datasource.uid == "prometheus")' >/dev/null
}

@test "k3dm tests failing-suite table has human-readable columns" {
  local tests_dashboard="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/k3dm-tests-configmap.yaml"
  local dashboard panel
  dashboard="$(yq -r '.data["k3dm-tests.json"]' "${tests_dashboard}")"
  panel="$(jq -c '.panels[] | select(.id == 4)' <<<"${dashboard}")"
  [ -n "${panel}" ]
  [ "$(jq -r '.title' <<<"${panel}")" = "Failing test cases (latest run)" ]
  [ "$(jq -r '.targets[0].instant' <<<"${panel}")" = "true" ]
  [ "$(jq -r '.targets[0].expr' <<<"${panel}")" = "k3dm_test_failure" ]
  jq -e '.transformations[] | select(.id == "organize") | .options.renameByName | .suite == "Test suite" and .case == "Case" and .name == "Test name" and .reason == "Failure reason"' <<<"${panel}" >/dev/null
  jq -e '.transformations[] | select(.id == "organize") | .options.excludeByName | .Time and .__name__ and .instance and .job and .Value' <<<"${panel}" >/dev/null
}

@test "both dashboard appsets self-heal" {
  run yq -r '.spec.template.spec.syncPolicy.automated.selfHeal' "${ACG}"
  [ "$output" = "true" ]
  run yq -r '.spec.template.spec.syncPolicy.automated.selfHeal' "${HUB}"
  [ "$output" = "true" ]
}

@test "Checkout Load Test CPU saturation uses a window that spans several scrapes" {
  local file="${DASHBOARDS_DIR}/checkout-loadtest-configmap.yaml"
  local panel
  panel="$(yq -r '.data["checkout-loadtest.json"]' "$file" | jq -c '.panels[] | select(.id == 5)')"
  [ -n "$panel" ]
  jq -e '(.targets[0].expr | contains("container_cpu_usage_seconds_total")) and (.targets[0].expr | contains("[5m]")) and (.targets[0].expr | contains("[1m]") | not) and (.targets[0].expr | contains("$__rate_interval") | not) and (.description | contains("once a minute"))' <<<"$panel" >/dev/null
}

@test "observability plugin applies both dashboard appsets" {
  run grep -c 'grafana-dashboards-\(acg\|hub\).yaml' "${PLUGIN}"
  [ "$output" = "2" ]
}

@test "CVE remediation outcome panels preserve the affected service" {
  run grep -F -- 'sum by (exported_service) (cve_remediation_state{state=\"applied\",current=\"true\"})' "${DASHBOARD}"
  [ "$status" -eq 0 ]

  run grep -F -- '"legendFormat": "{{exported_service}}"' "${DASHBOARD}"
  [ "$status" -eq 0 ]

  run grep -F -- '"textMode": "valueAndName"' "${DASHBOARD}"
  [ "$status" -eq 0 ]

  run grep -F -- 'sum by (exported_service, state) (cve_remediation_state{state=~\"failed|superseded|deployment_advanced\"})' "${DASHBOARD}"
  [ "$status" -eq 0 ]

  run grep -F -- '"legendFormat": "{{exported_service}} ({{state}})"' "${DASHBOARD}"
  [ "$status" -eq 0 ]
}

@test "Grafana Overview uses readable request labels" {
  run yq -r '.data["grafana-overview-readable.json"]' "${OVERVIEW}"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq empty
  [[ "$output" == *'"title": "Grafana Health & Firing Alerts"'* ]]
  [[ "$output" == *'"legendFormat": "HTTP {{status_code}}"'* ]]
  [[ "$output" == *'"legendFormat": "p99 — 99th percentile"'* ]]
  [[ "$output" == *'"legendFormat": "p50 — median"'* ]]
  [[ "$output" == *'"legendFormat": "Average — arithmetic mean"'* ]]
  [[ "$output" == *'Status -1 means the request did not produce a normal HTTP response'* ]]
}

@test "Grafana Overview dashboard count names what it counts" {
  local dashboard
  for dashboard in "${OVERVIEW}" "${HUB_OVERVIEW}"; do
    run grep -F -- '"title": "Grafana Dashboards Loaded"' "$dashboard"
    [ "$status" -eq 0 ]
    run grep -F -- '"title": "Dashboards"' "$dashboard"
    [ "$status" -ne 0 ]
  done
}

@test "hub Grafana Overview uses the same readable dashboard contract" {
  run yq -r '.data["grafana-overview-readable.json"]' "${HUB_OVERVIEW}"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq empty
  [[ "$output" == *'"title": "Grafana Health & Firing Alerts"'* ]]
  [[ "$output" == *'"legendFormat": "HTTP {{status_code}}"'* ]]
  [[ "$output" == *'"legendFormat": "p99 — 99th percentile"'* ]]
}

@test "readable Overview title does not collide with the stock Grafana Overview" {
  local dashboard
  for dashboard in "${OVERVIEW}" "${HUB_OVERVIEW}"; do
    run grep -F -- '"title": "Grafana Overview' "$dashboard"
    [ "$status" -ne 0 ]
  done
}

@test "Grafana Health dashboard has a fixed uid and k3dm tags" {
  local dashboard
  for dashboard in "${OVERVIEW}" "${HUB_OVERVIEW}"; do
    run bash -c "yq -r '.data[\"grafana-overview-readable.json\"]' '$dashboard' | jq -e '.uid == \"k3dm-grafana-health\" and (.tags | index(\"k3d-manager\")) != null'"
    [ "$status" -eq 0 ]
  done
}

@test "Grafana Overview Build Info panels use the positive table contract" {
  _assert_build_info_contract "${OVERVIEW}"
  _assert_build_info_contract "${HUB_OVERVIEW}"
}

@test "Grafana Overview Build Info panels stay byte-identical" {
  local app_panel hub_panel
  app_panel="$(_build_info_panel "${OVERVIEW}")"
  hub_panel="$(_build_info_panel "${HUB_OVERVIEW}")"
  [ "$(jq -S . <<<"$app_panel")" = "$(jq -S . <<<"$hub_panel")" ]
}

@test "Grafana Overview query panels use live metrics and rate interval" {
  _assert_query_contract "${OVERVIEW}"
  _assert_query_contract "${HUB_OVERVIEW}"
}

@test "Grafana Overview Firing Alerts and Request Rate panels stay byte-identical" {
  [ "$(jq -S '[.panels[] | select(.id == 6 or .id == 2 or .id == 12)]' < <(yq -r '.data["grafana-overview-readable.json"]' "${OVERVIEW}"))" = "$(jq -S '[.panels[] | select(.id == 6 or .id == 2 or .id == 12)]' < <(yq -r '.data["grafana-overview-readable.json"]' "${HUB_OVERVIEW}"))" ]
}

@test "Grafana Overview Firing Alerts by Category panels satisfy the table contract" {
  _assert_category_contract "${OVERVIEW}"
  _assert_category_contract "${HUB_OVERVIEW}"
}

@test "Grafana Overview panels do not overlap" {
  _assert_no_panel_overlap "${OVERVIEW}"
  _assert_no_panel_overlap "${HUB_OVERVIEW}"
}

@test "Grafana Overview category mutation rejects a missing Trivy category" {
  local snapshot="${BATS_TEST_TMPDIR}/app-overview-category.yaml"
  cp "${OVERVIEW}" "$snapshot"
  yq -i '(.data["grafana-overview-readable.json"] |= (fromjson | (.panels[] | select(.id == 12) | .targets[0].expr) |= sub("Trivy\\.\\*"; "Cve.*") | tojson))' "$snapshot"
  run _assert_category_contract "$snapshot"
  printf 'mutation (a) missing Trivy category: status=%s output=%s\n' "$status" "$output"
  [ "$status" -ne 0 ]
  cp "${OVERVIEW}" "$snapshot"
  cmp -s "${OVERVIEW}" "$snapshot"
  printf 'mutation (a) restore: cmp=identical\n'
}

@test "Grafana Overview category mutation rejects a time-series format" {
  local snapshot="${HUB_OVERVIEW}"
  local mutation="${BATS_TEST_TMPDIR}/hub-overview-category.yaml"
  cp "$snapshot" "$mutation"
  yq -i '(.data["grafana-overview-readable.json"] |= (fromjson | (.panels[] | select(.id == 12) | .targets[0].format) = "time_series" | tojson))' "$mutation"
  run _assert_category_contract "$mutation"
  printf 'mutation (b) time_series format: status=%s output=%s\n' "$status" "$output"
  [ "$status" -ne 0 ]
  cp "$snapshot" "$mutation"
  cmp -s "$snapshot" "$mutation"
  printf 'mutation (b) restore: cmp=identical\n'
}

@test "Grafana Overview query mutation rejects a fixed one-minute window" {
  local snapshot="${BATS_TEST_TMPDIR}/hub-overview-rate.yaml"
  cp "${HUB_OVERVIEW}" "$snapshot"
  yq -i '(.data["grafana-overview-readable.json"] |= (fromjson | (.panels[] | select(.id == 2) | .targets[0].expr) = "sum by (status_code) (rate(grafana_http_request_duration_seconds_count{job=~\"$job\", instance=~\"$instance\"}[1m]))" | tojson))' "$snapshot"
  run _assert_query_contract "$snapshot"
  [ "$status" -ne 0 ]
  cp "${HUB_OVERVIEW}" "$snapshot"
  cmp -s "${HUB_OVERVIEW}" "$snapshot"
}

@test "Grafana Overview query mutation rejects the removed alert metric" {
  local snapshot="${BATS_TEST_TMPDIR}/app-overview-alert.yaml"
  cp "${OVERVIEW}" "$snapshot"
  yq -i '(.data["grafana-overview-readable.json"] |= (fromjson | (.panels[] | select(.id == 6) | .targets[0].expr) = "grafana_alerting_result_total{job=~\"$job\", instance=~\"$instance\", state=\"alerting\"}" | tojson))' "$snapshot"
  run _assert_query_contract "$snapshot"
  [ "$status" -ne 0 ]
  cp "${OVERVIEW}" "$snapshot"
  cmp -s "${OVERVIEW}" "$snapshot"
}

@test "Grafana Overview query mutation rejects missing alert exclusion" {
  local snapshot="${BATS_TEST_TMPDIR}/app-overview-alert-exclusion.yaml"
  cp "${OVERVIEW}" "$snapshot"
  yq -i '(.data["grafana-overview-readable.json"] |= (fromjson | (.panels[] | select(.id == 6) | .targets[0].expr) = "count(ALERTS{alertstate=\"firing\"}) or vector(0)" | tojson))' "$snapshot"
  run _assert_query_contract "$snapshot"
  [ "$status" -ne 0 ]
  cp "${OVERVIEW}" "$snapshot"
  cmp -s "${OVERVIEW}" "$snapshot"
}

@test "Grafana Overview query mutation rejects the old Request Rate description" {
  local snapshot="${BATS_TEST_TMPDIR}/hub-overview-description.yaml"
  cp "${HUB_OVERVIEW}" "$snapshot"
  yq -i '(.data["grafana-overview-readable.json"] |= (fromjson | (.panels[] | select(.id == 2) | .description) = "Request rate grouped by HTTP status code. Status -1 means the request did not produce a normal HTTP response, usually because instrumentation recorded an internal failure before a response was available." | tojson))' "$snapshot"
  run _assert_query_contract "$snapshot"
  [ "$status" -ne 0 ]
  cp "${HUB_OVERVIEW}" "$snapshot"
  cmp -s "${HUB_OVERVIEW}" "$snapshot"
}

@test "Grafana Overview Build Info mutation guards reject a missing include" {
  local snapshot="${BATS_TEST_TMPDIR}/hub-overview.yaml"
  cp "${HUB_OVERVIEW}" "$snapshot"
  yq -i '(.data["grafana-overview-readable.json"] |= (fromjson | del(.panels[] | select(.id == 10) | .transformations[0].options.include) | tojson))' "$snapshot"
  run _assert_build_info_contract "$snapshot"
  [ "$status" -ne 0 ]
  cp "${HUB_OVERVIEW}" "$snapshot"
  cmp -s "${HUB_OVERVIEW}" "$snapshot"
}

@test "Grafana Overview Build Info mutation guards reject an extra include name" {
  local snapshot="${BATS_TEST_TMPDIR}/app-overview.yaml"
  cp "${OVERVIEW}" "$snapshot"
  yq -i '(.data["grafana-overview-readable.json"] |= fromjson | .data["grafana-overview-readable.json"].panels[] | select(.id == 10) | .transformations[0].options.include.names += ["__name__"] | .data["grafana-overview-readable.json"] |= tojson)' "$snapshot"
  run _assert_build_info_contract "$snapshot"
  [ "$status" -ne 0 ]
  cp "${OVERVIEW}" "$snapshot"
  cmp -s "${OVERVIEW}" "$snapshot"
}

@test "Grafana Overview Build Info mutation guards reject missing width overrides" {
  local snapshot="${BATS_TEST_TMPDIR}/hub-overview-widths.yaml"
  cp "${HUB_OVERVIEW}" "$snapshot"
  yq -i '(.data["grafana-overview-readable.json"] |= (fromjson | del(.panels[] | select(.id == 10) | .fieldConfig.overrides) | tojson))' "$snapshot"
  run _assert_build_info_contract "$snapshot"
  printf 'mutation missing width overrides: status=%s output=%s snapshot=%s\n' "$status" "$output" "$snapshot"
  [ "$status" -ne 0 ]
  cp "${HUB_OVERVIEW}" "$snapshot"
  cmp -s "${HUB_OVERVIEW}" "$snapshot"
}

@test "k3dm tests dashboard shows the latest run classification" {
  local tests_dashboard="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/k3dm-tests-configmap.yaml"
  run yq -r '.data["k3dm-tests.json"]' "${tests_dashboard}"
  [ "$status" -eq 0 ]
  local dashboard_json="$output"
  local panel
  panel=$(printf '%s\n' "$dashboard_json" | jq -c '.panels[] | select(.id == 7)')
  [ -n "$panel" ]
  [ "$(jq -r '.title' <<<"$panel")" = "Latest run classification" ]
  [ "$(jq '[.fieldConfig.defaults.mappings[]? | tostring | test("PASS|EXPECTED ENVIRONMENT")] | any' <<<"$panel")" = "false" ]
  [ "$(jq -r '.targets[0].expr' <<<"$panel")" = "k3dm_test_run_classification" ]
  run jq -e '.targets[0].expr | contains("last_over_time")' <<<"$panel"
  [ "$status" -ne 0 ]
  jq -e '.description | contains("failed_untriaged")' <<<"$panel" >/dev/null
  printf '%s\n' "$dashboard_json" | jq -e '.panels[] | select(.title == "Failed cases" and (.targets[0].expr == "k3dm_test_cases_failed"))' >/dev/null
  printf '%s\n' "$dashboard_json" | jq -e '.panels[] | select(.title == "Last run" and .fieldConfig.defaults.unit == "dateTimeAsIso" and .targets[0].expr == "max(k3dm_test_last_timestamp_seconds) * 1000")' >/dev/null
  printf '%s\n' "$dashboard_json" | jq -e '.panels[] | select(.title == "Time since last successful run")' >/dev/null
  printf '%s\n' "$dashboard_json" | jq -e '.panels[] | select(.title == "Failing test cases (latest run)" and (.description | contains("No data means")))' >/dev/null
}

@test "k3dm tests freshness stats aggregate to one latest value" {
  local tests_dashboard="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/k3dm-tests-configmap.yaml"
  run yq -r '.data["k3dm-tests.json"]' "${tests_dashboard}"
  [ "$status" -eq 0 ]
  local dashboard_json="$output"
  local latest_panel successful_panel
  latest_panel=$(printf '%s\n' "$dashboard_json" | jq -c '.panels[] | select(.id == 1)')
  successful_panel=$(printf '%s\n' "$dashboard_json" | jq -c '.panels[] | select(.id == 2)')
  [ "$(jq -r '.targets[0].expr' <<<"$latest_panel")" = "max(k3dm_test_last_timestamp_seconds) * 1000" ]
  [ "$(jq -r '.targets[0].instant' <<<"$latest_panel")" = "true" ]
  jq -e '.targets[0].expr | startswith("time() - max(")' <<<"$successful_panel" >/dev/null
  [ "$(jq -r '.targets[0].instant' <<<"$successful_panel")" = "true" ]
  [ "$(printf '%s\n' "$dashboard_json" | jq -r '.panels[] | select(.id == 2) | .title')" = "Time since last successful run" ]
}
