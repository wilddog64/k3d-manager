#!/usr/bin/env bats

@test "fixed browser listener configuration accepts defaults and rejects unsupported custom paths" {
  local helper="${BATS_TEST_DIRNAME}/../../lib/acg_browser_listeners.sh"
  local state="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${state}"
  run env LISTENER_STATE="${state}" bash -c '
    _warn() { printf "%s\n" "$*"; }
    _info() { :; }
    source "$1"
    _ACG_STATE_DIR="$LISTENER_STATE"
    _acg_validate_browser_listener_config "$LISTENER_STATE"
  ' bash "${helper}"
  [ "${status}" -eq 0 ]

  run env LISTENER_STATE="${state}" ARGOCD_BROWSER_HOST="argocd.example.test" \
      ARGOCD_BROWSER_PORT=8443 ARGOCD_BROWSER_LISTENER_WAIT_TIMEOUT=7 \
      ARGOCD_BROWSER_LISTENER_STARTUP_TIMEOUT=30 bash -c '
    _warn() { printf "%s\n" "$*"; }
    _info() { :; }
    source "$1"
    _ACG_STATE_DIR="$LISTENER_STATE"
    _acg_validate_browser_listener_config "$LISTENER_STATE"
  ' bash "${helper}"
  [ "${status}" -eq 0 ]

  run env LISTENER_STATE="${state}" ARGOCD_BROWSER_LISTENER_LOG="${BATS_TEST_TMPDIR}/custom.log" bash -c '
    _warn() { printf "%s\n" "$*"; }
    _info() { :; }
    source "$1"
    _ACG_STATE_DIR="$LISTENER_STATE"
    _acg_validate_browser_listener_config "$LISTENER_STATE"
  ' bash "${helper}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ARGOCD_BROWSER_LISTENER_LOG"*"unsupported"* ]]
  [[ "${output}" == *"${state}/logs/argocd-browser-https.log"* ]]
}

@test "fixed listener configuration rejects custom labels and Keycloak plist paths" {
  local helper="${BATS_TEST_DIRNAME}/../../lib/acg_browser_listeners.sh"
  local state="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${state}"
  for variable in ARGOCD_BROWSER_LISTENER_LABEL ARGOCD_BROWSER_LISTENER_PLIST \
      ARGOCD_BROWSER_LISTENER_WRAPPER ARGOCD_BROWSER_LISTENER_LAUNCHCTL_LOG \
      ARGOCD_BROWSER_LISTENER_STARTUP_TIMEOUT KEYCLOAK_BROWSER_LISTENER_LABEL \
      KEYCLOAK_BROWSER_LISTENER_PLIST KEYCLOAK_BROWSER_LISTENER_WRAPPER \
      KEYCLOAK_BROWSER_LISTENER_LOG KEYCLOAK_BROWSER_LISTENER_LAUNCHCTL_LOG \
      FRONTEND_BROWSER_LISTENER_PLIST; do
    run env LISTENER_STATE="${state}" "${variable}=custom" bash -c '
      _warn() { printf "%s\n" "$*"; }
      _info() { :; }
      source "$1"
      _ACG_STATE_DIR="$LISTENER_STATE"
      _acg_validate_browser_listener_config "$LISTENER_STATE"
    ' bash "${helper}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"${variable}"*"unsupported"* ]]
  done
}

@test "cluster-up still passes ARGOCD_BROWSER_LISTENER_WAIT_TIMEOUT to health readiness" {
  run grep -F '_argocd_wait_for_browser_https "${_argocd_browser_log}" "${ARGOCD_BROWSER_LISTENER_WAIT_TIMEOUT:-120}"' \
    "${BATS_TEST_DIRNAME}/../../../bin/cluster-up"
  [ "${status}" -eq 0 ]
  run grep -F ': "${ARGOCD_BROWSER_LISTENER_WAIT_TIMEOUT:=30}"' \
    "${BATS_TEST_DIRNAME}/../../../scripts/plugins/argocd.sh"
  [ "${status}" -eq 0 ]
}

