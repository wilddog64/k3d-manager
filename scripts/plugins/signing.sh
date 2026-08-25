#!/usr/bin/env bash
# scripts/plugins/signing.sh

set -euo pipefail

SIGNING_VAULT_PATH="${SIGNING_VAULT_PATH:-secret/cosign/signing}"
SIGNING_VAULT_POLICY="${SIGNING_VAULT_POLICY:-cosign-verify}"
SIGNING_ADMISSION_NAMESPACE="${SIGNING_ADMISSION_NAMESPACE:-kyverno}"
SIGNING_PUB_SECRET_NAME="${SIGNING_PUB_SECRET_NAME:-cosign-public-key}"
SIGNING_KEYCHAIN_SERVICE="${SIGNING_KEYCHAIN_SERVICE:-k3d-manager-signing}"
SIGNING_KEYCHAIN_KEY_ACCOUNT="${SIGNING_KEYCHAIN_KEY_ACCOUNT:-k3dm-cosign-key}"
SIGNING_KEYCHAIN_PASSWORD_ACCOUNT="${SIGNING_KEYCHAIN_PASSWORD_ACCOUNT:-k3dm-cosign-password}"
SIGNING_ESO_STORE="${SIGNING_ESO_STORE:-vault-backend}"
SIGNING_ESO_ROLE="${SIGNING_ESO_ROLE:-}"

function _signing_vault_key_exists() {
  local vault_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
  local vault_release="${2:-${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}}"
  local check_cmd
  printf -v check_cmd 'vault kv get -format=json %q >/dev/null 2>&1' "${SIGNING_VAULT_PATH}"
  _vault_exec --no-exit "${vault_ns}" "${check_cmd}" "${vault_release}" >/dev/null 2>&1
}

function _signing_generate_key_pair() {
  local workdir="${1:?work directory required}"
  local password=""
  password=$(_no_trace openssl rand -base64 32 | tr -d '\n' 2>/dev/null || true)
  [[ -n "${password}" ]] || return 1

  # Any future image-signing invocation must use --key env://COSIGN_KEY.
  (
    cd "${workdir}"
    COSIGN_PASSWORD="${password}" _no_trace _run_command -- cosign generate-key-pair
  ) || return 1

  SIGNING_GENERATED_PASSWORD="${password}"
  SIGNING_GENERATED_KEY_FILE="${workdir}/cosign.key"
  SIGNING_GENERATED_PUB_FILE="${workdir}/cosign.pub"
  [[ -s "${SIGNING_GENERATED_KEY_FILE}" && -s "${SIGNING_GENERATED_PUB_FILE}" ]]
}

function _signing_write_vault() {
  local vault_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
  local vault_release="${2:-${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}}"
  local key_file="${3:?private key file required}"
  local password="${4:?password required}"
  local pub_file="${5:?public key file required}"
  local key pub
  key="$(<"${key_file}")"
  pub="$(<"${pub_file}")"

  SIGNING_VAULT_VALUE_KEY="${key}" SIGNING_VAULT_VALUE_PASSWORD="${password}" \
    SIGNING_VAULT_VALUE_PUB="${pub}" _no_trace bash -c \
    'printf "vault kv put %q cosign.key=%q cosign.password=%q cosign.pub=%q\n" \
      "$1" "$SIGNING_VAULT_VALUE_KEY" "$SIGNING_VAULT_VALUE_PASSWORD" "$SIGNING_VAULT_VALUE_PUB"' \
    _ "${SIGNING_VAULT_PATH}" |
    _no_trace _vault_exec_stream --no-exit --stdin "${vault_ns}" "${vault_release}" -- sh -s
}

function _signing_backup_keychain() {
  local key_file="${1:?private key file required}" password="${2:?password required}"
  local key
  key="$(<"${key_file}")"
  _no_trace _secret_store_data "${SIGNING_KEYCHAIN_SERVICE}" \
    "${SIGNING_KEYCHAIN_KEY_ACCOUNT}" "${key}" "Cosign private key"
  _no_trace _secret_store_data "${SIGNING_KEYCHAIN_SERVICE}" \
    "${SIGNING_KEYCHAIN_PASSWORD_ACCOUNT}" "${password}" "Cosign password"
}

function _signing_apply_pub_externalsecret() {
  local template="${SCRIPT_DIR}/etc/signing/externalsecret-cosign-pub.yaml.tmpl"
  [[ -r "${template}" ]] || { _err "[signing] ESO template not found: ${template}"; return 1; }
  export SIGNING_ADMISSION_NAMESPACE SIGNING_PUB_SECRET_NAME
  # shellcheck disable=SC2016
  envsubst '$SIGNING_ADMISSION_NAMESPACE $SIGNING_PUB_SECRET_NAME' < "${template}" | _kubectl apply -f -
}

function _signing_apply_vault_policy() {
  local vault_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
  local vault_release="${2:-${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}}"
  local policy_file="${SCRIPT_DIR}/etc/signing/cosign-verify-policy.hcl"
  [[ -r "${policy_file}" ]] || { _err "[signing] Vault policy not found: ${policy_file}"; return 1; }
  _no_trace _vault_exec_stream --no-exit --stdin "${vault_ns}" "${vault_release}" -- \
    vault policy write "${SIGNING_VAULT_POLICY}" - < "${policy_file}"
}

