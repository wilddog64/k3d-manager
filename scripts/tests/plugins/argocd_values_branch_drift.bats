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

@test "argocd values branch: chart sources without the k3d-manager repo are ignored" {
  _kubectl() { _clean_fixture; }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"checked 1 k3d-manager references (0 tracking HEAD, ignored)"* ]]
}

@test "argocd values branch: unparseable input fails closed" {
  _kubectl() { printf '%s' 'not-json'; }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Could not evaluate values-branch drift"* ]]
  [[ "${output}" == *"values-branch input is not JSON"* ]]
}

@test "argocd values branch: zero k3d-manager references fails closed" {
  _kubectl() {
    cat <<'EOF'
{"items":[{"metadata":{"name":"chart-only"},"spec":{"sources":[{"chart":"trivy-operator","targetRevision":"0.34.0"}]}}]}
EOF
  }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"inspected 0 references"* ]]
}

@test "argocd values branch: manifest sources without ref are checked" {
  _kubectl() {
    cat <<'EOF'
{"items":[{"metadata":{"name":"manifest-source"},"spec":{"sources":[{"repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"k3d-manager-v1.16.0"}]}}]}
EOF
  }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"manifest-source"* ]]
}

@test "argocd values branch: HEAD sources are ignored as tracking sources" {
  _kubectl() {
    cat <<'EOF'
{"items":[
 {"metadata":{"name":"tracked"},"spec":{"sources":[{"repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"k3d-manager-v1.18.0"}]}},
 {"metadata":{"name":"rollout-demo"},"spec":{"sources":[{"repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"HEAD"}]}}
]}
EOF
  }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"rollout-demo HEAD"* ]]
}

@test "argocd values branch: counter reports checked and ignored HEAD references" {
  _kubectl() {
    cat <<'EOF'
{"items":[
 {"metadata":{"name":"tracked"},"spec":{"sources":[{"ref":"values","repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"k3d-manager-v1.18.0"}]}},
 {"metadata":{"name":"rollout-demo"},"spec":{"sources":[{"repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"HEAD"}]}}
]}
EOF
  }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"checked 1 k3d-manager references (1 tracking HEAD, ignored)"* ]]
}

@test "argocd values branch: dry-run skips confirmation" {
  _argocd_deploy_applicationsets() { return 0; }

  DRY_RUN=1 K3D_MANAGER_BRANCH=k3d-manager-v1.18.0 run deploy_argocd_applicationsets
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"DRY_RUN: skipping the values-branch confirmation"* ]]
  [[ "${output}" != *"All Applications reference"* ]]
}
