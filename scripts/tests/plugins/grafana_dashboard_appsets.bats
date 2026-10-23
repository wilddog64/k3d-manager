#!/usr/bin/env bats

ACG="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/grafana-dashboards-acg.yaml"
HUB="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/grafana-dashboards-hub.yaml"
PLUGIN="${BATS_TEST_DIRNAME}/../../plugins/observability.sh"
DASHBOARD="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-cve-autopatch.yaml"
BUGS_DASHBOARD="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-bugs.yaml"
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

_render_acg_exclude_for_server() {
  local appset="$1"
  local server="$2"
  local exclude
  exclude="$(yq -r '.spec.template.spec.source.directory.exclude // ""' "$appset")" || return 1
  if [[ "$server" == "https://kubernetes.default.svc" ]]; then
    exclude="$(sed 's/{{if eq .server "https:\/\/kubernetes.default.svc"}}//; s/{{end}}//' <<<"$exclude")" || return 1
  else
    [[ "$exclude" =~ ^(.*),\{\{if\ eq\ \.server ]] || return 1
    exclude="${BASH_REMATCH[1]}"
  fi
  printf '%s\n' "$exclude"
}

_assert_checkout_dashboard_excluded_for_hub() {
  local appset="$1"
  local exclude
  exclude="$(_render_acg_exclude_for_server "$appset" "https://kubernetes.default.svc")" || return 1
  [[ "$exclude" == *"checkout-loadtest-configmap.yaml"* ]]
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

_bugs_panel() {
  local dashboard_file="$1"
  yq -r '.data["k3dm-bugs.json"]' "$dashboard_file" | jq -c '.panels[] | select(.title == "Bugs")'
}

_assert_bugs_table_filter_contract() {
  local dashboard_file="$1"
  local panel
  panel="$(_bugs_panel "$dashboard_file")" || return 1
  jq -e '([.fieldConfig.overrides[] | select(.matcher.id == "byName" and .matcher.options == "Bug") | .properties[] | select(.id == "custom.filterable" and .value == true)] | length == 1) and (.targets[0].expr | contains("repo=\"$repo\"")) and (.targets[0].expr | contains("release=~\"$release\"")) and (.targets[0].expr | contains("live_verified=~\"$verified\""))' <<<"$panel" >/dev/null || return 1
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

_assert_active_alert_empty_cell_contract() {
  local dashboard_file="$1"
  local dashboard_json panel
  dashboard_json="$(yq -r '.data["grafana-overview-readable.json"]' "$dashboard_file")" || return 1
  panel="$(jq -c '.panels[] | select(.id == 13)' <<<"$dashboard_json")" || return 1
  jq -e '(.fieldConfig.defaults.noValue == "—") and ((.fieldConfig.defaults.noValue | contains("No firing")) | not) and (.description | contains("An empty table means no firing instance has an active-state timestamp."))' <<<"$panel" >/dev/null
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

@test "acg dashboard appset renders the checkout dashboard exclusion only for the hub" {
  local hub_exclude acg_exclude
  hub_exclude="$(_render_acg_exclude_for_server "${ACG}" "https://kubernetes.default.svc")"
  acg_exclude="$(_render_acg_exclude_for_server "${ACG}" "https://hostinger.example")"
  [[ "$hub_exclude" == *"checkout-loadtest-configmap.yaml"* ]]
  [[ "$acg_exclude" != *"checkout-loadtest-configmap.yaml"* ]]
}

@test "acg dashboard appset checkout exclusion guard rejects a missing filename" {
  local snapshot="${BATS_TEST_TMPDIR}/grafana-dashboards-acg-checkout.yaml"
  sed 's/,checkout-loadtest-configmap.yaml//' "${ACG}" > "$snapshot"
  run _assert_checkout_dashboard_excluded_for_hub "$snapshot"
  printf 'mutation (d) checkout exclusion: status=%s output=%s\n' "$status" "$output"
  [ "$status" -ne 0 ]
  cp "${ACG}" "$snapshot"
  cmp -s "${ACG}" "$snapshot"
  printf 'mutation (d) restore: cmp=identical\n'
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
  yq -i '.metadata.name = "k3dm-deployment-metrics"' "$second_collision"
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

@test "k3dm tests dashboard preserves failed cases across the selected range" {
  local tests_dashboard="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/k3dm-tests-configmap.yaml"
  local dashboard panel
  dashboard="$(yq -r '.data["k3dm-tests.json"]' "${tests_dashboard}")"
  panel="$(jq -c '.panels[] | select(.id == 8)' <<<"${dashboard}")"
  [ -n "${panel}" ]
  [ "$(jq -r '.title' <<<"${panel}")" = "Failures in selected time range" ]
  [ "$(jq -r '.targets[0].instant' <<<"${panel}")" = "true" ]
  [ "$(jq -r '.targets[0].expr' <<<"${panel}")" = "max_over_time(k3dm_test_failure[\$__range])" ]
  jq -e '.transformations[] | select(.id == "organize") | .options.renameByName | .instance == "Target / origin" and .suite == "Test suite" and .case == "Case" and .name == "Test name" and .reason == "Failure reason"' <<<"${panel}" >/dev/null
  jq -e '.transformations[] | select(.id == "organize") | .options.excludeByName | .Time and .__name__ and .job and .Value and (has("instance") | not)' <<<"${panel}" >/dev/null
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

@test "Grafana Bugs table title is filterable and preserves query selectors" {
  _assert_bugs_table_filter_contract "${BUGS_DASHBOARD}"
}

@test "Grafana Bugs table contract rejects an unfilterable title and missing selector" {
  local snapshot="${BATS_TEST_TMPDIR}/grafana-bugs-mutated.yaml"
  cp "${BUGS_DASHBOARD}" "$snapshot"
  yq -i '(.data["k3dm-bugs.json"] |= (fromjson | (.panels[] | select(.title == "Bugs") | .fieldConfig.overrides[] | select(.matcher.options == "Bug") | .properties) |= map(select(.id != "custom.filterable")) | tojson))' "$snapshot"
  run _assert_bugs_table_filter_contract "$snapshot"
  printf 'pre-fix representation (title filter missing): status=%s output=%s\n' "$status" "$output"
  [ "$status" -ne 0 ]

  cp "${BUGS_DASHBOARD}" "$snapshot"
  yq -i '(.data["k3dm-bugs.json"] |= (fromjson | (.panels[] | select(.title == "Bugs") | .targets[0].expr) |= sub("repo=\\\"\\$repo\\\","; "") | tojson))' "$snapshot"
  run _assert_bugs_table_filter_contract "$snapshot"
  printf 'mutation (query missing repo matcher): status=%s output=%s\n' "$status" "$output"
  [ "$status" -ne 0 ]
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
  [ "$(jq -S '[.panels[] | select(.id == 6 or .id == 2 or .id == 12 or .id == 13 or .id == 14)]' < <(yq -r '.data["grafana-overview-readable.json"]' "${OVERVIEW}"))" = "$(jq -S '[.panels[] | select(.id == 6 or .id == 2 or .id == 12 or .id == 13 or .id == 14)]' < <(yq -r '.data["grafana-overview-readable.json"]' "${HUB_OVERVIEW}"))" ]
}

@test "Grafana Overview Firing Alerts by Category panels satisfy the table contract" {
  _assert_category_contract "${OVERVIEW}"
  _assert_category_contract "${HUB_OVERVIEW}"
}

@test "active alert instances use a dash for missing labels in both dashboards" {
  _assert_active_alert_empty_cell_contract "${OVERVIEW}"
  _assert_active_alert_empty_cell_contract "${HUB_OVERVIEW}"
}

_assert_firing_instance_contract() {
  local dashboard_file="$1"
  local dashboard_json detail category
  dashboard_json="$(yq -r '.data["grafana-overview-readable.json"]' "$dashboard_file")" || return 1
  detail="$(jq -c '.panels[] | select(.id == 13)' <<<"$dashboard_json")" || return 1
  category="$(jq -c '.panels[] | select(.id == 12)' <<<"$dashboard_json")" || return 1
  jq -e '(.type == "table") and (.title | contains("Active Since (local; pending included)")) and (.description | contains("not a firing start or CVE detection time")) and (.description | contains("for: 15m")) and (.description | contains("elapsed alert active-state duration calculated from ALERTS_FOR_STATE")) and (.description | contains("not CVE age, time unpatched, first detection, or exact firing-start time")) and (.title | contains("Elapsed time since active")) and (.targets[1].legendFormat == "Elapsed time since active") and ([.targets[].expr | contains("bottomk(200") ] | all) and (.targets[0].expr | endswith("* 1000")) and ([.targets[].expr | contains("ALERTS_FOR_STATE") ] | all) and ([.targets[].expr | contains("alertstate=\"firing\"") ] | all) and (.targets | length == 2) and ([.transformations[].id] | index("merge") != null) and ([.transformations[] | select(.id == "filterFieldsByName") | .options.include.names] | flatten | index("alertname") != null) and ([.transformations[] | select(.id == "filterFieldsByName") | .options.include.names] | flatten | index("app") != null) and ([.transformations[] | select(.id == "filterFieldsByName") | .options.include.names] | flatten | index("pod") != null) and ([.transformations[] | select(.id == "filterFieldsByName") | .options.include.names] | flatten | index("instance") != null) and ([.transformations[] | select(.id == "filterFieldsByName") | .options.include.names] | flatten | index("severity") != null) and ([.transformations[] | select(.id == "filterFieldsByName") | .options.include.names] | flatten | index("__name__") == null) and ([.transformations[] | select(.id == "filterFieldsByName") | .options.include.names] | flatten | index("group") == null) and ([.transformations[] | select(.id == "filterFieldsByName") | .options.include.names] | flatten | index("tier") == null) and ([.transformations[] | select(.id == "organize") | .options.renameByName["Value #B"]] | index("Elapsed time since active") != null) and ([.fieldConfig.overrides[].properties[] | select(.id == "unit") | .value] | index("dateTimeAsIso") != null) and ([.fieldConfig.overrides[].properties[] | select(.id == "unit") | .value] | index("s") != null)' <<<"$detail" >/dev/null || return 1
  jq -e '([.transformations[] | select(.id == "organize") | .options.indexByName] | any(.namespace == 0 and .cluster == 1 and .alertname == 2 and .category == 3 and .app == 4 and .pod == 5 and .instance == 6 and .severity == 7 and .["Value #A"] == 8 and .["Value #B"] == 9))' <<<"$detail" >/dev/null || return 1
  jq -e '(.targets[0].expr | contains("count by (category, alertname, severity, cluster)")) and (.targets[0].expr | contains("Trivy.*")) and (.targets[0].expr | contains("category"))' <<<"$category" >/dev/null || return 1
  jq -e '(.panels[] | select(.id == 14) | .title == "CVE Findings — Report Created at (local)") and (.panels[] | select(.id == 14) | .targets[0].expr | contains("topk(200, trivy_vulnerability_report_created_timestamp_seconds) * 1000")) and (.panels[] | select(.id == 14) | .description | contains("not when the vulnerability was first detected")) and ([.panels[] | select(.id == 14) | .transformations[] | select(.id == "filterFieldsByName") | .options.include.names] | flatten | index("vulnerability_id") != null) and ([.panels[] | select(.id == 14) | .transformations[] | select(.id == "filterFieldsByName") | .options.include.names] | flatten | index("resource_name") != null) and ([.panels[] | select(.id == 14) | .transformations[] | select(.id == "organize") | .options.renameByName.resource_name] | index("Workload/report owner") != null)' <<<"$dashboard_json" >/dev/null || return 1
  jq -e '.timezone == "browser"' <<<"$dashboard_json" >/dev/null || return 1
}

_assert_dashboard_promql_parentheses() {
  local dashboard_file="$1"
  local expr
  while IFS= read -r expr; do
    python3 -c 'import sys
s=sys.argv[1]
depth=0; quoted=False; escaped=False; calls=[]; i=0
while i < len(s):
    c=s[i]
    if quoted:
        if escaped: escaped=False
        elif c == "\\": escaped=True
        elif c == "\"": quoted=False
    elif c == "\"": quoted=True
    elif s.startswith("label_replace(", i):
        calls.append(i + len("label_replace"))
    elif c == "(": depth += 1
    elif c == ")":
        depth -= 1
        if depth < 0: sys.exit(1)
    i += 1
if quoted or depth != 0: sys.exit(1)
# Each call position must have a matching closing delimiter, accounting for nesting.
for start in calls:
    depth=0; braces=0; brackets=0; quoted=False; escaped=False; commas=0
    for c in s[start:]:
        if quoted:
            if escaped: escaped=False
            elif c == "\\": escaped=True
            elif c == "\"": quoted=False
        elif c == "\"": quoted=True
        elif c == "(": depth += 1
        elif c == "{": braces += 1
        elif c == "}": braces -= 1
        elif c == "[": brackets += 1
        elif c == "]": brackets -= 1
        elif c == "," and depth == 1 and braces == 0 and brackets == 0: commas += 1
        elif c == ")":
            depth -= 1
            if depth == 0: break
    if depth != 0 or commas != 4: sys.exit(1)
if len(calls) != s.count("label_replace("): sys.exit(1)' "$expr" || return 1
    if command -v promtool >/dev/null 2>&1; then
      local rules_file="${BATS_TEST_TMPDIR}/panel-13-rules.yml"
      python3 -c 'import json,sys; print(json.dumps({"groups":[{"name":"panel13","rules":[{"alert":"Panel13QueryParse","expr":sys.argv[1]}]}]}))' "$expr" >"$rules_file" || return 1
      promtool check rules "$rules_file" >/dev/null || return 1
    fi
  done < <(yq -r '.data["grafana-overview-readable.json"]' "$dashboard_file" | jq -r '.panels[].targets[]?.expr // empty')
}

@test "Grafana Overview panel expressions have balanced PromQL parentheses" {
  _assert_dashboard_promql_parentheses "${OVERVIEW}"
  _assert_dashboard_promql_parentheses "${HUB_OVERVIEW}"
}

@test "Grafana Overview expression guard rejects an unbalanced mutation" {
  local snapshot="${BATS_TEST_TMPDIR}/overview-unbalanced-expression.yaml"
  cp "${OVERVIEW}" "${snapshot}"
  yq -i '(.data["grafana-overview-readable.json"] |= (fromjson | (.panels[] | select(.id == 13) | .targets[0].expr) |= ("(" + .) | tojson))' "${snapshot}"
  if _assert_dashboard_promql_parentheses "${snapshot}"; then
    return 1
  fi
}

@test "Grafana Overview firing instance detail contract is safe and preserves category counts" {
  _assert_firing_instance_contract "${OVERVIEW}"
  _assert_firing_instance_contract "${HUB_OVERVIEW}"
}

@test "Grafana Overview CVE report-time panels stay synchronized and bounded" {
  local app_cve hub_cve
  app_cve="$(jq -S '.panels[] | select(.id == 14)' < <(yq -r '.data["grafana-overview-readable.json"]' "${OVERVIEW}"))"
  hub_cve="$(jq -S '.panels[] | select(.id == 14)' < <(yq -r '.data["grafana-overview-readable.json"]' "${HUB_OVERVIEW}"))"
  [ -n "$app_cve" ] && [ "$app_cve" = "$hub_cve" ]
  jq -e '(.targets[0].expr | startswith("topk(200,")) and (.targets[0].expr | endswith("* 1000")) and ([.transformations[] | select(.id == "filterFieldsByName") | .options.include.names] | flatten | index("Value") != null) and ([.transformations[] | select(.id == "organize") | .options.indexByName] | any(.vulnerability_id == 0 and .severity == 1 and .cluster == 2 and .namespace == 3 and .image_repository == 4 and .resource_name == 5 and .package == 6 and .installed_version == 7 and .fixed_version == 8 and .Value == 9))' <<<"$app_cve" >/dev/null
}

@test "Grafana Overview firing instance fixtures preserve per-instance context and safe fallbacks" {
  local fixture result
  fixture='[{"alertname":"TrivyCriticalVulnerabilityDetected","category":"Image vulnerabilities","severity":"critical","cluster":"hub","instance":"cve-a","active_since":1761070000,"pending_for_seconds":0},{"alertname":"TrivyCriticalVulnerabilityDetected","category":"Image vulnerabilities","severity":"critical","cluster":"ubuntu-hostinger","instance":"cve-b","active_since":1761073600,"pending_for_seconds":300},{"alertname":"TargetDown","category":"Monitoring stack","severity":"warning","cluster":"acg","instance":"node-exporter","active_since":1761075000,"pending_for_seconds":60},{"alertname":"HostDiskMetricsStale","cluster":"hub","instance":"node-exporter","active_since":null,"pending_for_seconds":0}]'
  result="$(jq -c '[.[] | select(.active_since != null) | {alertname, category, severity, cluster, instance, active_since, active_duration: (1761075600 - .active_since), label: "Active since (UTC; pending included)"}]' <<<"$fixture")"
  jq -e 'length == 3 and .[0].active_since != .[1].active_since and .[0].instance != .[1].instance and .[1].active_duration == 2000 and all(.[]; .label == "Active since (UTC; pending included)" and .category != null and .severity != null)' <<<"$result" >/dev/null
  [ "$(jq 'length' <<<'[]')" = '0' ]
}

@test "Grafana Overview firing instance regression rejects the pre-fix missing detail panel" {
  local snapshot="${BATS_TEST_TMPDIR}/overview-no-instance-panel.yaml"
  cp "${OVERVIEW}" "$snapshot"
  yq -i '(.data["grafana-overview-readable.json"] |= (fromjson | .panels |= map(select(.id != 13)) | tojson))' "$snapshot"
  run _assert_firing_instance_contract "$snapshot"
  printf 'pre-fix representation (detail panel absent): status=%s output=%s\n' "$status" "$output"
  [ "$status" -ne 0 ]
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
  # shellcheck disable=SC2016
  yq -i '(.data["grafana-overview-readable.json"] |= (fromjson | (.panels[] | select(.id == 2) | .targets[0].expr) = "sum by (status_code) (rate(grafana_http_request_duration_seconds_count{job=~\"$job\", instance=~\"$instance\"}[1m]))" | tojson))' "$snapshot"
  run _assert_query_contract "$snapshot"
  [ "$status" -ne 0 ]
  cp "${HUB_OVERVIEW}" "$snapshot"
  cmp -s "${HUB_OVERVIEW}" "$snapshot"
}

@test "Grafana Overview query mutation rejects the removed alert metric" {
  local snapshot="${BATS_TEST_TMPDIR}/app-overview-alert.yaml"
  cp "${OVERVIEW}" "$snapshot"
  # shellcheck disable=SC2016
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
  printf '%s\n' "$dashboard_json" | jq -e '.panels[] | select(.title == "Last run" and .fieldConfig.defaults.color.mode == "fixed" and .fieldConfig.defaults.color.fixedColor == "text")' >/dev/null
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

@test "every provisioned Grafana dashboard carries at least one tag" {
  local file untagged=""
  for file in "${PLATFORM_OPS_DIR}"/grafana-dashboard-*.yaml "${DASHBOARDS_DIR}"/*.yaml; do
    while IFS= read -r dashboard_json; do
      [ -n "$dashboard_json" ] || continue
      if ! jq -e '(.tags // []) | length > 0' <<<"$dashboard_json" >/dev/null; then
        untagged+="${file##*/} "
      fi
    done < <(yq -o=json -I=0 '.data // {} | to_entries | .[] | select(.key | test("\\.json$")) | .value' "$file" | jq -c 'fromjson')
  done
  [ -z "$untagged" ] || { echo "untagged dashboards: ${untagged}"; false; }
}
