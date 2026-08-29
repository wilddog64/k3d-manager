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

# --- Admission verification (Kyverno) -----------------------------------------
SIGNING_KYVERNO_HELM_REPO_NAME="${SIGNING_KYVERNO_HELM_REPO_NAME:-kyverno}"
SIGNING_KYVERNO_HELM_REPO_URL="${SIGNING_KYVERNO_HELM_REPO_URL:-https://kyverno.github.io/kyverno/}"
SIGNING_KYVERNO_HELM_CHART_REF="${SIGNING_KYVERNO_HELM_CHART_REF:-kyverno/kyverno}"
SIGNING_KYVERNO_HELM_RELEASE="${SIGNING_KYVERNO_HELM_RELEASE:-kyverno}"
# A08: pin the chart version explicitly -- never floating latest.
SIGNING_KYVERNO_HELM_CHART_VERSION="${SIGNING_KYVERNO_HELM_CHART_VERSION:-3.9.0}"
SIGNING_POLICY_NAME="${SIGNING_POLICY_NAME:-verify-first-party-images}"
SIGNING_IMAGE_REFERENCES="${SIGNING_IMAGE_REFERENCES:-ghcr.io/wilddog64/*}"
# D2: default to Audit. Enforce is a gated, deliberate flip (see deploy_image_signing).
SIGNING_VALIDATION_FAILURE_ACTION="${SIGNING_VALIDATION_FAILURE_ACTION:-Audit}"
SIGNING_WEBHOOK_FAILURE_POLICY="${SIGNING_WEBHOOK_FAILURE_POLICY:-Ignore}"

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

