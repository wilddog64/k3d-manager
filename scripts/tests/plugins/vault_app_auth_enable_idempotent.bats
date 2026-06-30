#!/usr/bin/env bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"

@test "vault app auth: skips enable when auth mount already exists" {
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
    printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/kubectl.log"
    return 0
  }

  _vault_policy_exists() {
    return 0
  }

  _vault_exec_stream() {
    printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/vault-stream.log"
    return 0
  }

  _vault_exec() {
    printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/vault.log"
    case "$*" in
      "--no-exit secrets vault auth list -format=json vault")
        printf '%s\n' '{"kubernetes-app/":{"type":"kubernetes"}}'
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }

  local ca_path="${BATS_TEST_TMPDIR}/app-ca.crt"
  printf '%s\n' "test-ca" > "${ca_path}"

  export APP_CLUSTER_API_URL="https://2.25.146.252:6443"
  export APP_CLUSTER_CA_CERT_PATH="${ca_path}"
  run configure_vault_app_auth
  [ "${status}" -eq 0 ]

  run cat "${BATS_TEST_TMPDIR}/vault.log"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--no-exit secrets vault auth list -format=json vault"* ]]

  run sh -c "grep -cF -- 'vault auth enable -path=kubernetes-app kubernetes' '${BATS_TEST_TMPDIR}/vault.log' || true"
  [ "${status}" -eq 0 ]
  [ "${output}" -eq 0 ]
}

@test "_vault_exec: passes VAULT_TOKEN as env arg instead of embedding it in shell command" {
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

  _vault_container_name() {
    printf '%s\n' "vault"
  }

  __vault_exec_kubectl() {
    printf '%s\n' "$*" > "${BATS_TEST_TMPDIR}/exec.log"
    return 0
  }

  _VAULT_SESSION_TOKENS["secrets/vault"]="hvs.test-token"

  run _vault_exec "secrets" "vault status" "vault"
  [ "${status}" -eq 0 ]

  run cat "${BATS_TEST_TMPDIR}/exec.log"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"-- env VAULT_TOKEN=hvs.test-token sh -lc vault status"* ]]
  [[ "${output}" != *"sh -lc VAULT_TOKEN="* ]]
}
