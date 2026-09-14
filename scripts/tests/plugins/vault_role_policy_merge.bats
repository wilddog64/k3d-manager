#!/usr/bin/env bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"

setup() {
  _err() {
    printf '%s\n' "$*" >&2
    return 1
  }

  _warn() {
    :
  }

  _info() {
    :
  }

  SCRIPT_DIR="${REPO_ROOT}/scripts"
  PLUGINS_DIR="${BATS_TEST_TMPDIR}/plugins"
  mkdir -p "${PLUGINS_DIR}"
  printf '%s\n' '#!/usr/bin/env bash' > "${PLUGINS_DIR}/eso.sh"

  source "${REPO_ROOT}/scripts/plugins/vault.sh"

  _vault_login() {
    :
  }

  _kubectl() {
    return 0
  }

  _vault_policy_exists() {
    return 0
  }

  _vault_exec_stream() {
    cat >/dev/null
    return 0
  }

  _no_trace() {
    "$@"
  }

  _vault_exec() {
    printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/vault.log"
    if [[ "$*" == *"vault read -format=json"* ]]; then
      printf '%s\n' "${ROLE_JSON:-}"
    fi
    return 0
  }
}

@test "_vault_role_merged_policies: desired first, existing extras appended, default and duplicates dropped" {
  ROLE_JSON='{"data":{"token_policies":["default","eso-apps","cosign-verify","bad name"]}}'

  run _vault_role_merged_policies secrets vault auth/kubernetes/role/r "eso-apps,eso-ldap-directory"

  [ "${status}" -eq 0 ]
  [ "${output}" = "eso-apps,eso-ldap-directory,cosign-verify" ]
}

@test "_vault_role_merged_policies: unreadable role yields desired only" {
  ROLE_JSON='Error reading'

  run _vault_role_merged_policies secrets vault auth/kubernetes/role/r app-cluster-reader

  [ "${status}" -eq 0 ]
  [ "${output}" = "app-cluster-reader" ]
}

@test "_vault_role_merged_policies shell-escapes the role path in the read command" {
  ROLE_JSON=''

  run _vault_role_merged_policies secrets vault 'auth/kubernetes/role/r x;id' app-cluster-reader

  [ "${status}" -eq 0 ]
  grep -q 'role/r\\ x\\;id' "${BATS_TEST_TMPDIR}/vault.log"
  run grep -q 'role/r x;id' "${BATS_TEST_TMPDIR}/vault.log"
  [ "${status}" -ne 0 ]
}

@test "configure_vault_app_auth preserves an existing cosign-verify grant" {
  ROLE_JSON='{"data":{"token_policies":["app-cluster-reader","cosign-verify"]}}'
  local ca_path="${BATS_TEST_TMPDIR}/app-ca.crt"
  printf '%s\n' test-ca > "${ca_path}"
  export APP_CLUSTER_API_URL="https://2.25.146.252:6443"
  export APP_CLUSTER_CA_CERT_PATH="${ca_path}"

  run configure_vault_app_auth

  [ "${status}" -eq 0 ]
  run awk '/vault read -format=json/ && /auth\/kubernetes-app\/role\/eso-app-cluster/' "${BATS_TEST_TMPDIR}/vault.log"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"auth/kubernetes-app/role/eso-app-cluster"* ]]
  run awk '/role\/eso-app-cluster/ && /policies=app-cluster-reader,cosign-verify/' "${BATS_TEST_TMPDIR}/vault.log"
  [ "${status}" -eq 0 ]
}

@test "_vault_configure_secret_reader_role preserves an existing cosign-verify grant" {
  ROLE_JSON='{"data":{"token_policies":["default","eso-apps","eso-ldap-directory","cosign-verify"]}}'

  run _vault_configure_secret_reader_role secrets vault eso-ldap-sa identity secret ldap eso-ldap-directory

  [ "${status}" -eq 0 ]
  run awk '/auth\/kubernetes\/role\/eso-ldap-directory/ && /policies="eso-apps,eso-ldap-directory,cosign-verify"/' "${BATS_TEST_TMPDIR}/vault.log"
  [ "${status}" -eq 0 ]
}
