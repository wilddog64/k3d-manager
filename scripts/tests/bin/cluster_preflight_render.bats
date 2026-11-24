#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/../../.."
  REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
  RENDER_FN="$(sed -n '/^function _cluster_preflight_render_services_appset()/,/^}/p' "$REPO_ROOT/bin/cluster-preflight")"
  command -v envsubst
}

@test "services appset render uses preflight names from the real template" {
  run env REPO_ROOT="$REPO_ROOT" ARGOCD_NAMESPACE=cicd K3D_MANAGER_BRANCH=deploy/hub \
    bash -c "$RENDER_FN; _cluster_preflight_render_services_appset '$BATS_TEST_TMPDIR/rendered.yaml' sandbox"
  [ "$status" -eq 0 ]
  grep -Fqx "  name: sandbox-preflight-services-git" "$BATS_TEST_TMPDIR/rendered.yaml"
  grep -Fqx "      name: 'sandbox-preflight-{{.path.basename}}'" "$BATS_TEST_TMPDIR/rendered.yaml"
  run grep -Fq "      name: '{{.name}}-{{.path.basename}}'" "$BATS_TEST_TMPDIR/rendered.yaml"
  [ "$status" -eq 1 ]
}

@test "services appset render fails when Application name line is missing" {
  mkdir -p "$BATS_TEST_TMPDIR/repo/scripts/etc/argocd/applicationsets"
  sed "/^      name: '{{.name}}-{{.path.basename}}'$/d" \
    "$REPO_ROOT/scripts/etc/argocd/applicationsets/services-git.yaml" \
    > "$BATS_TEST_TMPDIR/repo/scripts/etc/argocd/applicationsets/services-git.yaml"
  [ -f "$BATS_TEST_TMPDIR/repo/scripts/etc/argocd/applicationsets/services-git.yaml" ]
  run env REPO_ROOT="$BATS_TEST_TMPDIR/repo" ARGOCD_NAMESPACE=cicd K3D_MANAGER_BRANCH=deploy/hub \
    bash -c "$RENDER_FN; _cluster_preflight_render_services_appset '$BATS_TEST_TMPDIR/doctored.yaml' sandbox"
  [ "$status" -ne 0 ]
}
