#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${ARGOCD_PLUGIN_SOURCE:-${BATS_TEST_DIRNAME}/../../plugins/argocd.sh}"
  RENDERED_FILE="${BATS_TEST_TMPDIR}/cluster-secret.yaml"
  ROLE_LOOKUP=""
  _kubectl() {
    while [[ "$1" == --* ]]; do
      shift
    done
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

@test "first-time registration applies the cluster secret without a role label" {
  register_for_test
  [ "${status}" -eq 0 ]
  [ "$(<"${BATS_TEST_TMPDIR}/active-role")" = "role-set" ]
  run grep -F -- 'k3d-manager/role:' "${RENDERED_FILE}"
  [ "${status}" -ne 0 ]
}

@test "a failed real kubectl role lookup still applies the cluster secret" {
  local kubectl_bin="${BATS_TEST_TMPDIR}/bin/kubectl"
  local applied_file="${BATS_TEST_TMPDIR}/real-kubectl-applied.yaml"
  local runner="${BATS_TEST_TMPDIR}/run-registration.sh"
  mkdir -p "${kubectl_bin%/*}"
  cat > "${kubectl_bin}" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "get" && "$2" == "secret" ]]; then
  printf 'secret lookup failed\n' >&2
  exit 1
fi
if [[ "$1" == "apply" && "$2" == "-f" ]]; then
  cat "$3" > "${APPLIED_FILE}"
  exit 0
fi
exit 2
STUB
  chmod +x "${kubectl_bin}"
  export APPLIED_FILE="${applied_file}"
  export PATH="${kubectl_bin%/*}:${PATH}"
  export ARGOCD_PLUGIN_SOURCE="${ARGOCD_PLUGIN_SOURCE:-${SCRIPT_DIR}/plugins/argocd.sh}"
  export ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc
  export ARGOCD_APP_CLUSTER_NAME=ubuntu-k3s
  export ARGOCD_APP_CLUSTER_SECRET_NAME=ubuntu-k3s-app-cluster
  export ARGOCD_NAMESPACE=cicd
  cat > "${runner}" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
source "${SCRIPT_DIR}/lib/system.sh"
source "${ARGOCD_PLUGIN_SOURCE}"
_argocd_set_active_app_cluster() { :; }
register_app_cluster
printf 'registration-survived\n'
SCRIPT
  chmod +x "${runner}"

  run bash "${runner}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"registration-survived"* ]]
  [[ "${output}" != *"secret lookup failed"* ]]
  [ -s "${APPLIED_FILE}" ]
  run grep -F -- 'k3d-manager/role:' "${APPLIED_FILE}"
  [ "${status}" -ne 0 ]
}