function _signing_grant_eso_read() {
  local vault_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
  local vault_release="${2:-${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}}"
  local role="${SIGNING_ESO_ROLE}"
  if [[ -z "${role}" ]]; then
    role=$(_kubectl --no-exit get clustersecretstore "${SIGNING_ESO_STORE}" \
      -o jsonpath='{.spec.provider.vault.auth.kubernetes.role}' 2>/dev/null || true)
  fi
  if [[ -z "${role}" ]]; then
    _warn "[signing] could not resolve ESO Vault role from store ${SIGNING_ESO_STORE}; set SIGNING_ESO_ROLE to grant read on ${SIGNING_VAULT_PATH}"
    return 0
  fi

  local role_json policies bound_names bound_ns
  role_json=$(_vault_exec --no-exit "${vault_ns}" \
    "vault read -format=json auth/kubernetes/role/${role}" "${vault_release}" 2>/dev/null || true)
  if [[ -z "${role_json}" ]]; then
    _warn "[signing] could not read Vault role ${role}; skipping ESO read grant"
    return 0
  fi
  policies=$(printf '%s' "${role_json}" | jq -r '.data.token_policies // [] | join(",")')
  if printf '%s' "${policies}" | tr ',' '\n' | grep -qx "${SIGNING_VAULT_POLICY}"; then
    _info "[signing] ESO role ${role} already grants ${SIGNING_VAULT_POLICY}"
    return 0
  fi
  bound_names=$(printf '%s' "${role_json}" | jq -r '.data.bound_service_account_names // [] | join(",")')
  bound_ns=$(printf '%s' "${role_json}" | jq -r '.data.bound_service_account_namespaces // [] | join(",")')
  _vault_exec_stream --no-exit "${vault_ns}" "${vault_release}" -- \
    vault write "auth/kubernetes/role/${role}" \
      bound_service_account_names="${bound_names}" \
      bound_service_account_namespaces="${bound_ns}" \
      policies="${policies},${SIGNING_VAULT_POLICY}" \
      ttl=1h
  _info "[signing] granted ${SIGNING_VAULT_POLICY} read to ESO role ${role}"
}

function _signing_seed_vault_key() {
  local vault_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
  local vault_release="${2:-${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}}"
  (
    local workdir
    workdir="$(mktemp -d "${TMPDIR:-/tmp}/k3dm-signing.XXXXXX")"
    trap 'rm -rf -- "${workdir}"' EXIT
    _signing_generate_key_pair "${workdir}" || {
      _err "[signing] cosign key generation failed"
      return 1
    }
    _signing_write_vault "${vault_ns}" "${vault_release}" \
      "${SIGNING_GENERATED_KEY_FILE}" "${SIGNING_GENERATED_PASSWORD}" "${SIGNING_GENERATED_PUB_FILE}"
    _signing_backup_keychain "${SIGNING_GENERATED_KEY_FILE}" "${SIGNING_GENERATED_PASSWORD}"
  )
}

function signing_init() {
  local vault_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
  local vault_release="${2:-${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}}"
  _vault_login "${vault_ns}" "${vault_release}"
  if _signing_vault_key_exists "${vault_ns}" "${vault_release}"; then
    _info "[signing] Vault key already present at ${SIGNING_VAULT_PATH}; skipping seed"
  else
    _signing_seed_vault_key "${vault_ns}" "${vault_release}" || return 1
    _info "[signing] cosign key material seeded"
  fi
  _signing_apply_vault_policy "${vault_ns}" "${vault_release}"
  _signing_grant_eso_read "${vault_ns}" "${vault_release}"
  _signing_apply_pub_externalsecret
}

function signing_rotate_key() {
  local vault_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
  local vault_release="${2:-${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}}"
  _vault_login "${vault_ns}" "${vault_release}"
  _signing_seed_vault_key "${vault_ns}" "${vault_release}" || return 1
  _signing_apply_vault_policy "${vault_ns}" "${vault_release}"
  _signing_grant_eso_read "${vault_ns}" "${vault_release}"
  _signing_apply_pub_externalsecret
  _warn "[signing] key rotated; retain the old public key or re-sign old images for overlap"
}

function signing_status() {
  local vault_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
  local vault_release="${2:-${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}}"
  local key_status=absent keychain_status=absent pub_status=absent
  local status=0
  _vault_login "${vault_ns}" "${vault_release}"
  if _signing_vault_key_exists "${vault_ns}" "${vault_release}"; then key_status=present; else status=1; fi
  if declare -f _secret_load_data >/dev/null 2>&1 && \
    _secret_load_data "${SIGNING_KEYCHAIN_SERVICE}" "${SIGNING_KEYCHAIN_KEY_ACCOUNT}" >/dev/null 2>&1 && \
    _secret_load_data "${SIGNING_KEYCHAIN_SERVICE}" "${SIGNING_KEYCHAIN_PASSWORD_ACCOUNT}" >/dev/null 2>&1; then
    keychain_status=present
  else
    status=1
  fi
  if _kubectl --no-exit -n "${SIGNING_ADMISSION_NAMESPACE}" \
    get secret "${SIGNING_PUB_SECRET_NAME}" >/dev/null 2>&1; then
    pub_status=present
  else
    status=1
  fi
  printf 'vault_key=%s keychain_backup=%s eso_public_secret=%s\n' \
    "${key_status}" "${keychain_status}" "${pub_status}"
  return "${status}"
}
