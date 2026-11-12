#!/usr/bin/env bats

MAKEFILE="${MAKEFILE:-${BATS_TEST_DIRNAME}/../../../Makefile}"

setup() {
  WORK="${BATS_TEST_TMPDIR}/work"
  CALL_LOG="${BATS_TEST_TMPDIR}/calls.log"
  mkdir -p "${WORK}/scripts" "${WORK}/bin" "${BATS_TEST_TMPDIR}/config/k3d-manager"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  [[ "${XDG_CONFIG_HOME}" == "${BATS_TEST_TMPDIR}/"* ]]
  printf 'hub\n' > "${XDG_CONFIG_HOME}/k3d-manager/machine-role"
  cp "${BATS_TEST_DIRNAME}/../../../bin/k3dm-require-role" "${WORK}/bin/"
  cp "${MAKEFILE}" "${WORK}/Makefile"
  : > "${CALL_LOG}"
  cat > "${WORK}/scripts/k3d-manager" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'BRANCH:%s STAGE:%s ARGS:' "${K3D_MANAGER_BRANCH:-}" "${K3DM_APPSETS_STAGE:-}" >> "${CALL_LOG}"
printf ' <%s>' "$@" >> "${CALL_LOG}"
printf '\n' >> "${CALL_LOG}"
EOF
  chmod +x "${WORK}/scripts/k3d-manager"
}

_run_make() {
  run env CALL_LOG="${CALL_LOG}" INFRA_CONTEXT="${INFRA_CONTEXT:-k3d-cluster-context}" \
    make --no-print-directory -C "${WORK}" "$@"
}

@test "appsets-reapply always passes deploy/hub" {
  APPSETS_STAGE=hub _run_make appsets-reapply BRANCH=k3d-manager-v1.42.0
  [ "${status}" -eq 0 ]
  grep -Fx 'BRANCH:deploy/hub STAGE:hub ARGS: <deploy_argocd_applicationsets> <--confirm>' "${CALL_LOG}"
}

@test "appsets-reapply ignores BRANCH for release and feature refs" {
  for branch in main HEAD k3d-manager-v1.42 feat/k3d-manager-v1.42.0 k3d-manager-v1.42.0-x; do
    : > "${CALL_LOG}"
    _run_make appsets-reapply "BRANCH=${branch}"
    [ "${status}" -eq 0 ]
    grep -Fx 'BRANCH:deploy/hub STAGE:all ARGS: <deploy_argocd_applicationsets> <--confirm>' "${CALL_LOG}"
  done
}

@test "appsets-check passes the branch and infra context" {
  INFRA_CONTEXT=k3d-cluster-context _run_make appsets-check BRANCH=k3d-manager-v1.42.0
  [ "${status}" -eq 0 ]
  grep -Fx 'BRANCH: STAGE: ARGS: <argocd_check_values_branch> <deploy/hub> <k3d-cluster-context>' "${CALL_LOG}"
}

@test "appsets targets are phony and listed in help" {
  run grep -E '^\.PHONY:.*appsets-reapply([[:space:]]|$).*appsets-check([[:space:]]|$)' "${WORK}/Makefile"
  [ "${status}" -eq 0 ]
  _run_make help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make appsets-reapply"* ]]
  [[ "${output}" == *"make appsets-check"* ]]
  [[ "${output}" == *"make hub-promote REF=..."* ]]
  [[ "${output}" == *"make hub-rollback"* ]]
  [[ "${output}" == *"make hub-promote-status"* ]]
}

_promote_stub() {
  STUB_MAKE="${BATS_TEST_TMPDIR}/stub-make"
  [[ "${STUB_MAKE}" == "${BATS_TEST_TMPDIR}/"* ]]
  cat > "${STUB_MAKE}" <<'STUB'
#!/usr/bin/env bash
target=""
for arg in "$@"; do
  case "$arg" in --*|-*) ;; *=*) ;; *) target="$arg" ;; esac
done
printf '%s REF=%s\n' "$target" "${REF:-}" >> "${CALL_LOG}"
[[ "$target" == "${FAIL_TARGET:-none}" ]] && exit 1
exit 0
STUB
  chmod +x "${STUB_MAKE}"
}

@test "promote runs hub-promote, appsets-check, platform-ops in order with REF" {
  _promote_stub
  _run_make promote REF=abc123 MAKE="${STUB_MAKE}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${CALL_LOG}")" = "hub-promote REF=abc123" ]
  [ "$(sed -n 2p "${CALL_LOG}" | cut -d' ' -f1)" = "appsets-check" ]
  [ "$(sed -n 3p "${CALL_LOG}" | cut -d' ' -f1)" = "platform-ops" ]
  [ "$(wc -l < "${CALL_LOG}" | tr -d ' ')" -eq 3 ]
}

@test "promote stops after a declined or failed hub-promote" {
  _promote_stub
  run env CALL_LOG="${CALL_LOG}" FAIL_TARGET=hub-promote make --no-print-directory -C "${WORK}" promote REF=abc123 MAKE="${STUB_MAKE}"
  [ "$status" -ne 0 ]
  [ "$(wc -l < "${CALL_LOG}" | tr -d ' ')" -eq 1 ]
  run grep -E 'appsets-check|platform-ops' "${CALL_LOG}"
  [ "$status" -ne 0 ]
}

@test "promote stops before platform-ops when appsets-check fails" {
  _promote_stub
  run env CALL_LOG="${CALL_LOG}" FAIL_TARGET=appsets-check make --no-print-directory -C "${WORK}" promote REF=abc123 MAKE="${STUB_MAKE}"
  [ "$status" -ne 0 ]
  run grep -F 'platform-ops' "${CALL_LOG}"
  [ "$status" -ne 0 ]
}

@test "promote without REF refuses before calling anything" {
  _promote_stub
  run env -u REF CALL_LOG="${CALL_LOG}" make --no-print-directory -C "${WORK}" promote MAKE="${STUB_MAKE}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: make promote REF="* ]]
  [ ! -s "${CALL_LOG}" ]
}
