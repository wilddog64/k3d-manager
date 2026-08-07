#!/usr/bin/env bats

LDAP_PLUGIN="${BATS_TEST_DIRNAME}/../../plugins/ldap.sh"

@test "LDAP chart passwords: only sed-safe values are retained" {
  run bash -c '
    _err() { :; }
    _no_trace() { "$@"; }
    source "$1"
    _ldap_password_is_chart_safe "safePassword_123.-"
    ! _ldap_password_is_chart_safe "unsafe/password"
    ! _ldap_password_is_chart_safe "unsafe&password"
  ' _ "${LDAP_PLUGIN}"
  [ "$status" -eq 0 ]
}

@test "LDAP chart passwords: generated values are delimiter-safe hex" {
  run bash -c '
    _err() { :; }
    _no_trace() { "$@"; }
    source "$1"
    password=$(_ldap_generate_chart_safe_password)
    [[ "$password" =~ ^[0-9a-f]{48}$ ]]
  ' _ "${LDAP_PLUGIN}"
  [ "$status" -eq 0 ]
}
