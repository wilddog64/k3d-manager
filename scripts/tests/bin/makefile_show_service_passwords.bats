#!/usr/bin/env bats

MAKEFILE="${MAKEFILE:-${BATS_TEST_DIRNAME}/../../../Makefile}"

show_service_passwords_target() {
  awk '/^show-service-passwords:/ { in_target=1; next } in_target && /^\t@echo ""$/ { exit } in_target { print }' "${MAKEFILE}"
}

show_service_passwords_full_target() {
  awk '/^show-service-passwords:/ { in_target=1 } in_target && /^## / { exit } in_target { print }' "${MAKEFILE}"
}

run_show_service_passwords() {
  local mode="$1" bin="$BATS_TEST_TMPDIR/bin" real_jq
  real_jq="$(command -v jq)"
  [ -n "$real_jq" ]
  mkdir -p "$bin" "$BATS_TEST_TMPDIR/$mode/home" "$BATS_TEST_TMPDIR/$mode/tmp"
  : >"$BATS_TEST_TMPDIR/session-bodies"
  : >"$BATS_TEST_TMPDIR/curl-args"
  [ "$BATS_TEST_TMPDIR/$mode/home" = "$BATS_TEST_TMPDIR/$mode/home" ]
  [ -z "$(find "$BATS_TEST_TMPDIR/$mode/home" "$BATS_TEST_TMPDIR/$mode/tmp" -mindepth 1 -print -quit)" ]
  cat >"$bin/fake-make" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/fake-make-calls"
STUB
  cat >"$bin/kubectl" <<'STUB'
#!/bin/bash
case "$*" in
  *'get secret vault-root'*) printf 'czNjcjN0LXJvb3QtdG9r' ;;
  *'get secret argocd-initial-admin-secret'*) printf 'aW5pdGlhbC1wYXNz' ;;
  *) : ;;
esac
STUB
  cat >"$bin/curl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/curl-args"
url=""; out=""; data=""; header_arg=""; code="200"; want_code=0
while (($#)); do
  case "$1" in
    http*) url="$1" ;;
    -o) shift; out="$1" ;;
    --data) shift; data="$1" ;;
    -H) shift; [[ "$1" == @* ]] && header_arg="$1" ;;
    -w) shift; want_code=1 ;;
  esac
  shift
done
if [[ "$header_arg" == @- ]]; then header="$(cat)"; elif [[ "$header_arg" == @* ]]; then header="$(cat "${header_arg#@}")"; else header=""; fi
case "$url" in
  *lookup-self)
    if [[ "$MAKE_TEST_ARGOCD_MODE" == vault-down ]] || { [[ "$MAKE_TEST_ARGOCD_MODE" == vault-flaky ]] && [ ! -f "$BATS_TEST_TMPDIR/$MAKE_TEST_ARGOCD_MODE/flaky" ]; }; then
      touch "$BATS_TEST_TMPDIR/$MAKE_TEST_ARGOCD_MODE/flaky"; exit 7
    fi
    [[ "$header" == 'X-Vault-Token: s3cr3t-root-tok' ]] || exit 22
    ;;
  *secret/data/argocd/admin)
    [[ "$header" == 'X-Vault-Token: s3cr3t-root-tok' ]] || exit 22
    printf '%s' '{"data":{"data":{"password":"vault-pass"}}}' ;;
  */api/v1/session)
    if [[ "$data" == @- ]]; then body="$(tr -d '\r\n' | "$REAL_JQ" -c .)"; else body="$(tr -d '\r\n' <"${data#@}" | "$REAL_JQ" -c .)"; fi
    printf '%s\n' "$body" >>"$BATS_TEST_TMPDIR/session-bodies"
    case "$body:$MAKE_TEST_ARGOCD_MODE" in
      '{"username":"admin","password":"vault-pass"}':stale) code=401 ;;
      '{"username":"admin","password":"initial-pass"}':stale) code=200 ;;
      '{"username":"admin","password":"vault-pass"}':rotated|'{"username":"admin","password":"vault-pass"}':vault-flaky) code=200 ;;
      *:unreachable) code=503 ;;
      *) code=400 ;;
    esac ;;
  *) printf '%s' '{"data":{"data":{"password":"other-pass"}}}' ;;
