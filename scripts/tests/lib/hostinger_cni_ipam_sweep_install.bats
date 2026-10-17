#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export SCRIPT_DIR
  source "${SCRIPT_DIR}/lib/system.sh"
  source "${SCRIPT_DIR}/lib/provider.sh"
  source "${SCRIPT_DIR}/lib/providers/k3s-hostinger.sh"
  _HOSTINGER_SSH_USER=ubuntu
  _HOSTINGER_SSH_KEY=/tmp/key
  _HOSTINGER_KUBE_CONTEXT=ubuntu-hostinger
  _info() { :; }
  _hostinger_require_host() { printf 'hostinger.example\n'; }
  _dry_run_active() { [[ "${DRY_RUN:-0}" == 1 ]]; }
  INSTALL_LOG="${BATS_TEST_TMPDIR}/install.log"
  : > "${INSTALL_LOG}"
  _run_command() { shift; "$@"; }
  ssh() {
    printf 'ssh %s\n' "$*" >> "${INSTALL_LOG}"
    if [[ "$*" == *"mktemp -d"* ]]; then printf '/tmp/k3dm-cni-ipam.ABC123\n'; fi
  }
  scp() { printf 'scp %s\n' "$*" >> "${INSTALL_LOG}"; }
}

_run_command() {
  shift
  "$@"
}

@test "cni ipam install: enables the timer" {
  run _hostinger_ensure_cni_ipam_sweep
  [ "$status" -eq 0 ]
  grep -q 'systemctl enable --now k3dm-cni-ipam-sweep.timer' "${INSTALL_LOG}"
}

@test "cni ipam install: rejects an unexpected staging directory" {
  _run_command() {
    shift
    if [[ "$1" == ssh ]]; then printf '/tmp/not-k3dm\n'; fi
  }
  run _hostinger_ensure_cni_ipam_sweep
  [ "$status" -eq 1 ]
  ! grep -q 'enable --now' "${INSTALL_LOG}"
}

@test "cni ipam install: dry run sends no remote command" {
  export DRY_RUN=1
  run _hostinger_ensure_cni_ipam_sweep
  [ "$status" -eq 0 ]
  [ ! -s "${INSTALL_LOG}" ]
}

@test "cni ipam install: both provider call sites follow the spec" {
  run awk '
    index($0, "_hostinger_ensure_vault_unseal_watchdog || return 1") { watchdog = NR }
    index($0, "_hostinger_ensure_cni_ipam_sweep || return 1") { sweep[++count] = NR }
    END { exit !(count == 2 && sweep[1] < watchdog && sweep[2] > watchdog) }
  ' "${SCRIPT_DIR}/lib/providers/k3s-hostinger.sh"
  [ "$status" -eq 0 ]
}
