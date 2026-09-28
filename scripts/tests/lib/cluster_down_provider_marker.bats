#!/usr/bin/env bats
# scripts/tests/lib/cluster_down_provider_marker.bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "cluster-down no longer removes the legacy active-provider path" {
  run grep -c 'rm -f.*active-provider"' "${REPO_ROOT}/bin/cluster-down"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "0" ]]
}

@test "cluster-down unrecords the current provider" {
  run grep -F '_acg_unrecord_provider' "${REPO_ROOT}/bin/cluster-down"
  [[ "${status}" -eq 0 ]]
  run grep -F '"${_cluster_provider}"' "${REPO_ROOT}/bin/cluster-down"
  [[ "${status}" -eq 0 ]]
}
