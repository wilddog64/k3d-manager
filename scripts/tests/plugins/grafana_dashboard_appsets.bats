#!/usr/bin/env bats

ACG="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/grafana-dashboards-acg.yaml"
HUB="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/grafana-dashboards-hub.yaml"
PLUGIN="${BATS_TEST_DIRNAME}/../../plugins/observability.sh"
DASHBOARD="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-cve-autopatch.yaml"
OVERVIEW="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/grafana-overview-readable-configmap.yaml"
HUB_OVERVIEW="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml"

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
  [ "$(jq -c '.transformations[0].options.include.names' <<<"$panel")" = '["version","edition","job","instance"]' ] || return 1
  [ "$(jq -r '[.transformations[].id] | join(",")' <<<"$panel")" = "filterFieldsByName,organize" ] || return 1
  [ "$(jq -r '[.transformations[] | select(.id == "organize") | .options.indexByName | to_entries | sort_by(.value) | .[].key] | join(",")' <<<"$panel")" = "version,edition,job,instance" ] || return 1
  [ "$(jq -r '[.transformations[] | select(.id == "organize") | .options.renameByName | to_entries | sort_by(.key) | .[] | (.key + "=" + .value)] | join(",")' <<<"$panel")" = "edition=Edition,instance=Instance,job=Job,version=Version" ] || return 1
  [ "$(jq -e 'any(.transformations[]; .id == "labelsToFields") | not' <<<"$panel")" = "true" ] || return 1
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
