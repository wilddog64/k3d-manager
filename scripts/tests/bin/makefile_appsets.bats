#!/usr/bin/env bats

MAKEFILE="${MAKEFILE:-${BATS_TEST_DIRNAME}/../../../Makefile}"

setup() {
  WORK="${BATS_TEST_TMPDIR}/work"
  CALL_LOG="${BATS_TEST_TMPDIR}/calls.log"
  mkdir -p "${WORK}/scripts"
  cp "${MAKEFILE}" "${WORK}/Makefile"
  : > "${CALL_LOG}"
  cat > "${WORK}/scripts/k3d-manager" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'BRANCH:%s ARGS:' "${K3D_MANAGER_BRANCH:-}" >> "${CALL_LOG}"
printf ' <%s>' "$@" >> "${CALL_LOG}"
printf '\n' >> "${CALL_LOG}"
EOF
  chmod +x "${WORK}/scripts/k3d-manager"
}

_run_make() {
  run env CALL_LOG="${CALL_LOG}" INFRA_CONTEXT="${INFRA_CONTEXT:-k3d-cluster-context}" \
    make --no-print-directory -C "${WORK}" "$@"
}

@test "appsets-reapply validates and passes the release branch" {
  _run_make appsets-reapply BRANCH=k3d-manager-v1.42.0
  [ "${status}" -eq 0 ]
  grep -Fx 'BRANCH:k3d-manager-v1.42.0 ARGS: <deploy_argocd_applicationsets> <--confirm>' "${CALL_LOG}"
}

@test "appsets-reapply refuses non-release branches" {
  for branch in main HEAD k3d-manager-v1.42 feat/k3d-manager-v1.42.0 k3d-manager-v1.42.0-x; do
    : > "${CALL_LOG}"
    _run_make appsets-reapply "BRANCH=${branch}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not a release branch"* ]]
    [ ! -s "${CALL_LOG}" ]
  done
}

@test "appsets-check passes the branch and infra context" {
  INFRA_CONTEXT=k3d-cluster-context _run_make appsets-check BRANCH=k3d-manager-v1.42.0
  [ "${status}" -eq 0 ]
  grep -Fx 'BRANCH: ARGS: <argocd_check_values_branch> <k3d-manager-v1.42.0> <k3d-cluster-context>' "${CALL_LOG}"
}

@test "appsets targets are phony and listed in help" {
  run grep -E '^\.PHONY:.*appsets-reapply([[:space:]]|$).*appsets-check([[:space:]]|$)' "${WORK}/Makefile"
  [ "${status}" -eq 0 ]
  _run_make help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make appsets-reapply"* ]]
  [[ "${output}" == *"make appsets-check"* ]]
}
