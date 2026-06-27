#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
}

@test "argocd app cluster generator: no static ubuntu-k3s ApplicationSet destination remains" {
  run grep -rF -- "ubuntu-k3s" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets"
  [ "$status" -eq 1 ]
}

@test "argocd app cluster generator: services-git uses matrix clusters label selector" {
  run grep -F -- "- matrix:" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/services-git.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- "k3d-manager/role: app-cluster" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/services-git.yaml"
  [ "$status" -eq 0 ]
}

@test "argocd app cluster generator: data-git exists and targets shopping-cart-data" {
  run test -f "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- "k3d-manager/role: app-cluster" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- "namespace: shopping-cart-data" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
}

@test "argocd app cluster generator: data-git ignores controller-injected volumeClaimTemplates fields" {
  run grep -F -- ".spec.volumeClaimTemplates[].status" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- ".spec.volumeClaimTemplates[].apiVersion" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- ".spec.volumeClaimTemplates[].kind" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
}
