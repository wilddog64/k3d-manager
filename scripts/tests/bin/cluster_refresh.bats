#!/usr/bin/env bats

@test "cluster-refresh regenerates the Grafana plist from the hub wrapper" {
  local home_dir="${BATS_TEST_TMPDIR}/home"
  local state_dir="${BATS_TEST_TMPDIR}/state"
  local plist="${home_dir}/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist"
  local wrapper="${plist%.plist}.sh"
  local block="${BATS_TEST_TMPDIR}/grafana-block.sh"
  local repo_root

  repo_root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  mkdir -p "$(dirname "${wrapper}")"
  : > "${wrapper}"
  sed -n '/^  _grafana_pf_label=/,/^  _launchd_ensure/p' "${repo_root}/bin/cluster-refresh" | sed '$d' > "${block}"
  run env HOME="${home_dir}" bash -c '
    _ACG_STATE_DIR="$2"
    _app_context="ubuntu-k3s"
    _provider_kubeconfig="${HOME}/.kube/ubuntu-k3s.yaml"
    _info() { :; }
    source "$3"
  ' bash "${REPO_ROOT}/bin/cluster-refresh" "${state_dir}" "${block}"

  [ "$status" -eq 0 ]
  grep -q '<string>/bin/bash</string>' "${plist}"
  grep -q 'com.k3d-manager.grafana-port-forward.sh' "${plist}"
  ! grep -q 'acg-kube-prometheus-stack-grafana' "${plist}"
}

@test "cluster-refresh retains the ACG Grafana plist when the hub wrapper is absent" {
  local home_dir="${BATS_TEST_TMPDIR}/home"
  local state_dir="${BATS_TEST_TMPDIR}/state"
  local plist="${home_dir}/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist"
  local block="${BATS_TEST_TMPDIR}/grafana-block.sh"
  local repo_root

  repo_root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  mkdir -p "$(dirname "${plist}")"
  sed -n '/^  _grafana_pf_label=/,/^  _launchd_ensure/p' "${repo_root}/bin/cluster-refresh" | sed '$d' > "${block}"
  run env HOME="${home_dir}" bash -c '
    _ACG_STATE_DIR="$2"
    _app_context="ubuntu-k3s"
    _provider_kubeconfig="${HOME}/.kube/ubuntu-k3s.yaml"
    _info() { :; }
    source "$3"
  ' bash "${REPO_ROOT}/bin/cluster-refresh" "${state_dir}" "${block}"

  [ "$status" -eq 0 ]
  grep -q 'acg-kube-prometheus-stack-grafana' "${plist}"
}

@test "cluster-refresh regenerates browser wrappers before bootstrapping launchd" {
  run grep -nF 'NODE_PATH="${_ACG_DIR}/node_modules" node -e "require('\''playwright'\'')"' bin/cluster-refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"require('playwright')"* ]]

  run grep -nF 'npm --prefix "${_ACG_DIR}" ci' bin/cluster-refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *'npm --prefix "${_ACG_DIR}" ci'* ]]

  run grep -nF '_argocd_write_browser_https_wrapper "${_argocd_browser_wrapper}" "${_argocd_browser_log}"' bin/cluster-refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"_argocd_write_browser_https_wrapper"* ]]

  run grep -nF 'regenerating argocd-browser-https wrapper' bin/cluster-refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"regenerating argocd-browser-https wrapper"* ]]

  run grep -nF '_frontend_browser_wrapper="${_ACG_STATE_DIR}/bin/frontend-browser-http.sh"' bin/cluster-refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"frontend-browser-http.sh"* ]]

  run grep -nF 'starting frontend port-forward: svc/frontend → 127.0.0.2:80' bin/cluster-refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"starting frontend port-forward"* ]]
}