esac
if [[ "$out" == /dev/null ]]; then :; elif [[ -n "$out" ]]; then printf '{}'>"$out"; fi
[[ "$want_code" -eq 1 ]] && printf '%s' "$code"
exit 0
STUB
  cat >"$bin/mktemp" <<'STUB'
#!/bin/bash
printf called >>"$BATS_TEST_TMPDIR/mktemp-calls"
exec /usr/bin/mktemp "$@"
STUB
  cat >"$bin/jq" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/jq-args"
exec "$REAL_JQ" "$@"
STUB
  chmod +x "$bin"/*
  if env HOME="$BATS_TEST_TMPDIR/$mode/home" TMPDIR="$BATS_TEST_TMPDIR/$mode/tmp" PATH="$bin:$PATH" REAL_JQ="$real_jq" MAKE="$bin/fake-make" MAKE_TEST_ARGOCD_MODE="$mode" SHOW_SERVICE_PASSWORDS_ARGOCD_URL=http://argocd.test make --no-print-directory -f "$MAKEFILE" show-service-passwords >"$BATS_TEST_TMPDIR/$mode/stdout" 2>"$BATS_TEST_TMPDIR/$mode/stderr"; then
    SHOW_STATUS=0
  else
    SHOW_STATUS=$?
  fi
  stderr="$(cat "$BATS_TEST_TMPDIR/$mode/stderr")"
  output="$(cat "$BATS_TEST_TMPDIR/$mode/stdout")${stderr:+$'\n'}${stderr}"
}

@test "N1: every ArgoCD mode avoids mktemp and leaves TMPDIR empty" {
  for mode in stale rotated unreachable; do
    run_show_service_passwords "$mode"
    [ "$SHOW_STATUS" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/mktemp-calls" ]
    [ -z "$(find "$BATS_TEST_TMPDIR/$mode/tmp" -mindepth 1 -print -quit)" ]
  done
}

@test "N2: secret target uses stdin-only transport and detector positive controls" {
  target="$(show_service_passwords_full_target)"
  [[ "$target" != *mktemp* && "$target" != *--rawfile* && "$target" != *'--arg password'* && "$target" != *'<<<'* && "$target" != *'<<'* ]]
  [[ "$target" == *'--data @-'* && "$target" == *'-H @-'* ]]
  # shellcheck disable=SC2016,SC2154
  fixture='x <<<"$$y"'
  [[ "$fixture" == *'<<<'* ]]
  # shellcheck disable=SC2016,SC2154
  fixture='printf x > "$$f"'
  [[ "$fixture" == *'>'* ]]
}

@test "credential values stay out of curl and jq argv" {
  for mode in stale rotated unreachable; do
    run_show_service_passwords "$mode"
    [ "$SHOW_STATUS" -eq 0 ]
    run grep -E 's3cr3t-root-tok|vault-pass|initial-pass' "$BATS_TEST_TMPDIR/curl-args" "$BATS_TEST_TMPDIR/jq-args"
    [ "$status" -eq 1 ]
  done
}

@test "liveness gate retries and restarts port-forward" {
  run_show_service_passwords vault-flaky
  [ "$SHOW_STATUS" -eq 0 ]
  [ "$(grep -c install-vault-port-forward "$BATS_TEST_TMPDIR/fake-make-calls")" -eq 1 ]
  run_show_service_passwords vault-down
  [ "$SHOW_STATUS" -ne 0 ]
  [[ "$output" == *'ERROR: Vault unreachable at 127.0.0.1:18200'* ]]
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
  [ "$SHOW_STATUS" -eq 0 ]
  [[ "$output" == *"password: initial-pass"* ]]
  [[ "$output" == *"Vault secret/argocd/admin is stale (rejected by ArgoCD)"* ]]
  [[ "$(cat "$BATS_TEST_TMPDIR/curl-args")" != *"vault-pass"* ]]
  [[ "$(cat "$BATS_TEST_TMPDIR/curl-args")" != *"initial-pass"* ]]
}

@test "show-service-passwords: accepted Vault candidate wins without a note" {
  run_show_service_passwords rotated
  [ "$SHOW_STATUS" -eq 0 ]
  [[ "$output" == *"password: vault-pass"* ]]
  [[ "$output" != *"note:"* ]]
}

@test "show-service-passwords: unreachable ArgoCD falls back with an unverified note" {
  run_show_service_passwords unreachable
  [ "$SHOW_STATUS" -eq 0 ]
  [[ "$output" == *"password: vault-pass"* ]]
  [[ "$output" == *"note:     not verified against ArgoCD"* ]]
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
    # shellcheck disable=SC2016
    run grep -nF 'password: $${'"${credential}" <<<"${block}"
    [ "${status}" -eq 0 ]
  done
}

@test "show-service-passwords: realm-user hint does not soften service admin" {
  target="$(awk '/^show-service-passwords:/,/^$/' "${MAKEFILE}")"
  block="$(awk '/_kc=/{ found=1 } found { print; if ($0 ~ /^\t?echo ""$/) exit }' <<<"${target}")"
  grep -q '_kc_hint=' <<<"${block}"
  # shellcheck disable=SC2016
  [ "$(grep -Fo '$$_kc_hint' <<<"${block}" | wc -l | tr -d ' ')" -eq 3 ]
  # shellcheck disable=SC2016
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

@test "M3: ArgoCD session bodies match each candidate exactly" {
  run_show_service_passwords stale
  [ "$SHOW_STATUS" -eq 0 ]
  printf '%s\n' '{"username":"admin","password":"vault-pass"}' '{"username":"admin","password":"initial-pass"}' >"$BATS_TEST_TMPDIR/expected-bodies"
  cmp "$BATS_TEST_TMPDIR/expected-bodies" "$BATS_TEST_TMPDIR/session-bodies"
  run_show_service_passwords rotated
  printf '%s\n' '{"username":"admin","password":"vault-pass"}' >"$BATS_TEST_TMPDIR/expected-bodies"
  cmp "$BATS_TEST_TMPDIR/expected-bodies" "$BATS_TEST_TMPDIR/session-bodies"
  run_show_service_passwords unreachable
  printf '%s\n' '{"username":"admin","password":"vault-pass"}' '{"username":"admin","password":"initial-pass"}' >"$BATS_TEST_TMPDIR/expected-bodies"
  cmp "$BATS_TEST_TMPDIR/expected-bodies" "$BATS_TEST_TMPDIR/session-bodies"
}

@test "M4: stdout matches captured pre-fix fixtures byte for byte" {
  for mode in stale rotated unreachable; do
    run_show_service_passwords "$mode"
    [ "$SHOW_STATUS" -eq 0 ]
    if [ "${CAPTURE_BASELINE:-0}" = 1 ]; then
      cp "$BATS_TEST_TMPDIR/$mode/stdout" "${BATS_TEST_DIRNAME}/../fixtures/show-service-passwords/$mode.out"
    else
      cmp "$BATS_TEST_DIRNAME/../fixtures/show-service-passwords/$mode.out" "$BATS_TEST_TMPDIR/$mode/stdout"
    fi
  done
}

@test "M5: Vault retry recovers and Vault down reports the existing error" {
  run_show_service_passwords vault-flaky
  [ "$SHOW_STATUS" -eq 0 ]
  [ "$(grep -c install-vault-port-forward "$BATS_TEST_TMPDIR/fake-make-calls")" -eq 1 ]
  cmp "$BATS_TEST_DIRNAME/../fixtures/show-service-passwords/rotated.out" "$BATS_TEST_TMPDIR/vault-flaky/stdout"
  run_show_service_passwords vault-down
  [ "$SHOW_STATUS" -ne 0 ]
  grep -F 'ERROR: Vault unreachable at 127.0.0.1:18200' <<<"$stderr"
}
