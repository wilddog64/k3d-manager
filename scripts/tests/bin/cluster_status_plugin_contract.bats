#!/usr/bin/env bats

# bin/cluster-status --full sources scripts/plugins/observability.sh directly rather than going
# through the dispatcher, so it must supply the two layout variables the dispatcher exports
# (scripts/k3d-manager:64-65). Without them the plugin aborts at source time under `set -u`.
# Spec: docs/bugs/2026-09-20-cluster-status-full-unbound-plugins-dir.md

@test "cluster-status defines the plugin layout contract before sourcing a plugin" {
  run grep -nE '^SCRIPT_DIR="\$\{REPO_ROOT\}/scripts"' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nE '^PLUGINS_DIR="\$\{SCRIPT_DIR\}/plugins"' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status sets PLUGINS_DIR before it sources the observability plugin" {
  local _assign _source
  _assign=$(grep -nE '^PLUGINS_DIR=' bin/cluster-status | head -1 | cut -d: -f1)
  _source=$(grep -nE '^source .*plugins/observability\.sh' bin/cluster-status | head -1 | cut -d: -f1)
  [ -n "${_assign}" ]
  [ -n "${_source}" ]
  [ "${_assign}" -lt "${_source}" ]
}

@test "observability plugin sources cleanly under set -u given the layout contract" {
  run env -u PLUGINS_DIR bash -u -c '
    SCRIPT_DIR="${PWD}/scripts"
    PLUGINS_DIR="${SCRIPT_DIR}/plugins"
    source scripts/plugins/observability.sh
    declare -f deploy_observability >/dev/null'
  [ "$status" -eq 0 ]
}
