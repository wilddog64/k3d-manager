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

@test "show-service-passwords: no credential is emitted on a user: line" {
  target="$(awk '/^show-service-passwords:/,/^$/' "${MAKEFILE}")"
  run grep -nE 'echo "[^"]*user:[^"]*\$\$\{_(kc|realm_admin|dev|op|argocd|graf|prom_pass|am_pass)' <<<"${target}"
  [ "${status}" -ne 0 ]
}

@test "show-service-passwords: every Keycloak credential sits behind a password: label" {
  target="$(awk '/^show-service-passwords:/,/^$/' "${MAKEFILE}")"
  block="$(awk '/_kc=/{ found=1 } found { print; if ($0 ~ /^\t?echo ""$/) exit }' <<<"${target}")"
  [ "$(grep -Fo 'password:' <<<"${block}" | wc -l | tr -d ' ')" -eq 4 ]
  for credential in _kc _realm_admin _dev _op; do
    run grep -nF 'password: $${'"${credential}" <<<"${block}"
    [ "${status}" -eq 0 ]
  done
}

@test "show-service-passwords: realm-user hint does not soften service admin" {
  target="$(awk '/^show-service-passwords:/,/^$/' "${MAKEFILE}")"
  block="$(awk '/_kc=/{ found=1 } found { print; if ($0 ~ /^\t?echo ""$/) exit }' <<<"${target}")"
  grep -q '_kc_hint=' <<<"${block}"
  [ "$(grep -Fo '$$_kc_hint' <<<"${block}" | wc -l | tr -d ' ')" -eq 3 ]
  grep -q 'password: $${_kc:-N/A}' <<<"${block}"
}

@test "show-service-passwords: other credential blocks remain unchanged" {
  target="$(awk '/^show-service-passwords:/,/^$/' "${MAKEFILE}")"
  for service in ArgoCD Grafana Prometheus Alertmanager; do
    block="$(awk -v marker="${service}" '$0 ~ marker && $0 ~ /echo/ { found=1 } found { print; if ($0 ~ /^\t?echo ""$/) exit }' <<<"${target}")"
    grep -q 'user:' <<<"${block}"
    grep -q 'password:' <<<"${block}"
    [ "$(grep -Fo ':-N/A}' <<<"${block}" | wc -l | tr -d ' ')" -ge 1 ]
  done
}
