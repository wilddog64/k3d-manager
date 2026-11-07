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

  run grep -nF 'starting frontend port-forward: svc/frontend → 127.0.0.3:18083' bin/cluster-refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"starting frontend port-forward"* ]]
}

@test "cluster-refresh creates a missing user agent without sudo" {
  local home_dir="${BATS_TEST_TMPDIR}/home" wrapper="${BATS_TEST_TMPDIR}/wrapper.sh"
  local plist="${BATS_TEST_TMPDIR}/home/Library/LaunchAgents/example.plist"
  local functions="${BATS_TEST_TMPDIR}/functions.sh"
  [[ "${home_dir}" == "${BATS_TEST_TMPDIR}/home" ]]
  mkdir -p "${home_dir}"
  : > "${wrapper}"
  sed -n '/^_user_agent_install_if_missing()/,/^}/p' bin/cluster-refresh > "${functions}"
  [ -s "${functions}" ]
  run env HOME="${home_dir}" bash -c '
    _info() { :; }
    source "$1"
    _user_agent_install_if_missing example "$2" "$HOME/logs/example.log" "$3"
  ' bash "${functions}" "${wrapper}" "${plist}"
  [ "$status" -eq 0 ]
  [ -f "${plist}" ]
  grep -F '<string>example</string>' "${plist}"
  grep -F "${wrapper}" "${plist}"
}

@test "cluster-refresh preserves an existing user agent plist" {
  local home_dir="${BATS_TEST_TMPDIR}/home" wrapper="${BATS_TEST_TMPDIR}/wrapper.sh"
  local plist="${BATS_TEST_TMPDIR}/home/Library/LaunchAgents/example.plist"
  local functions="${BATS_TEST_TMPDIR}/functions.sh"
  [[ "${home_dir}" == "${BATS_TEST_TMPDIR}/home" ]]
  mkdir -p "$(dirname "${plist}")"
  printf 'existing plist\n' > "${plist}"
  : > "${wrapper}"
  sed -n '/^_user_agent_install_if_missing()/,/^}/p' bin/cluster-refresh > "${functions}"
  [ -s "${functions}" ]
  run env HOME="${home_dir}" bash -c '
    _info() { :; }
    source "$1"
    _user_agent_install_if_missing example "$2" "$HOME/logs/example.log" "$3"
  ' bash "${functions}" "${wrapper}" "${plist}"
  [ "$status" -eq 0 ]
  [ "$(cat "${plist}")" = 'existing plist' ]
}

@test "N1: refresh browser listeners use user launchd without sudo or system paths" {
  local repo_root home_dir state_dir stub_bin block call_log
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  home_dir="${BATS_TEST_TMPDIR}/home"
  state_dir="${BATS_TEST_TMPDIR}/state"
  stub_bin="${BATS_TEST_TMPDIR}/bin"
  block="${BATS_TEST_TMPDIR}/browser-block.sh"
  call_log="${BATS_TEST_TMPDIR}/calls.log"
  [[ "${home_dir}" == "${BATS_TEST_TMPDIR}/home" ]]
  mkdir -p "${home_dir}/Library/LaunchAgents" "${state_dir}/bin" "${state_dir}/logs" "${state_dir}/argocd-browser-https-tls" "${stub_bin}"
  printf 'fixture\n' > "${state_dir}/argocd-browser-https-tls/fullchain.crt"
  printf 'fixture\n' > "${state_dir}/argocd-browser-https-tls/tls.key"
  : > "${call_log}"
  # Inert command stubs; fixture host m4-air.local, 2026-11-05.
  for command in socat curl kubectl launchctl sudo pkill; do
    cat > "${stub_bin}/${command}" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "${CALL_LOG}"
if [[ "${0##*/}" == launchctl && "${1:-}" == list ]]; then exit 1; fi
STUB
    chmod +x "${stub_bin}/${command}"
  done
  sed -n '/^  # ── 5\./,/^  # ── 6\./p' "${repo_root}/bin/cluster-refresh" > "${block}"
  [ -s "${block}" ]
  sed -n '/^_user_agent_install_if_missing()/,/^}/p' "${repo_root}/bin/cluster-refresh" > "${BATS_TEST_TMPDIR}/writer.sh"
  sed -n '/^_launchd_ensure()/,/^}/p' "${repo_root}/bin/cluster-refresh" >> "${BATS_TEST_TMPDIR}/writer.sh"
  run env HOME="${home_dir}" PATH="${stub_bin}:${PATH}" CALL_LOG="${call_log}" bash -c '
    set -euo pipefail
    [[ "$HOME" == "$1" ]]
    for cmd in socat curl kubectl launchctl sudo pkill; do
      [[ "$(command -v "$cmd")" == "$2/$cmd" ]]
    done
    _ACG_STATE_DIR="$3"
    _info() { :; }
    _warn() { :; }
    _argocd_issue_browser_tls_material() { return 1; }
    _argocd_write_browser_https_wrapper() { : > "$1"; }
    _argocd_write_port_forward_wrapper() { : > "$1"; }
    source "$5"
    _run_command() { printf "run_command %s\n" "$*" >> "$CALL_LOG"; return 1; }
    source "$4"
  ' bash "${home_dir}" "${stub_bin}" "${state_dir}" "${block}" "${BATS_TEST_TMPDIR}/writer.sh"
  [ "${status}" -eq 0 ]
  [ "$(grep -c '^launchctl load ' "${call_log}")" -eq 3 ]
  run grep -E '(^sudo |/Library/LaunchDaemons| system$)' "${call_log}"
  [ "${status}" -ne 0 ]
}

