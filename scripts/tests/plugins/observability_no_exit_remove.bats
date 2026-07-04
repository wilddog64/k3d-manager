#!/usr/bin/env bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"

@test "observability remove dashboard: missing configmap does not abort" {
  source "${REPO_ROOT}/scripts/plugins/observability.sh"

  _observability_acg_context() {
    printf '%s\n' "ubuntu-hostinger"
  }

  _kubectl() {
    printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/kubectl.log"
    case "$*" in
      --no-exit\ --context\ ubuntu-hostinger\ -n\ monitoring\ get\ configmap\ grafana-dashboard-argocd)
        return 1
        ;;
      *)
        return 0
        ;;
    esac
  }

  _info() {
    :
  }

  run _observability_remove_argocd_dashboard "ubuntu-hostinger"
  [ "${status}" -eq 0 ]

  run cat "${BATS_TEST_TMPDIR}/kubectl.log"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--no-exit --context ubuntu-hostinger -n monitoring get configmap grafana-dashboard-argocd"* ]]
}
