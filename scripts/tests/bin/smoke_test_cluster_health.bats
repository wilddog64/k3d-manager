#!/usr/bin/env bats

setup() {
  SMOKE_SCRIPT="${BATS_TEST_DIRNAME}/../../../bin/smoke-test-cluster-health"
  KUBECTL_CALL_LOG="${BATS_TEST_TMPDIR}/kubectl-calls"
  KUBECTL_STUB="${BATS_TEST_TMPDIR}/kubectl"

  cat >"${KUBECTL_STUB}" <<'EOF'
#!/usr/bin/env bash
printf '%s ' "$@" >>"${KUBECTL_CALL_LOG}"
printf '\n' >>"${KUBECTL_CALL_LOG}"

if [[ "${KUBECTL_STUB_MODE:-healthy}" == "fail" ]]; then
  exit 1
fi

case " $* " in
  *" get application "*)
    if [[ " $* " == *"destination.name"* ]]; then
      printf '%s' "${STUB_APP_DEST:-}"
    else
      printf 'Synced\n'
    fi
    ;;
  *" config get-contexts "*)
    printf '%s' "${STUB_CONTEXTS:-}"
    ;;
  *" get pods "*)
    if [[ " $* " == *" shopping-cart-apps "* ]]; then
      printf 'app-%s Running\n' 1 2 3
    else
      printf 'payment-%s Running\n' 1 2
    fi
    ;;
esac
EOF
  chmod +x "${KUBECTL_STUB}"
  export PATH="${BATS_TEST_TMPDIR}:${PATH}"
  export KUBECTL_CALL_LOG
  unset APP_CONTEXT INFRA_CONTEXT ARGOCD_APP_PREFIX KUBECTL_STUB_MODE
  unset STUB_APP_DEST STUB_CONTEXTS
}

@test "all healthy" {
  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"9 passed, 0 failed"* ]]
}

@test "defaults check pods on the infra context and use prefixed ArgoCD names" {
  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -E -- '--context=k3d-k3d-cluster get pods' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -E -- '--context=k3d-k3d-cluster get secret ghcr-pull-secret' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'ubuntu-k3s-shopping-cart-basket' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'ubuntu-hostinger' "${KUBECTL_CALL_LOG}"
  [ "${status}" -ne 0 ]
}

@test "INFRA_CONTEXT override flows to pod checks when APP_CONTEXT is unset" {
  export INFRA_CONTEXT=hub-x

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -E -- '--context=hub-x get pods' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'k3d-k3d-cluster' "${KUBECTL_CALL_LOG}"
  [ "${status}" -ne 0 ]
}

@test "explicit APP_CONTEXT is honored for pods and secrets" {
  export APP_CONTEXT=remote-y

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -E -- '--context=remote-y get pods' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -E -- '--context=remote-y get secret ghcr-pull-secret' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -E -- '--context=k3d-k3d-cluster get application' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
}

@test "kubectl failure is reported rather than exiting silently" {
  export KUBECTL_STUB_MODE=fail

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"=== Result:"* ]]
  [[ "${output}" == *"NotFound (expected Synced)"* ]]
}

@test "an empty ArgoCD app prefix is preserved" {
  export ARGOCD_APP_PREFIX=""

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -F -- 'get application shopping-cart-basket' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
}

@test "app context is resolved from the checked application's destination" {
  export STUB_APP_DEST="ubuntu-k3s"
  export STUB_CONTEXTS="k3d-k3d-cluster
ubuntu-k3s
ubuntu-hostinger"

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -E -- '--context=ubuntu-k3s get pods' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -E -- '--context=ubuntu-k3s get secret ghcr-pull-secret' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -E -- '--context=k3d-k3d-cluster .*get application' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
}

@test "a destination that is not a local context falls back to the infra context" {
  export STUB_APP_DEST="remote-only"
  export STUB_CONTEXTS="k3d-k3d-cluster
ubuntu-k3s"

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -E -- '--context=k3d-k3d-cluster get pods' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -E -- '--context=remote-only get pods' "${KUBECTL_CALL_LOG}"
  [ "${status}" -ne 0 ]
}

@test "an empty destination falls back to the infra context" {
  export STUB_APP_DEST=""
  export STUB_CONTEXTS="k3d-k3d-cluster"

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -E -- '--context=k3d-k3d-cluster get pods' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
}

@test "explicit APP_CONTEXT wins over a resolvable destination" {
  export APP_CONTEXT=remote-y
  export STUB_APP_DEST="ubuntu-k3s"
  export STUB_CONTEXTS="k3d-k3d-cluster
ubuntu-k3s"

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -E -- '--context=remote-y get pods' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -E -- '--context=ubuntu-k3s get pods' "${KUBECTL_CALL_LOG}"
  [ "${status}" -ne 0 ]
  run grep -F -- 'destination.name' "${KUBECTL_CALL_LOG}"
  [ "${status}" -ne 0 ]
}

@test "the chosen contexts are reported before the checks run" {
  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Infra context: k3d-k3d-cluster"* ]]
  [[ "${output}" == *"app context: k3d-k3d-cluster"* ]]
  [[ "${output}" == *"ubuntu-k3s-shopping-cart-*"* ]]
}
