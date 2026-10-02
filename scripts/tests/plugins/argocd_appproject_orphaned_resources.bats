#!/usr/bin/env bats

PROJECT_DIR="${BATS_TEST_DIRNAME}/../../etc/argocd/projects"

@test "platform AppProject has no orphaned-resource monitoring" {
  run bash -c 'ARGOCD_NAMESPACE=cicd envsubst '\''$ARGOCD_NAMESPACE'\'' < "$1" | yq -e '\''select(.kind == "AppProject") | .spec.orphanedResources == null'\''' _ "${PROJECT_DIR}/platform.yaml.tmpl"
  [ "${status}" -eq 0 ]
}

@test "shopping-cart AppProject has no orphaned-resource monitoring" {
  run bash -c 'ARGOCD_NAMESPACE=cicd envsubst '\''$ARGOCD_NAMESPACE'\'' < "$1" | yq -e '\''select(.kind == "AppProject") | .spec.orphanedResources == null'\''' _ "${PROJECT_DIR}/shopping-cart.yaml.tmpl"
  [ "${status}" -eq 0 ]
}

@test "AppProjects retain required project fields" {
  for project in platform shopping-cart; do
    run bash -c 'ARGOCD_NAMESPACE=cicd envsubst '\''$ARGOCD_NAMESPACE'\'' < "$1" | yq -e '\''select(.kind == "AppProject") | (.spec.sourceRepos | length > 0) and (.spec.destinations | length > 0)'\''' _ "${PROJECT_DIR}/${project}.yaml.tmpl"
    [ "${status}" -eq 0 ]
  done

  run bash -c 'ARGOCD_NAMESPACE=cicd envsubst '\''$ARGOCD_NAMESPACE'\'' < "$1" | yq -e '\''select(.kind == "AppProject") | .spec.roles | length > 0'\''' _ "${PROJECT_DIR}/platform.yaml.tmpl"
  [ "${status}" -eq 0 ]
}
