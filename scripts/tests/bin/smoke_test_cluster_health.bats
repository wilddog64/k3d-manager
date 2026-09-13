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
    printf 'Synced\n'
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
}

@test "all healthy" {
  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"9 passed, 0 failed"* ]]
}

@test "defaults use the live app context and prefixed ArgoCD names" {
  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -F -- '--context=ubuntu-hostinger' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'ubuntu-k3s-shopping-cart-basket' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -F -- '--context=ubuntu-k3s ' "${KUBECTL_CALL_LOG}"
  [ "${status}" -ne 0 ]
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
