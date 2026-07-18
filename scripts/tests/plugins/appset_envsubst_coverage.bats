#!/usr/bin/env bats

APPSETS="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets"
ARGOCD="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"

@test "appset deploy derives envsubst vars from each file" {
  run grep -c "envsubst '\$ARGOCD_NAMESPACE \$K3D_MANAGER_BRANCH \$APP_CLUSTER_NAME'" "${ARGOCD}"
  [ "${output}" -eq 0 ]
}

@test "every appset variable is exported by some deploy path" {
  local missing=""
  for f in "${APPSETS}"/*.yaml; do
    for v in $(grep -oh '\${[A-Za-z_][A-Za-z0-9_]*}' "$f" | tr -d '${}' | sort -u); do
      grep -rqh "export .*${v}\|: \"\${${v}:=" "${BATS_TEST_DIRNAME}/../../plugins/" \
        || missing="${missing} $(basename "$f"):${v}"
    done
  done
  [ -z "${missing}" ] || { echo "unexported appset vars:${missing}"; false; }
}
