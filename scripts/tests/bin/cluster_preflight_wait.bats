#!/usr/bin/env bats

setup_wait_test() {
  local script_path="${PREFLIGHT_SCRIPT:-bin/cluster-preflight}"
  WAIT_FN="$(sed -n '/^function _cluster_preflight_wait_for_apps()/,/^}/p' "${script_path}")"
}

run_wait_test() {
  local wait_mode="$1"
  local timeout="$2"
  run env WAIT_MODE="${wait_mode}" WAIT_TIMEOUT="${timeout}" WAIT_FN="${WAIT_FN}" \
    bash -c '
set -euo pipefail
_kubectl() {
  if [[ "$*" == *"applications.argoproj.io"* ]]; then
    printf "%s" "{\"items\":[{\"metadata\":{\"name\":\"t1-preflight-x\"},\"spec\":{\"destination\":{\"name\":\"t1\"}}}]}"
  elif [[ "${WAIT_MODE}" == ready ]]; then
    printf "%s" "Synced Healthy"
  else
    printf "%s" ""
  fi
}
_info() { echo "$*"; }
_err() { echo "$*"; }
sleep() { :; }
eval "${WAIT_FN}"
ARGOCD_NAMESPACE=cicd VCLUSTER_NAMESPACE=vcluster \
  _cluster_preflight_wait_for_apps t1 "${WAIT_TIMEOUT}"
'
}

@test "preflight wait: synced and healthy app succeeds" {
  setup_wait_test
  run_wait_test ready 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"are Synced/Healthy"* ]]
}

@test "preflight wait: empty app status reaches timeout" {
  setup_wait_test
  run_wait_test empty 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"Timed out waiting"* ]]
}
