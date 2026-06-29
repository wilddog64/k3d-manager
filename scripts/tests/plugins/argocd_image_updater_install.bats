#!/usr/bin/env bats

SRC="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
KUST="${BATS_TEST_DIRNAME}/../../etc/argocd/image-updater/kustomization.yaml"

@test "image-updater install: deploy function defined" {
  run grep -F -- 'function _argocd_deploy_image_updater()' "${SRC}"
  [ "${status}" -eq 0 ]
}

@test "image-updater install: targets image-updater config dir" {
  run grep -F -- 'updater_dir="$ARGOCD_CONFIG_DIR/image-updater"' "${SRC}"
  [ "${status}" -eq 0 ]
}

@test "image-updater install: applies kustomize dir" {
  run grep -F -- 'apply -k "$updater_dir"' "${SRC}"
  [ "${status}" -eq 0 ]
}

@test "image-updater install: honors ARGOCD_SKIP_IMAGE_UPDATER" {
  run grep -F -- 'ARGOCD_SKIP_IMAGE_UPDATER' "${SRC}"
  [ "${status}" -eq 0 ]
}

@test "image-updater install: invoked from post-deploy bootstrap" {
  run grep -cF -- '_argocd_deploy_image_updater' "${SRC}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 2 ]
}

@test "image-updater pull-secret: ensure function defined" {
  run grep -F -- 'function _argocd_ensure_ghcr_pull_secret()' "${SRC}"
  [ "${status}" -eq 0 ]
}

@test "image-updater pull-secret: ensure invoked before install" {
  run grep -cF -- '_argocd_ensure_ghcr_pull_secret' "${SRC}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 2 ]
}

@test "image-updater pull-secret: secret created in ARGOCD_NAMESPACE" {
  run grep -F -- 'create secret docker-registry ghcr-pull-secret' "${SRC}"
  [ "${status}" -eq 0 ]
}

@test "image-updater pull-secret: credentials point at cicd" {
  run grep -F -- 'credentials: pullsecret:cicd/ghcr-pull-secret' "${KUST}"
  [ "${status}" -eq 0 ]
}

@test "image-updater pull-secret: no shopping-cart-apps reference in kustomization" {
  run grep -F -- 'shopping-cart-apps' "${KUST}"
  [ "${status}" -ne 0 ]
}
