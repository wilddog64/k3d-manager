#!/usr/bin/env bash
# scripts/plugins/acg.sh — stub: delegates to lib-acg subtree

_acg_stub_load() {
  local _k3dm_root
  if [[ -n "${BATS_TEST_DIRNAME:-}" ]]; then
    _k3dm_root="$(cd -P "${BATS_TEST_DIRNAME}/../../.." >/dev/null 2>&1 && pwd)"
  elif _k3dm_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    :
  else
    _k3dm_root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 && pwd)"
  fi

  # shellcheck source=/dev/null
  source "${_k3dm_root}/scripts/plugins/aws.sh"
  # shellcheck source=/dev/null
  source "${_k3dm_root}/scripts/lib/acg/scripts/plugins/acg.sh"
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

function acg_import_credentials()   { __acg_stub_acg_import_credentials "$@"; }
function _acg_write_credentials()    { __acg_stub__acg_write_credentials "$@"; }
function acg_get_credentials()      { __acg_stub_acg_get_credentials "$@"; }
function acg_provision()            { __acg_stub_acg_provision "$@"; }
function acg_status()               { __acg_stub_acg_status "$@"; }
function acg_extend_playwright()    { __acg_stub_acg_extend_playwright "$@"; }
function _acg_extend_playwright()   { __acg_stub__acg_extend_playwright "$@"; }
function acg_extend()               { __acg_stub_acg_extend "$@"; }
function acg_watch()                { __acg_stub_acg_watch "$@"; }
function acg_watch_start()         { __acg_stub_acg_watch_start "$@"; }
function acg_watch_stop()          { __acg_stub_acg_watch_stop "$@"; }
function acg_chrome_cdp_install()   { __acg_stub_acg_chrome_cdp_install "$@"; }
function acg_chrome_cdp_uninstall() { __acg_stub_acg_chrome_cdp_uninstall "$@"; }
function acg_teardown()             { __acg_stub_acg_teardown "$@"; }
