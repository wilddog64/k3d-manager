#!/usr/bin/env bats

MAKEFILE="${MAKEFILE:-${BATS_TEST_DIRNAME}/../../../Makefile}"

show_service_passwords_target() {
  awk '/^show-service-passwords:/ { in_target=1; next } in_target && /^\t@echo ""$/ { exit } in_target { print }' "${MAKEFILE}"
}

run_show_service_passwords() {
  local mode="$1" bin="$BATS_TEST_TMPDIR/show-passwords-bin"
  mkdir -p "$bin"
  cat >"$bin/kubectl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"get secret vault-root"*) printf '%s' 'dG9rZW4=' ;;
  *"get secret argocd-initial-admin-secret"*) printf '%s' 'aW5pdGlhbC1wYXNz' ;;
  *) : ;;
esac
EOF
  cat >"$bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${BATS_TEST_TMPDIR}/show-passwords-curl-args"
url="${@: -1}"
case "$url" in
  *lookup-self) printf '200' ;;
  *secret/data/argocd/admin) printf '%s' '{"data":{"data":{"password":"vault-pass"}}}' ;;
  *api/v1/session)
    count_file="${BATS_TEST_TMPDIR}/show-passwords-session-count"
    count=0
    [ -f "$count_file" ] && count="$(cat "$count_file")"
    count=$((count + 1))
    printf '%s' "$count" >"$count_file"
    case "${MAKE_TEST_ARGOCD_MODE}" in
      stale) [ "$count" -eq 1 ] && printf '401' || printf '200' ;;
      rotated) printf '200' ;;
      unreachable) printf '503' ;;
    esac
    ;;
  *) printf '%s' '{"data":{"data":{"password":"other-pass"}}}' ;;
esac
EOF
  chmod +x "$bin"/*
  run env PATH="$bin:$PATH" MAKE_TEST_ARGOCD_MODE="$mode" SHOW_SERVICE_PASSWORDS_ARGOCD_URL=http://argocd.test make --no-print-directory -f "$MAKEFILE" show-service-passwords
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
  [[ "${target}" == *"argocd-initial-admin-secret"* ]]
}

@test "show-service-passwords: stale Vault candidate falls back to accepted initial secret" {
  run_show_service_passwords stale
  [ "$status" -eq 0 ]
  [[ "$output" == *"password: initial-pass"* ]]
  [[ "$output" == *"Vault secret/argocd/admin is stale (rejected by ArgoCD)"* ]]
  [[ "$(cat "$BATS_TEST_TMPDIR/show-passwords-curl-args")" != *"vault-pass"* ]]
  [[ "$(cat "$BATS_TEST_TMPDIR/show-passwords-curl-args")" != *"initial-pass"* ]]
}

@test "show-service-passwords: accepted Vault candidate wins without a note" {
  run_show_service_passwords rotated
  [ "$status" -eq 0 ]
  [[ "$output" == *"password: vault-pass"* ]]
  [[ "$output" != *"note:"* ]]
}

@test "show-service-passwords: unreachable ArgoCD falls back with an unverified note" {
  run_show_service_passwords unreachable
  [ "$status" -eq 0 ]
  [[ "$output" == *"password: vault-pass"* ]]
  [[ "$output" == *"note:     not verified against ArgoCD"* ]]
}

@test "show-service-passwords: candidate passwords are passed through payload files" {
  target="$(awk '/^show-service-passwords:/,/^$/' "${MAKEFILE}")"
  [[ "$target" != *'--arg password'* ]]
  [[ "$target" == *'--rawfile password'* ]]
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
