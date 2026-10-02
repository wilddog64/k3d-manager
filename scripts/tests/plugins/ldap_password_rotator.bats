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
  ! sed -n "${preflight_line}p" "$ROTATE" | grep -Fq 'VAULT_TOKEN'
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
  ! grep -Fq 'vault.vault.svc' "${REPO_ROOT}/plugins/ldap.sh"
}
