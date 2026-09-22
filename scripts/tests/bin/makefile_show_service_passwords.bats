#!/usr/bin/env bats

MAKEFILE="${MAKEFILE:-${BATS_TEST_DIRNAME}/../../../Makefile}"

show_service_passwords_target() {
  awk '/^show-service-passwords:/ { in_target=1; next } in_target && /^\t@echo ""$/ { exit } in_target { print }' "${MAKEFILE}"
}

@test "show-service-passwords: liveness gate no longer probes optional argocd mirror" {
  gate="$(show_service_passwords_target)"
  run grep -F 'secret/data/argocd/admin' <<<"${gate}"
  [ "${status}" -ne 0 ]
}

@test "show-service-passwords: liveness gate probes lookup-self twice" {
  gate="$(show_service_passwords_target)"
  [ "$(grep -Fo 'auth/token/lookup-self' <<<"${gate}" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "show-service-passwords: liveness error identifies Vault endpoint" {
  gate="$(show_service_passwords_target)"
  [[ "${gate}" == *'127.0.0.1:18200'* ]]
  [[ "${gate}" != *'check Vault token and port-forward'* ]]
}

@test "show-service-passwords: ArgoCD block references its authoritative k8s secret" {
  target="$(awk '/^show-service-passwords:/,/^$/' "${MAKEFILE}")"
  block="$(awk '/_argocd=/{ found=1 } found { print; if ($0 ~ /^\t?echo ""$/) exit }' <<<"${target}")"
  [[ "${block}" == *"argocd-initial-admin-secret"* ]]
}

@test "show-service-passwords: Prometheus block keeps Vault as its only credential source" {
  target="$(awk '/^show-service-passwords:/,/^$/' "${MAKEFILE}")"
  block="$(awk '/_prom_creds=/{ found=1 } found { print; if ($0 ~ /^\t?echo ""$/) exit }' <<<"${target}")"
  [[ "${block}" != *"prometheus-basic-auth.env"* ]]
  [[ "${block}" != *"argocd-initial-admin-secret"* ]]
}

@test "show-service-passwords: credential blocks retain N/A degradation" {
  target="$(awk '/^show-service-passwords:/,/^$/' "${MAKEFILE}")"
  for service in ArgoCD Grafana Prometheus Alertmanager; do
    block="$(awk -v marker="${service}" '$0 ~ marker && $0 ~ /echo/ { found=1 } found { print; if ($0 ~ /^\t?echo ""$/) exit }' <<<"${target}")"
    [ "$(grep -Fo ':-N/A}' <<<"${block}" | wc -l | tr -d ' ')" -ge 1 ]
  done
}
