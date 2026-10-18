#!/usr/bin/env bats

YAML="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/services-git.yaml"

@test "image-updater: image-list annotation is absent" {
  run grep -F -- 'argocd-image-updater.argoproj.io/image-list' "${YAML}"
  [ "${status}" -ne 0 ]
}

@test "image-updater: digest auto-update strategy is absent" {
  run grep -F -- 'argocd-image-updater.argoproj.io/app.update-strategy' "${YAML}"
  [ "${status}" -ne 0 ]
}

@test "image-updater: argocd write-back method is absent" {
  run grep -F -- 'argocd-image-updater.argoproj.io/write-back-method' "${YAML}"
  [ "${status}" -ne 0 ]
}

@test "image-updater: shopping-cart apps are no longer hard enrolled" {
  run grep -F -- 'ghcr.io/wilddog64/shopping-cart-' "${YAML}"
  [ "${status}" -ne 0 ]

  run grep -E -- 'if eq \.path\.basename "shopping-cart-(basket|order|product-catalog)"' "${YAML}"
  [ "${status}" -ne 0 ]
}
