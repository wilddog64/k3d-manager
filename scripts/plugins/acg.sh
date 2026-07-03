#!/usr/bin/env bash
# scripts/plugins/acg.sh — stub: delegates to absorbed foundation ACG module

_acg_stub_load() {
  local _k3dm_root
  if [[ -n "${BATS_TEST_DIRNAME:-}" ]]; then
    _k3dm_root="$(cd -P "${BATS_TEST_DIRNAME}/../../.." >/dev/null 2>&1 && pwd)"
  elif _k3dm_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    :
  else
    _k3dm_root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 && pwd)"
  fi

  export ACG_CLUSTER_TEMPLATE="${ACG_CLUSTER_TEMPLATE:-${_k3dm_root}/scripts/etc/acg-cluster.yaml}"
  # shellcheck source=/dev/null
  source "${_k3dm_root}/scripts/plugins/aws.sh"
  # shellcheck source=/dev/null
  source "${_k3dm_root}/scripts/lib/foundation/scripts/lib/acg/acg.sh"
  # shellcheck source=/dev/null
  source "${_k3dm_root}/scripts/lib/foundation/scripts/lib/acg/gcp.sh"
}

_acg_stub_alias_function() {
  local source_name="$1"
  local alias_name="$2"
  eval "$(declare -f "${source_name}" | sed "1s/^${source_name}[[:space:]]*()/${alias_name}()/" )"
}

_acg_stub_load
_acg_stub_alias_function acg_import_credentials __acg_stub_acg_import_credentials
_acg_stub_alias_function _acg_write_credentials __acg_stub__acg_write_credentials
_acg_stub_alias_function acg_get_credentials __acg_stub_acg_get_credentials
_acg_stub_alias_function acg_provision __acg_stub_acg_provision
_acg_stub_alias_function acg_status __acg_stub_acg_status
_acg_stub_alias_function acg_extend_playwright __acg_stub_acg_extend_playwright
_acg_stub_alias_function _acg_extend_playwright __acg_stub__acg_extend_playwright
_acg_stub_alias_function acg_extend __acg_stub_acg_extend
_acg_stub_alias_function acg_watch __acg_stub_acg_watch
_acg_stub_alias_function acg_watch_start __acg_stub_acg_watch_start
_acg_stub_alias_function acg_watch_stop __acg_stub_acg_watch_stop
_acg_stub_alias_function acg_chrome_cdp_install __acg_stub_acg_chrome_cdp_install
_acg_stub_alias_function acg_chrome_cdp_uninstall __acg_stub_acg_chrome_cdp_uninstall
_acg_stub_alias_function acg_teardown __acg_stub_acg_teardown

_acg_watch_retarget_logs() {
  local run_dir plist_path out_path err_path label
  run_dir="${K3DM_RUN_DIR:-${HOME}/.local/share/k3d-manager/run}"
  plist_path="${_ACG_WATCH_PLIST_PATH:-${HOME}/Library/LaunchAgents/com.k3d-manager.acg-watch.plist}"
  label="${_ACG_WATCH_LAUNCHD_LABEL:-com.k3d-manager.acg-watch}"
  out_path="${run_dir}/k3d-manager-acg-watch.out"
  err_path="${run_dir}/k3d-manager-acg-watch.err"

  [[ -f "${plist_path}" ]] || return 0
  mkdir -p "${run_dir}"

  python3 - "${plist_path}" "${out_path}" "${err_path}" <<'PY'
import plistlib
import sys
from pathlib import Path

plist_path = Path(sys.argv[1])
out_path = sys.argv[2]
err_path = sys.argv[3]

with plist_path.open('rb') as handle:
    data = plistlib.load(handle)

data["StandardOutPath"] = out_path
data["StandardErrorPath"] = err_path

with plist_path.open('wb') as handle:
    plistlib.dump(data, handle, sort_keys=False)
PY

  if command -v launchctl >/dev/null 2>&1 && launchctl list "${label}" >/dev/null 2>&1; then
    launchctl unload "${plist_path}" 2>/dev/null || true
    launchctl load "${plist_path}" 2>/dev/null || true
  fi
}

function acg_import_credentials()   { __acg_stub_acg_import_credentials "$@"; }
function _acg_write_credentials()    { __acg_stub__acg_write_credentials "$@"; }
function acg_get_credentials()      { __acg_stub_acg_get_credentials "$@"; }
function acg_provision()            { __acg_stub_acg_provision "$@"; }
function acg_status()               { __acg_stub_acg_status "$@"; }
function acg_extend_playwright()    { __acg_stub_acg_extend_playwright "$@"; }
function _acg_extend_playwright()   { __acg_stub__acg_extend_playwright "$@"; }
function acg_extend()               { __acg_stub_acg_extend "$@"; }
function acg_watch()                { __acg_stub_acg_watch "$@"; }
function acg_watch_start()          {
  __acg_stub_acg_watch_start "$@"
  _acg_watch_retarget_logs
  _info "[acg] Sandbox watcher logs redirected to ${K3DM_RUN_DIR:-${HOME}/.local/share/k3d-manager/run}/k3d-manager-acg-watch.err"
}
function acg_watch_stop()          { __acg_stub_acg_watch_stop "$@"; }
function acg_chrome_cdp_install()   { __acg_stub_acg_chrome_cdp_install "$@"; }
function acg_chrome_cdp_uninstall() { __acg_stub_acg_chrome_cdp_uninstall "$@"; }
function acg_teardown()             { __acg_stub_acg_teardown "$@"; }
