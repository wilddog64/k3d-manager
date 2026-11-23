#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  export CALL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  : >"${CALL_LOG}"
}

_run_deregister() {
  CALL_LOG="${CALL_LOG}" SCRIPT_DIR="${REPO_ROOT}/scripts" bash -c '
    source "${SCRIPT_DIR}/lib/providers/k3s-hostinger.sh"
    _HOSTINGER_KUBE_CONTEXT=hostinger-test
    _info() { :; }
    _kubectl() {
      printf "%s\n" "$*" >>"${CALL_LOG}"
      case "$*" in
        "-n cicd get secret cluster-hostinger-test -o jsonpath={.data.server}")
          printf "%s" "$(printf %s https://host.k3d.internal:6443 | base64)"
          ;;
        "-n cicd get applications -o json")
          cat <<'JSON'
{"items":[
{"metadata":{"name":"hostinger-by-name"},"spec":{"destination":{"name":"hostinger-test"}}},
{"metadata":{"name":"hostinger-by-server"},"spec":{"destination":{"server":"https://host.k3d.internal:6443"}}},
{"metadata":{"name":"other-cluster"},"spec":{"destination":{"name":"other"}}},
{"metadata":{"name":"in-cluster"},"spec":{"destination":{"server":"https://kubernetes.default.svc"}}}
]}
JSON
          ;;
      esac
    }
    _hostinger_deregister_cluster
  '
}

@test "matching applications have finalizers stripped and are deleted" {
  run _run_deregister
  [ "${status}" -eq 0 ]
  grep -q 'patch application/hostinger-by-name --type=merge' "${CALL_LOG}"
  grep -q 'delete application/hostinger-by-name --ignore-not-found' "${CALL_LOG}"
  grep -q 'patch application/hostinger-by-server --type=merge' "${CALL_LOG}"
  grep -q 'delete application/hostinger-by-server --ignore-not-found' "${CALL_LOG}"
  run grep -q 'application/other-cluster' "${CALL_LOG}"
  [ "${status}" -ne 0 ]
  run grep -q 'application/in-cluster' "${CALL_LOG}"
  [ "${status}" -ne 0 ]
  run grep -q 'applicationset' "${CALL_LOG}"
  [ "${status}" -ne 0 ]
}

@test "Secret is deleted before the first Application" {
  run _run_deregister
  [ "${status}" -eq 0 ]
  secret_line="$(grep -n 'delete secret cluster-hostinger-test' "${CALL_LOG}" | cut -d: -f1)"
  app_line="$(grep -n 'delete application/' "${CALL_LOG}" | head -1 | cut -d: -f1)"
  [ "${secret_line}" -lt "${app_line}" ]
}

@test "in-cluster server is not matched" {
  : >"${CALL_LOG}"
  run env CALL_LOG="${CALL_LOG}" SCRIPT_DIR="${REPO_ROOT}/scripts" bash -c '
    source "${SCRIPT_DIR}/lib/providers/k3s-hostinger.sh"
    _HOSTINGER_KUBE_CONTEXT=hostinger-test
    _info() { :; }
    _kubectl() {
      printf "%s\n" "$*" >>"${CALL_LOG}"
      case "$*" in
        "-n cicd get secret cluster-hostinger-test -o jsonpath={.data.server}")
          printf "%s" "$(printf %s https://kubernetes.default.svc | base64)"
          ;;
        "-n cicd get applications -o json")
          cat <<'JSON'
{"items":[
{"metadata":{"name":"in-cluster"},"spec":{"destination":{"server":"https://kubernetes.default.svc"}}},
{"metadata":{"name":"other-cluster"},"spec":{"destination":{"name":"other"}}}
]}
JSON
          ;;
      esac
    }
    _hostinger_deregister_cluster
  '
  [ "${status}" -eq 0 ]
  run grep -E 'patch application/in-cluster|delete application/in-cluster' "${CALL_LOG}"
  [ "${status}" -ne 0 ]
}
