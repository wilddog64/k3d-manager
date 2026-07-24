#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
}

_mixed_fixture() {
  cat <<'EOF'
{"items":[
 {"metadata":{"name":"trivy-operator"},"spec":{"sources":[
   {"ref":"values","repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"k3d-manager-v1.18.0"},
   {"chart":"trivy-operator","targetRevision":"0.34.0"}]}},
 {"metadata":{"name":"acg-trivy-operator"},"spec":{"sources":[
   {"ref":"values","repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"k3d-manager-v1.16.0"},
   {"chart":"trivy-operator","targetRevision":"0.34.0"}]}}
]}
EOF
}

_clean_fixture() {
  cat <<'EOF'
{"items":[
 {"metadata":{"name":"trivy-operator"},"spec":{"sources":[
   {"ref":"values","repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"k3d-manager-v1.18.0"},
   {"chart":"trivy-operator","targetRevision":"0.34.0"}]}}
]}
EOF
}

@test "argocd values branch: reports drift and returns 1 when an Application is stale" {
  _kubectl() { _mixed_fixture; }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"acg-trivy-operator"* ]]
  [[ "${output}" == *"k3d-manager-v1.16.0"* ]]
}

@test "argocd values branch: the up-to-date Application is not reported as drifted" {
  _kubectl() { _mixed_fixture; }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 1 ]
  [[ "${output}" != *"  trivy-operator k3d-manager-v1.18.0"* ]]
}

@test "argocd values branch: returns 0 when every Application matches" {
  _kubectl() { _clean_fixture; }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"All Applications reference values branch k3d-manager-v1.18.0"* ]]
}

@test "argocd values branch: returns 2 instead of a false green when Applications cannot be read" {
  _kubectl() { return 1; }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Could not read Applications"* ]]
}

@test "argocd values branch: chart sources are ignored, only the values ref is checked" {
  _kubectl() { _clean_fixture; }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"checked 1 values references"* ]]
}
