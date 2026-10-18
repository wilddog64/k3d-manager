#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export SCRIPT_DIR
  source "${SCRIPT_DIR}/lib/system.sh"
  source "${SCRIPT_DIR}/lib/provider.sh"
  source "${SCRIPT_DIR}/lib/providers/k3s-hostinger.sh"
  WATCHDOG_LOG="${BATS_TEST_TMPDIR}/watchdog.log"
  : > "${WATCHDOG_LOG}"
  _HOSTINGER_KUBE_CONTEXT=ubuntu-hostinger
  _info() { :; }
}

@test "hostinger watchdog: skips when Vault StatefulSet is absent" {
  kubectl() { return 1; }
  vault_install_unseal_watchdog() { printf 'called\n' >> "${WATCHDOG_LOG}"; }

  run _hostinger_ensure_vault_unseal_watchdog
  [ "$status" -eq 0 ]
  [ ! -s "${WATCHDOG_LOG}" ]
}

@test "hostinger watchdog: installs for an existing Vault StatefulSet" {
  kubectl() { return 0; }
  vault_install_unseal_watchdog() { printf '%s %s\n' "$1" "$2" >> "${WATCHDOG_LOG}"; }

  run _hostinger_ensure_vault_unseal_watchdog
  [ "$status" -eq 0 ]
  grep -qx 'secrets ubuntu-hostinger' "${WATCHDOG_LOG}"
}

@test "hostinger watchdog: reports installer failure" {
  kubectl() { return 0; }
  vault_install_unseal_watchdog() { return 1; }

  run _hostinger_ensure_vault_unseal_watchdog
  [ "$status" -eq 1 ]
  [[ "$output" == *"Vault unseal watchdog install failed"* ]]
}

@test "hostinger refresh: calls watchdog after edge refresh" {
  run awk '
    /_hostinger_refresh_access_layer \|\| return 1/ { access = NR }
    /_hostinger_ensure_vault_unseal_watchdog \|\| return 1/ { watchdog = NR }
    END { exit !(access && watchdog && watchdog > access) }
  ' "${SCRIPT_DIR}/lib/providers/k3s-hostinger.sh"
  [ "$status" -eq 0 ]
}
