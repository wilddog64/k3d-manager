#!/usr/bin/env bash
# scripts/plugins/gcp.sh — stub: delegates to lib-acg subtree

_gcp_stub_load() {
  local _k3dm_root
  if [[ -n "${BATS_TEST_DIRNAME:-}" ]]; then
    _k3dm_root="$(cd -P "${BATS_TEST_DIRNAME}/../../.." >/dev/null 2>&1 && pwd)"
  elif _k3dm_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    :
  else
    _k3dm_root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 && pwd)"
  fi

  # shellcheck source=/dev/null
  source "${_k3dm_root}/scripts/lib/acg/scripts/plugins/gcp.sh"
}

_gcp_stub_alias_function() {
  local source_name="$1"
  local alias_name="$2"
  eval "$(declare -f "${source_name}" | sed "1s/^${source_name}[[:space:]]*()/${alias_name}()/" )"
}

_gcp_stub_load
_gcp_stub_alias_function gcp_get_credentials __gcp_stub_gcp_get_credentials
_gcp_stub_alias_function gcp_login __gcp_stub_gcp_login
_gcp_stub_alias_function gcp_revoke __gcp_stub_gcp_revoke

function gcp_get_credentials() { __gcp_stub_gcp_get_credentials "$@"; }
function gcp_login()           { __gcp_stub_gcp_login "$@"; }
function gcp_revoke()          { __gcp_stub_gcp_revoke "$@"; }
