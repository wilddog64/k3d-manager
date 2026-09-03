#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
}

@test "shopping-cart-namespace app owns the namespace and ghcr pull secret manifests" {
  run test -f "${BATS_TEST_DIRNAME}/../../../services/shopping-cart-namespace/kustomization.yaml"
  [ "$status" -eq 0 ]
  run test -f "${BATS_TEST_DIRNAME}/../../../services/shopping-cart-namespace/namespace.yaml"
  [ "$status" -eq 0 ]
  run test -f "${BATS_TEST_DIRNAME}/../../../services/shopping-cart-namespace/ghcr-pull-secret-externalsecret.yaml"
  [ "$status" -eq 0 ]
  run grep -qF -- "ghcr-pull-secret-externalsecret.yaml" "${BATS_TEST_DIRNAME}/../../../services/shopping-cart-namespace/kustomization.yaml"
  [ "$status" -eq 0 ]
  run grep -qF -- "argocd.argoproj.io/sync-wave: \"-1\"" "${BATS_TEST_DIRNAME}/../../../services/shopping-cart-namespace/namespace.yaml"
  [ "$status" -eq 0 ]
  run grep -qF -- "secret/data/github/pat" "${BATS_TEST_DIRNAME}/../../../services/shopping-cart-namespace/ghcr-pull-secret-externalsecret.yaml"
  [ "$status" -eq 0 ]
  run grep -qF -- "kubernetes.io/dockerconfigjson" "${BATS_TEST_DIRNAME}/../../../services/shopping-cart-namespace/ghcr-pull-secret-externalsecret.yaml"
  [ "$status" -eq 0 ]
}

@test "shopping-cart-frontend deployment uses ghcr pull secret" {
  run test -f "${BATS_TEST_DIRNAME}/../../../services/shopping-cart-frontend/serviceaccount.yaml"
  [ "$status" -eq 0 ]

  run grep -qF -- "imagePullSecrets:" "${BATS_TEST_DIRNAME}/../../../services/shopping-cart-frontend/serviceaccount.yaml"
  [ "$status" -eq 0 ]

  run grep -qF -- "- name: ghcr-pull-secret" "${BATS_TEST_DIRNAME}/../../../services/shopping-cart-frontend/serviceaccount.yaml"
  [ "$status" -eq 0 ]

  run grep -qF -- "serviceaccount.yaml" "${BATS_TEST_DIRNAME}/../../../services/shopping-cart-frontend/kustomization.yaml"
  [ "$status" -eq 0 ]

  run grep -qF -- "serviceAccountName: frontend" "${BATS_TEST_DIRNAME}/../../../services/shopping-cart-frontend/kustomization.yaml"
  [ "$status" -eq 0 ]
}