@test "fixed listener configuration rejects unsafe host overrides" {
  local helper="${BATS_TEST_DIRNAME}/../../lib/acg_browser_listeners.sh"
  local state="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${state}"
  for invalid_host in 'bad host' 'a..b' '-label.example' 'label-.example' \
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.example'; do
    run env LISTENER_STATE="${state}" ARGOCD_BROWSER_HOST="${invalid_host}" bash -c '
      _warn() { printf "%s\n" "$*"; }
      _info() { :; }
      source "$1"
      _ACG_STATE_DIR="$LISTENER_STATE"
      _acg_validate_browser_listener_config "$LISTENER_STATE"
    ' bash "${helper}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"unsafe ARGOCD_BROWSER_HOST"* ]]
  done
}

@test "loopback listener helper installs alias first and short-circuits frontend on alias failure" {
  local helper="${BATS_TEST_DIRNAME}/../../lib/acg_browser_listeners.sh"
  local calls="${BATS_TEST_TMPDIR}/listener-order.calls"
  run env CALLS="${calls}" bash -c '
    source "$1"
    install_alias() { printf "alias %s\n" "$1" >> "$CALLS"; }
    install_frontend() { printf "frontend %s\n" "$1" >> "$CALLS"; }
    _acg_install_loopback_frontend_listener loopback frontend install_alias install_frontend
  ' bash "${helper}"
  [ "${status}" -eq 0 ]
  [ "$(cat "${calls}")" = $'alias loopback\nfrontend frontend' ]

  : > "${calls}"
  run env CALLS="${calls}" bash -c '
    source "$1"
    install_alias() { printf "alias %s\n" "$1" >> "$CALLS"; return 1; }
    install_frontend() { printf "frontend %s\n" "$1" >> "$CALLS"; }
    _acg_install_loopback_frontend_listener loopback frontend install_alias install_frontend
  ' bash "${helper}"
  [ "${status}" -ne 0 ]
  [ "$(cat "${calls}")" = "alias loopback" ]
}

@test "cluster-up and refresh production installers use alias-first callbacks" {
  local up="${BATS_TEST_DIRNAME}/../../../bin/cluster-up"
  local refresh="${BATS_TEST_DIRNAME}/../../../bin/cluster-refresh"
  local up_callbacks="${BATS_TEST_TMPDIR}/up-listener-callbacks.sh"
  local refresh_callback="${BATS_TEST_TMPDIR}/refresh-listener-callback.sh"
  sed -n '/^function _acg_install_supervised_listener()/,/^}/p; /^function _acg_install_frontend_http_listener()/,/^}/p' "${up}" > "${up_callbacks}"
  sed -n '/^_cluster_refresh_stdin_is_tty()/,/^}/p; /^_acg_refresh_install_listener()/,/^}/p' "${refresh}" > "${refresh_callback}"
  for callback_file in "${up_callbacks}" "${refresh_callback}"; do
    local installers="_acg_install_supervised_listener _acg_install_frontend_http_listener"
    [[ "${callback_file}" == "${refresh_callback}" ]] && installers="_acg_refresh_install_listener _acg_refresh_install_listener"
    local calls="${BATS_TEST_TMPDIR}/production-calls"
    : > "${calls}"
    run env CALLBACK_FILE="${callback_file}" INSTALLERS="${installers}" CALLS="${calls}" bash -c '
      source "$1"
      source "$CALLBACK_FILE"
      _run_command() { printf "%s\n" "$*" >> "$CALLS"; [[ "$*" != *sandbox-loopback-alias* ]]; }
      _acg_install_browser_listener() { printf "frontend %s\n" "$1" >> "$CALLS"; }
      read -r alias_installer frontend_installer <<< "$INSTALLERS"
      _acg_install_loopback_frontend_listener sandbox-loopback-alias frontend-http \
        "$alias_installer" "$frontend_installer"
    ' bash "${BATS_TEST_DIRNAME}/../../lib/acg_browser_listeners.sh"
    [ "${status}" -ne 0 ]
    run grep -F 'frontend frontend-http' "${calls}"
    [ "${status}" -eq 1 ]
  done
}

