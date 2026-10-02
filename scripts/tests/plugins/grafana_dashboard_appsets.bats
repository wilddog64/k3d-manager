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
  jq -e '(.targets[0].expr | contains("grafana_alerting_alerts")) and (.targets[0].expr | contains("or vector(0)")) and (.targets[0].expr | contains("grafana_alerting_result_total") | not) and (.fieldConfig.defaults.noValue == "0")' <<<"$firing" >/dev/null || return 1
  jq -e '(.targets[0].expr | contains("rate(")) and (.targets[0].expr | contains("[$__rate_interval]")) and (.targets[0].expr | contains("irate(") | not) and (.targets[0].expr | contains("[1m]") | not) and (.targets[0] | has("interval") | not)' <<<"$request" >/dev/null || return 1
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
  run yq -r '.spec.template.spec.source.directory.include' "${HUB}"
  [ "$output" = "grafana-dashboard-*.yaml" ]
}

@test "both dashboard appsets self-heal" {
  run yq -r '.spec.template.spec.syncPolicy.automated.selfHeal' "${ACG}"
  [ "$output" = "true" ]
  run yq -r '.spec.template.spec.syncPolicy.automated.selfHeal' "${HUB}"
  [ "$output" = "true" ]
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
  [[ "$output" == *'"title": "Grafana Overview — Readable"'* ]]
  [[ "$output" == *'"legendFormat": "HTTP {{status_code}}"'* ]]
  [[ "$output" == *'"legendFormat": "p99 — 99th percentile"'* ]]
  [[ "$output" == *'"legendFormat": "p50 — median"'* ]]
  [[ "$output" == *'"legendFormat": "Average — arithmetic mean"'* ]]
  [[ "$output" == *'Status -1 means the request did not produce a normal HTTP response'* ]]
}

@test "hub Grafana Overview uses the same readable dashboard contract" {
  run yq -r '.data["grafana-overview-readable.json"]' "${HUB_OVERVIEW}"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq empty
  [[ "$output" == *'"title": "Grafana Overview — Readable"'* ]]
  [[ "$output" == *'"legendFormat": "HTTP {{status_code}}"'* ]]
  [[ "$output" == *'"legendFormat": "p99 — 99th percentile"'* ]]
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
  [ "$(jq -S '[.panels[] | select(.id == 6 or .id == 2)]' < <(yq -r '.data["grafana-overview-readable.json"]' "${OVERVIEW}"))" = "$(jq -S '[.panels[] | select(.id == 6 or .id == 2)]' < <(yq -r '.data["grafana-overview-readable.json"]' "${HUB_OVERVIEW}"))" ]
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

@test "k3dm tests dashboard keeps the make exit code informational" {
  local tests_dashboard="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/k3dm-tests-configmap.yaml"
  run yq -r '.data["k3dm-tests.json"]' "${tests_dashboard}"
  [ "$status" -eq 0 ]
  local dashboard_json="$output"
  local panel
  panel=$(printf '%s\n' "$dashboard_json" | jq -c '.panels[] | select(.id == 7)')
  [ -n "$panel" ]
  [ "$(jq -r '.title' <<<"$panel")" = "Make exit code (informational)" ]
  [ "$(jq '[.fieldConfig.defaults.mappings[]? | tostring | test("PASS|EXPECTED ENVIRONMENT")] | any' <<<"$panel")" = "false" ]
  [ "$(jq -r '.targets[0].expr' <<<"$panel")" = "k3dm_test_exit_code" ]
  run jq -e '.targets[0].expr | contains("last_over_time")' <<<"$panel"
  [ "$status" -ne 0 ]
  jq -e '.description | contains("Failed cases")' <<<"$panel" >/dev/null
  printf '%s\n' "$dashboard_json" | jq -e '.panels[] | select(.title == "Failed cases" and (.targets[0].expr == "k3dm_test_cases_failed"))' >/dev/null
}
