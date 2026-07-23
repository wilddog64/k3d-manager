#!/usr/bin/env bats

APPSETS="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets"
ARGOCD="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"

@test "appset deploy derives envsubst vars from each file" {
  run grep -c "envsubst '\$ARGOCD_NAMESPACE \$K3D_MANAGER_BRANCH \$APP_CLUSTER_NAME'" "${ARGOCD}"
  [ "${output}" -eq 0 ]
}

@test "every appset variable is defaulted in the argocd bootstrap scope" {
  local missing=""
  local vars_file="${BATS_TEST_DIRNAME}/../../etc/argocd/vars.sh"
  local argocd_sh="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  for f in "${APPSETS}"/*.yaml; do
    for v in $(grep -oh '\${[A-Za-z_][A-Za-z0-9_]*}' "$f" | tr -d '${}' | sort -u); do
      grep -qE "^export ${v}=|^: \"\\\$\{${v}:=" "${vars_file}" \
        || grep -qE "^\s*(export )?${v}=|^\s*: \"\\\$\{${v}:=" "${argocd_sh}" \
        || missing="${missing} $(basename "$f"):${v}"
    done
  done
  [ -z "${missing}" ] || { echo "appset vars not defaulted in bootstrap scope:${missing}"; false; }
}
