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
  *" get applications "*)
    printf '%s\n' "${STUB_APPS:-}"
    ;;
  *" config get-contexts "*)
    printf '%s' "${STUB_CONTEXTS:-}"
    ;;
  *" get secret "*)
    if [[ " $* " == *" -n ${STUB_MISSING_SECRET_NS} "* ]]; then
      exit 1
    fi
    ;;
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
  export STUB_APPS=$'ubuntu-hostinger-shopping-cart-basket\tubuntu-hostinger\nubuntu-hostinger-shopping-cart-order\tubuntu-hostinger\nubuntu-hostinger-shopping-cart-payment\tubuntu-hostinger\nubuntu-hostinger-shopping-cart-product-catalog\tubuntu-hostinger\nubuntu-hostinger-shopping-cart-frontend\tubuntu-hostinger\nhub-grafana-dashboards\tk3d-k3d-cluster'
  export STUB_CONTEXTS=$'k3d-k3d-cluster\nubuntu-hostinger'
  unset APP_CONTEXT INFRA_CONTEXT ARGOCD_APP_PREFIX KUBECTL_STUB_MODE STUB_MISSING_SECRET_NS
}
@test "current inventory selects the hostinger target" {
  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"9 passed, 0 failed"* ]]
  run grep -E -- '--context=ubuntu-hostinger get pods' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -E -- '--context=ubuntu-hostinger get secret ghcr-pull-secret' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'get application ubuntu-hostinger-shopping-cart-basket' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  for app in order payment product-catalog frontend; do
    run grep -F -- "get application ubuntu-hostinger-shopping-cart-${app}" "${KUBECTL_CALL_LOG}"
    [ "${status}" -eq 0 ]
  done
  run grep -c -- 'get applications' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
  [ "${output}" -eq 1 ]
}

@test "no candidates refuses before health checks" {
  export STUB_APPS=$'hub-grafana-dashboards\tk3d-k3d-cluster'

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"[TARGET]"* ]]
  [[ "${output}" != *"[FAIL]"* ]]
  run grep -E -- 'get (secret|pods)' "${KUBECTL_CALL_LOG}"
  [ "${status}" -ne 0 ]
}

@test "multiple candidates refuse without a prefix" {
  export STUB_APPS=$'ubuntu-hostinger-shopping-cart-basket\tubuntu-hostinger\nacg-aws-shopping-cart-basket\tacg-aws'
  export STUB_CONTEXTS=$'k3d-k3d-cluster\nubuntu-hostinger\nacg-aws'

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"ubuntu-hostinger-shopping-cart-basket"* ]]
  [[ "${output}" == *"acg-aws-shopping-cart-basket"* ]]
}

@test "explicit prefix selects the AWS candidate" {
  export STUB_APPS=$'ubuntu-hostinger-shopping-cart-basket\tubuntu-hostinger\nacg-aws-shopping-cart-basket\tacg-aws'
  export STUB_CONTEXTS=$'k3d-k3d-cluster\nubuntu-hostinger\nacg-aws'
  export ARGOCD_APP_PREFIX=acg-aws-

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -E -- '--context=acg-aws get pods' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
}

@test "an incorrect explicit prefix refuses without health failures" {
  export ARGOCD_APP_PREFIX=ubuntu-k3s-

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"[TARGET]"* ]]
  [[ "${output}" != *"[FAIL]"* ]]
}

@test "a destination that is not local refuses safely" {
  export STUB_APPS=$'ubuntu-hostinger-shopping-cart-basket\tremote-only'
  export STUB_CONTEXTS=$'k3d-k3d-cluster\nubuntu-hostinger'

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"remote-only"* ]]
  [[ "${output}" != *"[FAIL]"* ]]
}

@test "an explicit context that mismatches the destination refuses" {
  export APP_CONTEXT=ubuntu-k3s

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"does not match"* ]]
  [[ "${output}" != *"[FAIL]"* ]]
}

@test "an explicit context equal to the destination is honored" {
  export APP_CONTEXT=ubuntu-hostinger

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -E -- '--context=ubuntu-hostinger get pods' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
}

@test "an empty destination uses the infra context" {
  export STUB_APPS=$'ubuntu-hostinger-shopping-cart-basket\t'
  export STUB_CONTEXTS=k3d-k3d-cluster

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -E -- '--context=k3d-k3d-cluster get pods' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
}

@test "an empty prefix selects the unprefixed basket application" {
  export STUB_APPS=$'shopping-cart-basket\t'
  export ARGOCD_APP_PREFIX=

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -F -- 'get application shopping-cart-basket' "${KUBECTL_CALL_LOG}"
  [ "${status}" -eq 0 ]
}

@test "a selected-target secret failure remains a health failure" {
  export STUB_MISSING_SECRET_NS=shopping-cart-data

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"[FAIL] ghcr-pull-secret MISSING in shopping-cart-data"* ]]
}

@test "kubectl failure reports target discovery failure" {
  export KUBECTL_STUB_MODE=fail

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"[TARGET] could not list ArgoCD Applications"* ]]
  [[ "${output}" != *"[FAIL]"* ]]
}
