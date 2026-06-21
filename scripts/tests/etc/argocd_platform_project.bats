#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  PLATFORM_TMPL="${REPO_ROOT}/scripts/etc/argocd/projects/platform.yaml.tmpl"
  ESO_APPSET="${REPO_ROOT}/scripts/etc/argocd/applicationsets/eso.yaml"
}

@test "platform AppProject does not hardwire app-cluster to a single provider name" {
  run grep -nE 'name:[[:space:]]*ubuntu-k3s' "$PLATFORM_TMPL"
  [ "$status" -ne 0 ]
}

@test "platform AppProject does not bake a render-time provider name" {
  run grep -nE 'name:[[:space:]]*\$\{APP_CLUSTER_NAME\}' "$PLATFORM_TMPL"
  [ "$status" -ne 0 ]
}

@test "platform AppProject uses provider-generic app-cluster destinations" {
  run grep -cE "name:[[:space:]]*'\\*'" "$PLATFORM_TMPL"
  [ "$status" -eq 0 ]
  [ "$output" -ge 7 ]
}

@test "eso ApplicationSet uses cluster-name destination form (matches data-git)" {
  run grep -nE "name:[[:space:]]*'\\{\\{.name\\}\\}'" "$ESO_APPSET"
  [ "$status" -eq 0 ]
  run grep -nE "server:[[:space:]]*'\\{\\{.server\\}\\}'" "$ESO_APPSET"
  [ "$status" -ne 0 ]
}
