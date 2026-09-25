#!/usr/bin/env bats

setup() {
  repo_root="${BATS_TEST_DIRNAME}/../../.."
  hostinger="${repo_root}/scripts/lib/providers/k3s-hostinger.sh"
  observability="${repo_root}/scripts/plugins/observability.sh"
  cluster_up="${repo_root}/bin/cluster-up"
}

@test "the pushgateway probe uses the installed service name" {
  run sed -n '/local _pushgateway_pf_plist=/,/rm -f "${_pushgateway_pf_plist}"/p' "${hostinger}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'local _pushgateway_svc="prometheus-pushgateway"'* ]]
  [[ "${output}" == *'get svc "${_pushgateway_svc}"'* ]]
  [[ "${output}" == *'"svc/${_pushgateway_svc}"'* ]]
}

@test "no producer refers to the bare pushgateway service name" {
  run grep -nE 'get svc pushgateway([^[:alnum:]_-]|$)|svc/pushgateway([^[:alnum:]_-]|$)|helm upgrade --install pushgateway([^[:alnum:]_-]|$)' "${hostinger}" "${cluster_up}" "${observability}"
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}

@test "all three sites agree on the pushgateway service name" {
  helm_name="$(sed -n 's/.*helm upgrade --install \([^ ]*\).*/\1/p' "${observability}")"
  cluster_name="$(sed -n 's#.*<string>svc/\(prometheus-pushgateway\)</string>.*#\1#p' "${cluster_up}")"
  hostinger_name="$(sed -n 's/.*local _pushgateway_svc="\([^"]*\)".*/\1/p' "${hostinger}")"
  [ "${helm_name}" = "prometheus-pushgateway" ]
  [ "${helm_name}" = "${cluster_name}" ]
  [ "${helm_name}" = "${hostinger_name}" ]
}
