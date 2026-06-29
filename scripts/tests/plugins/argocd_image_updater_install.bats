#!/usr/bin/env bats

SRC="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"

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
