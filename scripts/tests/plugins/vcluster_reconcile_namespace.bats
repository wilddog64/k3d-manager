#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  export VCLUSTER_NAMESPACE="vclusters"
  export _VCLUSTER_BIN="vcluster"
  export VCLUSTER_CALLS="${BATS_TEST_TMPDIR}/calls.log"
  : > "$VCLUSTER_CALLS"
  source "${BATS_TEST_DIRNAME}/../../plugins/vcluster.sh"
  _VCLUSTER_BIN="vcluster"
  _warn() { :; }
  _run_command() { _vcluster_test_run_command "$@"; }
}

_vcluster_test_run_command() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-exit|--quiet) shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done

  if [[ "${1:-}" == "${_VCLUSTER_BIN}" && "${2:-}" == "list" ]]; then
    if [[ "$*" != *"--output json"* ]]; then
      printf '\033[32mNAME\033[0m   NAMESPACE\n---+---+--------'
      return 0
    fi
    printf '%s' "${VCLUSTER_LIST_OUTPUT:-}"
    return 0
  fi

  printf '%s\n' "$*" >> "$VCLUSTER_CALLS"
  if [[ "${VCLUSTER_DELETE_FAIL:-0}" == "1" && "${1:-}" == "${_VCLUSTER_BIN}" && "${2:-}" == "delete" ]]; then
    return 1
  fi
  return 0
}

@test "reconcile: deletes only the non-kept JSON cluster" {
  VCLUSTER_LIST_OUTPUT='[{"Name":"keep-me"},{"Name":"orphan-a"}]'
  _vcluster_reconcile_namespace keep-me

  [ "$(grep -c '^vcluster delete orphan-a -n vclusters --wait$' "$VCLUSTER_CALLS")" -eq 1 ]
  ! grep -q 'keep-me' "$VCLUSTER_CALLS"
}

@test "reconcile: empty JSON list does not delete" {
  VCLUSTER_LIST_OUTPUT='[]'
  _vcluster_reconcile_namespace keep-me

  [ ! -s "$VCLUSTER_CALLS" ]
}

@test "reconcile: colored table output does not delete" {
  VCLUSTER_LIST_OUTPUT=$'\033[32mNAME\033[0m   NAMESPACE\n---+---+--------'
  run _vcluster_reconcile_namespace keep-me

  [ "$status" -eq 0 ]
  [ ! -s "$VCLUSTER_CALLS" ]
}

@test "reconcile: delete failure falls back to helm uninstall" {
  VCLUSTER_LIST_OUTPUT='[{"Name":"orphan-a"}]'
  VCLUSTER_DELETE_FAIL=1 _vcluster_reconcile_namespace keep-me

  grep -Fxq 'vcluster delete orphan-a -n vclusters --wait' "$VCLUSTER_CALLS"
  grep -Fxq 'helm -n vclusters uninstall orphan-a --wait' "$VCLUSTER_CALLS"
}
