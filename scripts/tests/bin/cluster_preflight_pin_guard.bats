#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
@test "preflight applies the other resources and requires a successful pin lookup for services" {
  source <(sed -n '/^function _cluster_preflight_apply_argocd_resources()/,/^}/p' "$BATS_TEST_DIRNAME/../../../bin/cluster-preflight")
  PREFLIGHT_RENDER_DIR="$BATS_TEST_TMPDIR/render"
  local log="$BATS_TEST_TMPDIR/applies" rc
  _info() { :; }
  _err() { echo "$*"; exit 1; }
  _cluster_preflight_render_platform_project() { :; }
  _cluster_preflight_render_data_layer_app() { :; }
  _cluster_preflight_render_platform_appset() { :; }
  _cluster_preflight_render_services_appset() { :; }
  _cluster_preflight_render_observability_appset() { :; }
  _kubectl() { [[ "$3" == "$PREFLIGHT_RENDER_DIR/"* ]] && echo "${3##*/}" >>"$log"; }
  _run_command() {
    [[ "$*" == '--soft -- git ls-remote --exit-code https://github.com/wilddog64/k3d-manager refs/heads/cve-pins/hub' ]] || return 99
    [ "${GIT_TERMINAL_PROMPT:-}" = 0 ] || return 98
    return "$rc"
  }
  for rc in 0 2 128; do
    : >"$log"
    run _cluster_preflight_apply_argocd_resources sandbox
    for file in platform-project data-layer platform-helm observability-acg; do grep -qx "$file.yaml" "$log"; done
    if (( rc == 0 )); then
      [ "$status" = 0 ]; grep -qx services-git.yaml "$log"
    else
      [ "$status" = 1 ]
      if (( rc == 2 )); then
        [[ "$output" == *"pin branch cve-pins/hub not found (exit 2)"* ]]
      else
        [[ "$output" == *"pin branch lookup failed (rc $rc)"* ]]
      fi
      run ! grep -qx services-git.yaml "$log"
    fi
  done
}
