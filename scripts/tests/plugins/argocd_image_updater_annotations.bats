#!/usr/bin/env bats

YAML="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/services-git.yaml"
SCAN="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan.sh"

@test "image-updater: shopping-cart apps are not statically enrolled in image updater" {
  run grep -nF 'argocd-image-updater.argoproj.io/image-list' "${YAML}"
  [ "${status}" -eq 1 ]
}

@test "image-updater: no digest auto-update strategy remains in services-git" {
  run grep -nF 'argocd-image-updater.argoproj.io/app.update-strategy' "${YAML}"
  [ "${status}" -eq 1 ]
}

@test "image-updater: no argocd write-back method remains in services-git" {
  run grep -nF 'argocd-image-updater.argoproj.io/write-back-method' "${YAML}"
  [ "${status}" -eq 1 ]
}

@test "image-updater: services-git still preserves kustomize image diff ignore" {
  run grep -nF '.spec.source.kustomize.images' "${YAML}"
  [ "${status}" -eq 0 ]
}

@test "image-updater: app CVE scan no longer claims image updater will keep cluster current" {
  run grep -nF 'Image Updater keeps cluster current' "${SCAN}"
  [ "${status}" -eq 1 ]
}

@test "image-updater: app CVE scan logs controlled promotion requirement after rebuild dispatch" {
  run grep -nF 'controlled promotion must apply the replacement image' "${SCAN}"
  [ "${status}" -eq 0 ]
}