function _signing_install_kyverno() {
  local skip_repo_ops=0
  case "${SIGNING_KYVERNO_HELM_CHART_REF}" in
    /*|./*|../*|file://*) skip_repo_ops=1 ;;
  esac
  case "${SIGNING_KYVERNO_HELM_REPO_URL}" in
    ""|/*|./*|../*|file://*) skip_repo_ops=1 ;;
  esac

  if (( ! skip_repo_ops )); then
    _helm repo add "${SIGNING_KYVERNO_HELM_REPO_NAME}" "${SIGNING_KYVERNO_HELM_REPO_URL}"
    _helm repo update >/dev/null 2>&1
  fi

  local -a helm_args=(--create-namespace)
  if [[ -n "${SIGNING_KYVERNO_HELM_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${SIGNING_KYVERNO_HELM_CHART_VERSION}")
  fi
  local _set
  for _set in ${SIGNING_KYVERNO_HELM_SET:-}; do
    helm_args+=(--set "${_set}")
  done

  _helm upgrade --install \
    -n "${SIGNING_ADMISSION_NAMESPACE}" \
    "${SIGNING_KYVERNO_HELM_RELEASE}" \
    "${SIGNING_KYVERNO_HELM_CHART_REF}" \
    "${helm_args[@]}"
}

function _signing_wait_kyverno() {
  _kubectl --no-exit -n "${SIGNING_ADMISSION_NAMESPACE}" wait \
    --for=condition=available --timeout=180s \
    deployment -l app.kubernetes.io/part-of=kyverno >/dev/null 2>&1
}

function _signing_wait_pub_secret() {
  local _tries="${SIGNING_PUB_SECRET_WAIT_TRIES:-30}" _i=0
  while (( _i < _tries )); do
    if _kubectl --no-exit -n "${SIGNING_ADMISSION_NAMESPACE}" \
      get secret "${SIGNING_PUB_SECRET_NAME}" \
      -o 'jsonpath={.data.cosign\.pub}' 2>/dev/null | grep -q .; then
      return 0
    fi
    _i=$(( _i + 1 ))
    sleep 5
  done
  _err "[signing] ESO did not populate ${SIGNING_ADMISSION_NAMESPACE}/${SIGNING_PUB_SECRET_NAME} in time"
  return 1
}

function _signing_render_policy() {
  local pub_file="${1:?public key file required}"
  local template="${2:?policy template required}"
  export SIGNING_POLICY_NAME SIGNING_IMAGE_REFERENCES \
    SIGNING_VALIDATION_FAILURE_ACTION SIGNING_WEBHOOK_FAILURE_POLICY
  # shellcheck disable=SC2016
  envsubst '$SIGNING_POLICY_NAME $SIGNING_IMAGE_REFERENCES $SIGNING_VALIDATION_FAILURE_ACTION $SIGNING_WEBHOOK_FAILURE_POLICY' \
    < "${template}" |
    awk -v pf="${pub_file}" '
      /^# __PUBLIC_KEY__$/ {
        while ((getline line < pf) > 0) { print "                      " line }
        close(pf)
        next
      }
      { print }
    '
}

function _signing_apply_cluster_policy() {
  local template="${SCRIPT_DIR}/etc/signing/cluster-policy-verify-images.yaml.tmpl"
  [[ -r "${template}" ]] || { _err "[signing] policy template not found: ${template}"; return 1; }

  local pub_file
  pub_file="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${pub_file}'" RETURN

  _kubectl --no-exit -n "${SIGNING_ADMISSION_NAMESPACE}" get secret "${SIGNING_PUB_SECRET_NAME}" \
    -o jsonpath='{.data.cosign\.pub}' 2>/dev/null | base64 -d > "${pub_file}" || true
  if [[ ! -s "${pub_file}" ]] || ! grep -q "BEGIN PUBLIC KEY" "${pub_file}"; then
    _err "[signing] no valid cosign.pub in ${SIGNING_ADMISSION_NAMESPACE}/${SIGNING_PUB_SECRET_NAME}; run signing_init first"
    return 1
  fi

  _signing_render_policy "${pub_file}" "${template}" | _kubectl apply -f -
}

function deploy_image_signing() {
  local vault_ns="${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}"
  local vault_release="${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}"
  local action="${SIGNING_VALIDATION_FAILURE_ACTION}"
  local app_cluster=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --audit) action="Audit"; shift ;;
      --enforce) action="Enforce"; shift ;;
      --app-cluster|--skip-vault-init) app_cluster=1; shift ;;
      -h|--help)
        cat <<'USAGE'
Usage: deploy_image_signing [--audit|--enforce] [--app-cluster]

Install Kyverno (pinned chart) and apply the first-party cosign verifyImages
ClusterPolicy scoped to the shopping-cart app namespaces.

  --audit        (default) failureAction=Audit -- report would-be-blocks only.
  --enforce      reject unsigned first-party pods. GATED (decision D2): only after
                 the Audit PolicyReports show zero would-be-blocks for current
                 first-party images. Requires SIGNING_ALLOW_ENFORCE=1 to confirm.
  --app-cluster  target a remote app cluster (no hub Vault): skip signing_init and
                 pull cosign.pub via the ESO ClusterSecretStore. Alias:
                 --skip-vault-init.
USAGE
        return 0 ;;
      *) _err "[signing] Unknown option: $1"; return 1 ;;
    esac
  done

  if [[ "${action}" == "Enforce" && "${SIGNING_ALLOW_ENFORCE:-0}" != "1" ]]; then
    _err "[signing] --enforce is gated: confirm Audit is clean, then set SIGNING_ALLOW_ENFORCE=1 (D2)."
    return 1
  fi
  SIGNING_VALIDATION_FAILURE_ACTION="${action}"

  if (( app_cluster )); then
    _info "[signing] --app-cluster: skipping hub Vault init; cosign.pub arrives via ESO ClusterSecretStore ${SIGNING_ESO_STORE}"
  else
    _info "[signing] ensuring cosign key material (idempotent)"
    signing_init "${vault_ns}" "${vault_release}" || return 1
  fi

  _info "[signing] installing Kyverno (chart ${SIGNING_KYVERNO_HELM_CHART_VERSION})"
  _signing_install_kyverno || return 1
  if ! _signing_wait_kyverno; then
    _err "[signing] Kyverno did not become Ready"
    return 1
  fi

  if (( app_cluster )); then
    _info "[signing] applying cosign.pub ExternalSecret; waiting for ESO sync"
    _signing_apply_pub_externalsecret || return 1
    _signing_wait_pub_secret || return 1
  fi

  _info "[signing] applying verifyImages ClusterPolicy (${SIGNING_VALIDATION_FAILURE_ACTION})"
  _signing_apply_cluster_policy || return 1

  if [[ "${SIGNING_VALIDATION_FAILURE_ACTION}" == "Enforce" ]]; then
    _warn "[signing] ${SIGNING_POLICY_NAME} is ENFORCING on shopping-cart-apps/shopping-cart-payment"
  else
    _info "[signing] ${SIGNING_POLICY_NAME} in Audit -- inspect PolicyReports before --enforce"
  fi
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
