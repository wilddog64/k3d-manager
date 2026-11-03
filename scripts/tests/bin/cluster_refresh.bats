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
  run grep -q 'acg-kube-prometheus-stack-grafana' "${plist}"
  [ "$status" -ne 0 ]
}

@test "cluster-refresh scopes sandbox tunnel and ArgoCD endpoint" {
  run grep -nF 'export TUNNEL_SCOPE=sandbox' bin/cluster-refresh
  [ "$status" -eq 0 ]
  run grep -nF 'https://host.k3d.internal:${TUNNEL_SANDBOX_LOCAL_PORT:-16443}' bin/cluster-refresh
  [ "$status" -eq 0 ]
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

@test "cluster-refresh regenerates user wrappers after fixed listener installation" {
  run grep -nF 'NODE_PATH="${_ACG_DIR}/node_modules" node -e "require('\''playwright'\'')"' bin/cluster-refresh
  [ "$status" -eq 0 ]
  run grep -nF 'npm --prefix "${_ACG_DIR}" ci' bin/cluster-refresh
  [ "$status" -eq 0 ]

  run grep -nF '_acg_refresh_install_listener argocd-https' bin/cluster-refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *'"${ARGOCD_BROWSER_PORT:-443}"'* ]]
  run grep -nF '_argocd_write_browser_https_wrapper' bin/cluster-refresh
  [ "$status" -ne 0 ]
  run grep -nF '_acg_refresh_install_listener keycloak-http' bin/cluster-refresh
  [ "$status" -eq 0 ]
  local listener_line="${output%%:*}"
  run grep -nF '_argocd_write_port_forward_wrapper "${_keycloak_browser_wrapper}"' bin/cluster-refresh
  [ "$status" -eq 0 ]
  local wrapper_line="${output%%:*}"
  [ "$listener_line" -lt "$wrapper_line" ]

  run grep -nF '_frontend_browser_wrapper="${_ACG_STATE_DIR}/bin/frontend-browser-http.sh"' bin/cluster-refresh
  [ "$status" -eq 0 ]
  run grep -nF 'starting frontend port-forward: svc/frontend → 127.0.0.1:18082' bin/cluster-refresh
  [ "$status" -eq 0 ]
  run grep -nF 'write frontend-http' bin/cluster-refresh
  [ "$status" -ne 0 ]
  [[ "$output" != *"launchctl bootstrap system"* ]]
}

@test "cluster-refresh listener helper uses interactive sudo in a TTY and succeeds when enabled" {
  local block="${BATS_TEST_TMPDIR}/listener-helper.sh"
  local repo_root
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  sed -n '/^_cluster_refresh_stdin_is_tty()/,/^}/p; /^_acg_refresh_install_listener()/,/^}/p' \
    "${repo_root}/bin/cluster-refresh" > "${block}"
  run env CLUSTER_PROVIDER=k3s-aws LISTENER_TEST_STATE="${BATS_TEST_TMPDIR}/state" LISTENER_TEST_BLOCK="${block}" bash -c '
    _ACG_STATE_DIR="${LISTENER_TEST_STATE}"
    _cluster_provider="${CLUSTER_PROVIDER}"
    mkdir -p "${LISTENER_TEST_STATE}"
    calls="${LISTENER_TEST_STATE}/calls"
    _warn() { printf "%s\n" "$*"; }
    _run_command() { printf "%s\n" "$*" >> "$calls"; return "${RUNNER_RC:-1}"; }
    source "${LISTENER_TEST_BLOCK}"
    _cluster_refresh_stdin_is_tty() { return 0; }
    if _acg_refresh_install_listener argocd-https "$1/cert" "$1/key"; then exit 9; fi
    grep -q -- "--interactive-sudo" "$calls"
    if grep -q -- "--prefer-sudo" "$calls"; then exit 1; fi
    RUNNER_RC=0 _acg_refresh_install_listener argocd-https "$1/cert" "$1/key"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"secure argocd-https listener helper failed"* ]]
  [ "$(grep -c -- 'argocd-https' "${BATS_TEST_TMPDIR}/state/calls")" -eq 2 ]
}

@test "cluster-refresh listener failure stays soft without a TTY and has a recovery command" {
  local block="${BATS_TEST_TMPDIR}/listener-helper.sh"
  local repo_root
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  sed -n '/^_cluster_refresh_stdin_is_tty()/,/^}/p; /^_acg_refresh_install_listener()/,/^}/p' \
    "${repo_root}/bin/cluster-refresh" > "${block}"
  run env CLUSTER_PROVIDER=k3s-aws LISTENER_TEST_STATE="${BATS_TEST_TMPDIR}/state" LISTENER_TEST_BLOCK="${block}" bash -c '
    _ACG_STATE_DIR="${LISTENER_TEST_STATE}"
    _cluster_provider="${CLUSTER_PROVIDER}"
    mkdir -p "${LISTENER_TEST_STATE}"
    calls="${LISTENER_TEST_STATE}/calls"
    _warn() { printf "%s\n" "$*"; }
    _run_command() { printf "%s\n" "$*" >> "$calls"; return 1; }
    source "${LISTENER_TEST_BLOCK}"
    _cluster_refresh_stdin_is_tty() { return 1; }
    if _acg_refresh_install_listener keycloak-http; then exit 9; fi
    [[ $(wc -l < "$calls") -eq 1 ]]
    grep -q -- "--interactive-sudo" "$calls"
    if grep -q -- "--prefer-sudo" "$calls"; then exit 1; fi
    if grep -q "launchctl bootstrap" "$calls"; then exit 1; fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"sudo -v && make refresh CLUSTER_PROVIDER=k3s-aws"* ]]
}
