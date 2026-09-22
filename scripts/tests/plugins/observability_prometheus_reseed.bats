#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/observability.sh"
}

stub_prometheus_reseed() {
  _observability_prometheus_auth_file() { printf '%s/auth.env\n' "${BATS_TEST_TMPDIR}"; }
  _kubectl() { printf 'test-vault-token\n'; }
  htpasswd() { printf 'admin:$2a$test-hash\n'; }
  _observability_prometheus_vault_payload() {
    printf '{"password":"%s","hash":"%s"}' "$1" "$2"
  }
}

@test "prometheus reseed: healthy Vault credential does not write" {
  local calls="${BATS_TEST_TMPDIR}/calls"
  stub_prometheus_reseed
  curl() {
    printf 'read\n' >> "${calls}"
    printf '{"data":{"data":{"user":"admin","password":"vault-password"}}}\n'
  }

  run _observability_ensure_prometheus_login
  [ "${status}" -eq 0 ]
  [ "$(grep -c '^read$' "${calls}")" -eq 1 ]
  [ "$(grep -c 'POST' "${calls}" 2>/dev/null || true)" -eq 0 ]
}

@test "prometheus reseed: readable cache password is reused" {
  local calls="${BATS_TEST_TMPDIR}/calls"
  stub_prometheus_reseed
  printf '%s\n' 'PROMETHEUS_BASIC_AUTH_USER=cache-user' 'PROMETHEUS_BASIC_AUTH_PASSWORD=recovered-password' > "${BATS_TEST_TMPDIR}/auth.env"
  curl() {
    if [[ "$*" == *"--request POST"* ]]; then
      [[ "$*" == *"recovered-password"* ]] && printf 'recovered\n' >> "${calls}" || return 1
      return 0
    fi
    return 22
  }

  run _observability_ensure_prometheus_login
  [ "${status}" -eq 0 ]
  grep -Fx 'recovered' "${calls}"
  ! grep -F 'test-vault-token' "${calls}"
}

@test "prometheus reseed: missing cache generates and writes a credential" {
  local calls="${BATS_TEST_TMPDIR}/calls"
  stub_prometheus_reseed
  _observability_generate_prometheus_basic_auth() {
    printf 'generated\n' >> "${calls}"
    _PROM_BASIC_AUTH_PASSWORD='generated-password'
    _PROM_BASIC_AUTH_BCRYPT='generated-hash'
  }
  curl() {
    [[ "$*" == *"--request POST"* ]] && printf 'posted\n' >> "${calls}" || return 22
  }

  run _observability_ensure_prometheus_login
  [ "${status}" -eq 0 ]
  grep -Fx 'generated' "${calls}"
  grep -Fx 'posted' "${calls}"
}

@test "prometheus reseed: literal password cache value is unusable" {
  local calls="${BATS_TEST_TMPDIR}/calls"
  stub_prometheus_reseed
  printf '%s\n' 'PROMETHEUS_BASIC_AUTH_USER=admin' 'PROMETHEUS_BASIC_AUTH_PASSWORD=password' > "${BATS_TEST_TMPDIR}/auth.env"
  _observability_generate_prometheus_basic_auth() {
    printf 'generated\n' >> "${calls}"
    _PROM_BASIC_AUTH_PASSWORD='fresh-password'
    _PROM_BASIC_AUTH_BCRYPT='fresh-hash'
  }
  curl() {
    [[ "$*" == *"--request POST"* ]] && printf 'posted\n' >> "${calls}" || return 22
  }

  run _observability_ensure_prometheus_login
  [ "${status}" -eq 0 ]
  grep -Fx 'generated' "${calls}"
  ! grep -Fx 'password' "${calls}"
}

@test "prometheus reseed: failed write remains a failure through refresh" {
  stub_prometheus_reseed
  curl() { return 22; }

  run _observability_ensure_prometheus_login
  [ "${status}" -ne 0 ]
  run _observability_refresh_prometheus_auth_proxy
  [ "${status}" -ne 0 ]
}
