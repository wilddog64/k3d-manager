#!/usr/bin/env bats

VALUES="${BATS_TEST_DIRNAME}/../../etc/helm/observability/kube-prometheus-stack-values.yaml"

valid_image() {
  local tag sha
  tag="$(yq -r '.grafana.image.tag' "$1")" || return 1
  sha="$(yq -r '.grafana.image.sha' "$1")" || return 1
  [[ "${tag}" == "12.4.15" && "${sha}" =~ ^[0-9a-f]{64}$ ]]
}

@test "hub Grafana uses the approved image tag" {
  valid_image "${VALUES}"
  run yq -r '.grafana.image.tag' "${VALUES}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "12.4.15" ]
}

@test "hub Grafana uses the approved image digest" {
  run yq -r '.grafana.image.sha' "${VALUES}"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ ^[0-9a-f]{64}$ ]]
  [ "${output}" = "2894082f6cf7081aefdc1389265c04000812309208c190d75e8c65f7a30e4b7e" ]
}

@test "image validation rejects missing and unsafe tags and malformed digests" {
  local fixture="${BATS_TEST_TMPDIR}/values.yaml" tag sha
  [[ "${fixture}" == "${BATS_TEST_TMPDIR}/values.yaml" ]]
  sha="2894082f6cf7081aefdc1389265c04000812309208c190d75e8c65f7a30e4b7e"
  printf 'grafana:\n  image:\n    tag: "12.4.15"\n    sha: "%s"\n' "${sha}" > "${fixture}"
  valid_image "${fixture}"
  for tag in missing '' latest 11.4.0; do
    if [ "${tag}" = missing ]; then
      printf 'grafana:\n  image:\n    sha: "%s"\n' "${sha}" > "${fixture}"
    else
      printf 'grafana:\n  image:\n    tag: "%s"\n    sha: "%s"\n' "${tag}" "${sha}" > "${fixture}"
    fi
    run valid_image "${fixture}"
    [ "${status}" -ne 0 ]
  done
  for sha in missing '' abc 2894082F6cf7081aefdc1389265c04000812309208c190d75e8c65f7a30e4b7e; do
    if [ "${sha}" = missing ]; then
      printf 'grafana:\n  image:\n    tag: "12.4.15"\n' > "${fixture}"
    else
      printf 'grafana:\n  image:\n    tag: "12.4.15"\n    sha: "%s"\n' "${sha}" > "${fixture}"
    fi
    run valid_image "${fixture}"
    [ "${status}" -ne 0 ]
  done
}
