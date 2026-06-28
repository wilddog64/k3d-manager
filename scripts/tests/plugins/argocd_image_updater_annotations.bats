#!/usr/bin/env bats

YAML="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/services-git.yaml"

@test "image-updater: image-list guarded for basket" {
  run grep -F -- 'eq .path.basename "shopping-cart-basket"' "${YAML}"
  [ "${status}" -eq 0 ]
}

@test "image-updater: image-list guarded for order" {
  run grep -F -- 'eq .path.basename "shopping-cart-order"' "${YAML}"
  [ "${status}" -eq 0 ]
}

@test "image-updater: image-list guarded for product-catalog" {
  run grep -F -- 'eq .path.basename "shopping-cart-product-catalog"' "${YAML}"
  [ "${status}" -eq 0 ]
}

@test "image-updater: image ref built from basename with :latest" {
  run grep -F -- 'app=ghcr.io/wilddog64/{{.path.basename}}:latest' "${YAML}"
  [ "${status}" -eq 0 ]
}

@test "image-updater: digest update-strategy present" {
  run grep -F -- 'argocd-image-updater.argoproj.io/app.update-strategy' "${YAML}"
  [ "${status}" -eq 0 ]
}

@test "image-updater: write-back-method argocd present" {
  run grep -F -- 'argocd-image-updater.argoproj.io/write-back-method' "${YAML}"
  [ "${status}" -eq 0 ]
}