@test "Hostinger production installer stops before frontend when alias install fails" {
  local provider="${BATS_TEST_DIRNAME}/../../lib/providers/k3s-hostinger.sh"
  local snippet="${BATS_TEST_TMPDIR}/hostinger-listener-install.sh"
  local calls="${BATS_TEST_TMPDIR}/hostinger-listener-calls"
  sed -n '/^function _hostinger_install_fixed_browser_listeners()/,/^}/p; /^function _hostinger_install_one_fixed_listener()/,/^}/p' \
    "${provider}" > "${snippet}"
  for fail_alias in 0 1; do
    : > "${calls}"
    run env PROVIDER_SNIPPET="${snippet}" CALLS="${calls}" FAIL_ALIAS="${fail_alias}" bash -c '
      _ACG_STATE_DIR="$PWD/state"
      CLUSTER_PROVIDER=k3s-hostinger
      ARGOCD_BROWSER_TLS_DIR="$PWD/tls"
      _warn() { :; }
      _info() { :; }
      _acg_validate_browser_listener_config() { :; }
      _acg_install_loopback_frontend_listener() {
        local alias="$1" frontend="$2" alias_fn="$3" frontend_fn="$4"
        "$alias_fn" "$alias" && "$frontend_fn" "$frontend"
      }
      _run_command() {
        printf "%s\n" "$*" >> "$CALLS"
        [[ "${FAIL_ALIAS}" != 1 || "$*" != *hostinger-loopback-alias* ]]
      }
      source "$PROVIDER_SNIPPET"
      _hostinger_install_fixed_browser_listeners
    ' bash
    if [[ "${fail_alias}" == 1 ]]; then
      [ "${status}" -ne 0 ]
      run grep -F 'hostinger-frontend-http' "${calls}"
      [ "${status}" -eq 1 ]
    else
      [ "${status}" -eq 0 ]
      local alias_line frontend_line
      alias_line="$(grep -nF 'hostinger-loopback-alias' "${calls}" | cut -d: -f1)"
      frontend_line="$(grep -nF 'hostinger-frontend-http' "${calls}" | cut -d: -f1)"
      [ "${alias_line}" -lt "${frontend_line}" ]
    fi
  done
}

@test "cluster-up and refresh install the loopback alias before the frontend listener" {
  run awk '
    /_acg_install_loopback_frontend_listener sandbox-loopback-alias frontend-http/ { found = 1 }
    END { exit !found }
  ' "${BATS_TEST_DIRNAME}/../../../bin/cluster-up"
  [ "${status}" -eq 0 ]
  run awk '
    /_acg_install_loopback_frontend_listener sandbox-loopback-alias frontend-http/ { found = 1 }
    END { exit !found }
  ' "${BATS_TEST_DIRNAME}/../../../bin/cluster-refresh"
  [ "${status}" -eq 0 ]
}

@test "cluster-up validates listener options before changing hosts, only on macOS" {
  local up="${BATS_TEST_DIRNAME}/../../../bin/cluster-up"
  local check_line hosts_line
  check_line="$(grep -nF '_acg_validate_browser_listener_config "${_ACG_STATE_DIR}" || exit 1' "${up}" | head -1 | cut -d: -f1)"
  hosts_line="$(grep -nF 'Updating /etc/hosts entries before starting the ArgoCD browser HTTPS listener' "${up}" | head -1 | cut -d: -f1)"
  [ -n "${check_line}" ] && [ -n "${hosts_line}" ]
  [ "${check_line}" -lt "${hosts_line}" ]
  grep -B1 -F '_acg_validate_browser_listener_config "${_ACG_STATE_DIR}" || exit 1' "${up}" | grep -q 'if _is_mac; then'
}

