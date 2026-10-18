#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${ARGOCD_PLUGIN_SOURCE:-${BATS_TEST_DIRNAME}/../../plugins/argocd.sh}"
  RENDERED_FILE="${BATS_TEST_TMPDIR}/cluster-secret.yaml"
  ROLE_LOOKUP=""
  _kubectl() {
    if [[ "$1" == "get" && "$2" == "secret" ]]; then
      [[ -n "${ROLE_LOOKUP}" ]] && printf '%s\n' "${ROLE_LOOKUP}"
      [[ -n "${ROLE_LOOKUP}" ]] && return 0
      return 1
    fi
    if [[ "$1" == "apply" && "$2" == "-f" ]]; then
      cp "$3" "${RENDERED_FILE}"
    fi
  }
  _argocd_set_active_app_cluster() {
    printf 'role-set\n' > "${BATS_TEST_TMPDIR}/active-role"
  }
  export RENDERED_FILE ROLE_LOOKUP
  export -f _kubectl _argocd_set_active_app_cluster
}

register_for_test() {
  export ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc
  export ARGOCD_APP_CLUSTER_NAME=ubuntu-k3s
  export ARGOCD_APP_CLUSTER_SECRET_NAME=ubuntu-k3s-app-cluster
  export ARGOCD_NAMESPACE=cicd
  run register_app_cluster
}

@test "data-git preserves generated resources and keeps its generator contract" {
  local manifest="${DATA_GIT_MANIFEST:-${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml}"
  run grep -F -- 'preserveResourcesOnDeletion: true' "${manifest}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'k3d-manager/role: app-cluster' "${manifest}"
  [ "${status}" -eq 0 ]
  run grep -F -- "name: '{{.name}}-data-layer'" "${manifest}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'path: data-layer' "${manifest}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'PrunePropagationPolicy=foreground' "${manifest}"
  [ "${status}" -eq 0 ]
}

@test "re-registration carries an existing app-cluster role into the manifest" {
  ROLE_LOOKUP=app-cluster
  export ROLE_LOOKUP
  register_for_test
  [ "${status}" -eq 0 ]
  run grep -F -- 'k3d-manager/role: "app-cluster"' "${RENDERED_FILE}"
  [ "${status}" -eq 0 ]
}

@test "first-time registration still applies the app-cluster role" {
  register_for_test
  [ "${status}" -eq 0 ]
  [ "$(<"${BATS_TEST_TMPDIR}/active-role")" = "role-set" ]
}
