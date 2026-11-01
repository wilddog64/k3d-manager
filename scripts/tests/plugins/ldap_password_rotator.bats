#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  TMPL="${REPO_ROOT}/etc/ldap/ldap-password-rotator.yaml.tmpl"
  RENDERED="${BATS_TEST_TMPDIR}/ldap-password-rotator.yaml"
  ROTATE="${BATS_TEST_TMPDIR}/rotate.sh"

  LDAP_NAMESPACE=identity \
  VAULT_NAMESPACE=secrets \
  LDAP_ROTATOR_IMAGE=alpine/k8s:1.31.4 \
  LDAP_ROTATION_SCHEDULE='0 0 1 * *' \
  LDAP_POD_LABEL='app.kubernetes.io/component=openldap' \
  LDAP_PORT=1389 \
  LDAP_BASE_DN='dc=home,dc=org' \
  LDAP_ADMIN_DN='cn=ldap-admin,dc=home,dc=org' \
  LDAP_USER_OU=ou=users \
  VAULT_ADDR='http://vault.secrets.svc:8200' \
  VAULT_ROOT_TOKEN_SECRET=vault-root \
  VAULT_ROOT_TOKEN_KEY=root_token \
  USERS_TO_ROTATE='chengkai.liang,test-user' \
  envsubst '$LDAP_NAMESPACE $VAULT_NAMESPACE $LDAP_ROTATOR_IMAGE $LDAP_ROTATION_SCHEDULE $LDAP_POD_LABEL $LDAP_PORT $LDAP_BASE_DN $LDAP_ADMIN_DN $LDAP_USER_OU $VAULT_ADDR $VAULT_ROOT_TOKEN_SECRET $VAULT_ROOT_TOKEN_KEY $USERS_TO_ROTATE' \
    < "$TMPL" > "$RENDERED"
  yq -r '.data["rotate.sh"]' "$RENDERED" > "$ROTATE"
}

@test "rendered rotator uses portable password generation" {
  run grep -F -- '/dev/urandom' "$ROTATE"
  [ "$status" -eq 0 ]
  run grep -F -- 'openssl' "$ROTATE"
  [ "$status" -ne 0 ]
}

@test "LDAP rotator decodes the Slack URL and passes it to curl" {
  notice="${BATS_TEST_TMPDIR}/notice.sh"
  capture="${BATS_TEST_TMPDIR}/curl-args"
  sed -n '/^[[:space:]]*slack_url=$(kubectl/,/^[[:space:]]*fi$/p' "$ROTATE" > "$notice"
  CAPTURE="$capture" /bin/sh -c '
    kubectl() { printf %s aHR0cHM6Ly9leGFtcGxlLmNvbS9ob29r; }
    base64() { [ "$1" = -d ] || return 1; command base64 -d; }
    curl() { printf "%s\n" "$@" > "$CAPTURE"; }
    . "$1"
  ' sh "$notice"
  run grep -Fx 'https://example.com/hook' "$capture"
  [ "$status" -eq 0 ]
}

@test "generate_password returns 48 lowercase hexadecimal characters without openssl" {
  function_text="${BATS_TEST_TMPDIR}/generate-password.sh"
  sed -n '/^generate_password() {/,/^}/p' "$ROTATE" > "$function_text"
  result="$(PATH="${BATS_TEST_TMPDIR}/no-openssl:/usr/bin:/bin" /bin/sh -c ". '$function_text'; generate_password")"
  [[ "$result" =~ ^[0-9a-f]{48}$ ]]
}

@test "empty password guard precedes the LDAP update" {
  guard_line="$(grep -nF 'if [ -z "$new_password" ]; then' "$ROTATE" | cut -d: -f1)"
  ldap_line="$(grep -nF 'if update_ldap_password ' "$ROTATE" | cut -d: -f1)"
  [ -n "$guard_line" ]
  [ -n "$ldap_line" ]
  [ "$guard_line" -lt "$ldap_line" ]
}

@test "Vault preflight precedes the user loop and does not use the token" {
  main_line="$(grep -nF 'main() {' "$ROTATE" | cut -d: -f1)"
  loop_line="$(grep -nF 'while IFS= read -r user' "$ROTATE" | cut -d: -f1)"
  preflight_line="$(grep -nF 'vault status -address=' "$ROTATE" | cut -d: -f1)"
  [ "$preflight_line" -gt "$main_line" ]
  [ "$preflight_line" -lt "$loop_line" ]
  run grep -Fq 'VAULT_TOKEN' <<<"$(sed -n "${preflight_line}p" "$ROTATE")"
  [ "$status" -ne 0 ]
}

@test "password rotator deploy derives the Vault address from VAULT_NS" {
  plugin="${BATS_TEST_TMPDIR}/ldap-function.sh"
  capture="${BATS_TEST_TMPDIR}/vault-addr"
  awk '/^function _ldap_deploy_password_rotator\(\)/,/^}$/' "${REPO_ROOT}/plugins/ldap.sh" > "$plugin"

  SCRIPT_DIR="$REPO_ROOT" \
  VAULT_NS=secrets \
  CAPTURE="$capture" \
  bash -c '
    _info() { :; }
    _warn() { :; }
    _kubectl() { cat >/dev/null; printf "%s" "$VAULT_ADDR" > "$CAPTURE"; }
    envsubst() { cat; }
    export SCRIPT_DIR VAULT_NS CAPTURE
    source "$1"
    _ldap_deploy_password_rotator identity
  ' bash "$plugin"

  [ "$(<"$capture")" = 'http://vault.secrets.svc:8200' ]
  run grep -Fq 'vault.vault.svc' "${REPO_ROOT}/plugins/ldap.sh"
  [ "$status" -ne 0 ]
}

@test "LDAP rotator notice reports failures, skips and success safely" {
  block="$BATS_TEST_TMPDIR/notice.sh"
  awk '/if \[ -n "\$slack_url" \]; then/ { print "set -eu"; capture=1 } capture { sub(/^ +/, ""); print; if ($0 == "fi") exit }' "$ROTATE" > "$block"
  mkdir -p "$BATS_TEST_TMPDIR/stubs"
  cat > "$BATS_TEST_TMPDIR/stubs/curl" <<'STUB'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then shift; printf '%s' "${REPLY_BODY:-no_service}" > "$1"; fi
  shift
done
printf '%s' "$HTTP_STATUS"
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/curl"
  run env PATH="$BATS_TEST_TMPDIR/stubs:$PATH" slack_url='https://secret-webhook-marker' HTTP_STATUS=404 /bin/sh "$block"
  [ "$status" -eq 0 ]
  [[ "$output" == *'WARN slack notice not delivered: HTTP 404 no_service'* ]]
  [[ "$output" != *'secret-webhook-marker'* ]]
  run env PATH="$BATS_TEST_TMPDIR/stubs:$PATH" slack_url='https://secret-webhook-marker' HTTP_STATUS=200 /bin/sh "$block"
  [ "$status" -eq 0 ]
  [[ "$output" != *WARN* ]]
  run env PATH="$BATS_TEST_TMPDIR/stubs:$PATH" slack_url='' HTTP_STATUS=200 /bin/sh "$block"
  [ "$status" -eq 0 ]
  [[ "$output" == *'WARN slack notice skipped'* ]]
  run env PATH="$BATS_TEST_TMPDIR/stubs:$PATH" slack_url='https://secret-webhook-marker' HTTP_STATUS=404 REPLY_BODY='https://secret-webhook-marker' /bin/sh "$block"
  [ "$status" -eq 0 ]
  [[ "$output" != *'secret-webhook-marker'* ]]
}