@test "cluster-up rejects invalid macOS listener configuration before bootstrap or provisioning" {
  local repo="${BATS_TEST_TMPDIR}/fake-repo" home="${BATS_TEST_TMPDIR}/home" stub_bin="${BATS_TEST_TMPDIR}/bin" mode
  mkdir -p "${repo}/bin" "${repo}/scripts/lib" "${repo}/scripts/plugins" "${home}" "${stub_bin}"
  cp "${CLUSTER_UP_FILE:-bin/cluster-up}" "${repo}/bin/cluster-up"
  cp scripts/lib/acg_browser_listeners.sh "${repo}/scripts/lib/acg_browser_listeners.sh"
  cmp -s "${CLUSTER_UP_FILE:-bin/cluster-up}" "${repo}/bin/cluster-up"
  cat > "${repo}/bin/k3dm-require-role" <<'SH'
#!/bin/bash
[[ "$1" == hub ]]
SH
  chmod +x "${repo}/bin/k3dm-require-role"
  for file in ssh_config_guard.sh deployment_metrics.sh system_overrides.sh cloudflared_keychain.sh \
      cloudflared_render.sh cloudflare_tunnel.sh core.sh hub_host_ip.sh; do
    : > "${repo}/scripts/lib/${file}"
  done
  for file in gemini.sh acg.sh tunnel.sh argocd.sh keycloak.sh shopping_cart.sh hub_recovery.sh; do
    : > "${repo}/scripts/plugins/${file}"
  done
  cat > "${repo}/scripts/lib/system.sh" <<'SH'
_is_mac() { [[ "$TEST_OS" == Darwin ]]; }
_dry_run_active() { return 1; }
_warn() { printf '%s\n' "$*" >&2; }
_info() { :; }
SH
  cat > "${repo}/scripts/lib/provider.sh" <<'SH'
_acg_normalize_provider() { printf '%s\n' "$1"; }
_acg_provider_state_dir() { printf '%s/state/%s\n' "$HOME" "$1"; }
SH
  cat > "${stub_bin}/node" <<'SH'
#!/bin/bash
printf 'node\n' >> "$TEST_CALLS"
exit 1
SH
  cat > "${stub_bin}/npm" <<'SH'
#!/bin/bash
printf 'npm\n' >> "$TEST_CALLS"
exit 99
SH
  cat > "${stub_bin}/aws" <<'SH'
#!/bin/bash
printf 'aws\n' >> "$TEST_CALLS"
exit 99
SH
  chmod +x "${stub_bin}/node" "${stub_bin}/npm" "${stub_bin}/aws"
  for mode in invalid valid non_darwin; do
    local calls="${BATS_TEST_TMPDIR}/${mode}.calls" test_os=Darwin listener_label=custom
    : > "${calls}"
    [[ "${mode}" == valid ]] && listener_label=com.k3d-manager.argocd-browser-https
    [[ "${mode}" == non_darwin ]] && test_os=Linux
    run env HOME="${home}" PATH="${stub_bin}:/usr/bin:/bin" TEST_OS="${test_os}" TEST_CALLS="${calls}" \
      ARGOCD_BROWSER_LISTENER_LABEL="${listener_label}" CLUSTER_PROVIDER=k3s-aws bash "${repo}/bin/cluster-up"
    [ "${status}" -ne 0 ]
    if [[ "${mode}" == invalid ]]; then
      [[ "${output}" == *"ARGOCD_BROWSER_LISTENER_LABEL"*"unsupported"* ]]
      [ ! -s "${calls}" ]
      [ ! -e "${home}/state" ]
      [ ! -e "${home}/.local" ]
    else
      [ "$(cat "${calls}")" = $'node\nnpm' ]
      [ ! -e "${home}/state" ]
      [ ! -e "${home}/.local" ]
    fi
  done
}

@test "Hostinger installs its loopback alias before its frontend listener" {
  run awk '
    /_acg_install_loopback_frontend_listener hostinger-loopback-alias hostinger-frontend-http/ { found = 1 }
    END { exit !found }
  ' "${BATS_TEST_DIRNAME}/../../lib/providers/k3s-hostinger.sh"
  [ "${status}" -eq 0 ]
}