@test "M8: refresh writes user agents and the same high-port browser wrappers" {
  local repo_root home_dir state_dir stub_bin block helpers call_log
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  home_dir="${BATS_TEST_TMPDIR}/home"
  state_dir="${BATS_TEST_TMPDIR}/state"
  stub_bin="${BATS_TEST_TMPDIR}/bin"
  block="${BATS_TEST_TMPDIR}/browser-block.sh"
  helpers="${BATS_TEST_TMPDIR}/helpers.sh"
  call_log="${BATS_TEST_TMPDIR}/calls.log"
  [[ "${home_dir}" == "${BATS_TEST_TMPDIR}/home" ]]
  mkdir -p "${home_dir}/Library/LaunchAgents" "${state_dir}/bin" "${state_dir}/logs" "${state_dir}/argocd-browser-https-tls" "${stub_bin}"
  printf 'fixture\n' > "${state_dir}/argocd-browser-https-tls/fullchain.crt"
  printf 'fixture\n' > "${state_dir}/argocd-browser-https-tls/tls.key"
  : > "${call_log}"
  for command in socat curl kubectl launchctl sudo; do
    cat > "${stub_bin}/${command}" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "${CALL_LOG}"
STUB
    chmod +x "${stub_bin}/${command}"
  done
  sed -n '/^  # ── 5\./,/^  # ── 6\./p' "${repo_root}/bin/cluster-refresh" > "${block}"
  sed -n '/^_user_agent_install_if_missing()/,/^}/p' "${repo_root}/bin/cluster-refresh" > "${helpers}"
  sed -n '/^function _argocd_write_browser_https_wrapper()/,/^}/p' "${repo_root}/scripts/plugins/argocd.sh" >> "${helpers}"
  [ -s "${block}" ] && [ -s "${helpers}" ]
  run env HOME="${home_dir}" PATH="${stub_bin}:${PATH}" CALL_LOG="${call_log}" bash -c '
    set -euo pipefail
    [[ "$HOME" == "$1" ]]
    for cmd in socat curl kubectl launchctl sudo; do
      [[ "$(command -v "$cmd")" == "$2/$cmd" ]]
    done
    _ACG_STATE_DIR="$3"
    SCRIPT_DIR="$4/scripts"
    _info() { :; }
    _warn() { :; }
    _err() { printf "%s\n" "$*" >&2; return 1; }
    _argocd_issue_browser_tls_material() { return 1; }
    _launchd_ensure() { printf "ensure %s\n" "$*" >> "$CALL_LOG"; }
    source "$SCRIPT_DIR/lib/port_forward_wrapper.sh"
    source "$5"
    source "$6"
  ' bash "${home_dir}" "${stub_bin}" "${state_dir}" "${repo_root}" "${helpers}" "${block}"
  [ "${status}" -eq 0 ]
  run python3 - "${home_dir}" "${state_dir}" "${call_log}" "${repo_root}" <<'PY'
import pathlib, plistlib, sys
home, state, log, repo = map(pathlib.Path, sys.argv[1:])
labels = {
    'argocd-https': 'argocd-browser-https.sh',
    'keycloak-http': 'keycloak-browser-http.sh',
    'sandbox-frontend-http': 'frontend-browser-http.sh',
}
for suffix, wrapper in labels.items():
    label = 'com.k3d-manager.browser.' + suffix
    path = home / 'Library/LaunchAgents' / (label + '.plist')
    plist = plistlib.loads(path.read_bytes())
    assert plist['Label'] == label
    assert plist['ProgramArguments'] == ['/bin/bash', str(state / 'bin' / wrapper)]
    assert 'UserName' not in plist
    assert f'ensure {label} {path} user' in log.read_text()
argocd = (state / 'bin/argocd-browser-https.sh').read_text()
keycloak = (state / 'bin/keycloak-browser-http.sh').read_text()
frontend = (state / 'bin/frontend-browser-http.sh').read_text()
assert 'LOCAL_PORT=18443' in argocd and 'https://127.0.0.1:18443/healthz' in argocd
assert 'LOCAL_PORT=18080' in keycloak and 'http://127.0.0.1:18080/health/ready' in keycloak
assert '--address=127.0.0.3' in frontend and 'svc/frontend 18083:80' in frontend
assert 'curl' not in frontend
# The handwritten sandbox wrapper must stay identical to cluster-up's heredoc.
def wrapper_body(path):
    text = path.read_text()
    return text.split('cat > "${_frontend_browser_wrapper}" <<FRONTEND_WRAPPER\n', 1)[1].split('\nFRONTEND_WRAPPER', 1)[0]
assert wrapper_body(repo / 'bin/cluster-refresh') == wrapper_body(repo / 'bin/cluster-up')
PY
  [ "${status}" -eq 0 ]
}
