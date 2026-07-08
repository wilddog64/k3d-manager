# Core namespace defaults
export VAULT_NS="${VAULT_NS:-secrets}"

# PKI toggles (optional; only used if VAULT_ENABLE_PKI=1)
export VAULT_ENABLE_PKI="${VAULT_ENABLE_PKI:-1}"         # 1 to enable PKI bootstrap
export VAULT_PKI_PATH="${VAULT_PKI_PATH:-pki}"           # mount path (e.g. pki or pki_int)
export VAULT_PKI_ROLE="${VAULT_PKI_ROLE:-jenkins-tls}"   # role name to create/update
export VAULT_PKI_CN="${VAULT_PKI_CN:-dev.k3d.internal}"      # root CA CN (for root mode)
export VAULT_PKI_MAX_TTL="${VAULT_PKI_MAX_TTL:-87600h}"  # CA max TTL (10y)
export VAULT_PKI_ROLE_TTL="${VAULT_PKI_ROLE_TTL:-720h}"  # leaf max TTL
export VAULT_PKI_ALLOWED="${VAULT_PKI_ALLOWED:-}"        # comma list (e.g. jenkins.dev.k3d.internal,*.svc)
export VAULT_PKI_ENFORCE_HOSTNAMES="${VAULT_PKI_ENFORCE_HOSTNAMES:-true}"  # true/false
export VAULT_ENDPOINT="${VAULT_ENDPOINT:-http://vault.${VAULT_NS}.svc:8200}"

# Hub Vault location profile (Tier 3 relocation seam).
#   laptop    — hub Vault on the Mac, reached via reverse-tunnel + socat bridge (default; today's path)
#   hostinger — hub Vault in-cluster on the Hostinger app cluster (primary; functional after P2)
# Persisted failover state (Tier 3 P4): keyed by app-cluster context when one can be resolved,
# so ACG/Hostinger do not share one global profile. Explicit env wins over the file; an absent
# or invalid file leaves the default 'laptop' untouched (behavior-preserving).
function _hub_vault_profile_context() {
  if [[ -n "${APP_CONTEXT:-}" ]]; then
    printf '%s\n' "${APP_CONTEXT}"
    return 0
  fi
  if declare -f _shopping_cart_resolve_app_context >/dev/null 2>&1; then
    _shopping_cart_resolve_app_context 2>/dev/null || true
    return 0
  fi
  if declare -f _acg_provider_context >/dev/null 2>&1 && declare -f _acg_resolve_provider >/dev/null 2>&1; then
    _acg_provider_context "$(_acg_resolve_provider 2>/dev/null || printf '%s' k3s-aws)" 2>/dev/null || true
    return 0
  fi
  printf '\n'
}

if [[ -z "${HUB_VAULT_PROFILE_STATE_FILE:-}" ]]; then
  _hub_state_dir="${K3DM_STATE_DIR:-${HOME}/.local/share/k3d-manager}"
  _hub_legacy_state_file="${_hub_state_dir}/hub-vault-profile"
  _hub_profile_context="$(_hub_vault_profile_context)"
  if [[ -n "${_hub_profile_context}" ]]; then
    _hub_profile_key="$(printf '%s' "${_hub_profile_context}" | tr -c 'A-Za-z0-9_.-' '_')"
    HUB_VAULT_PROFILE_STATE_FILE="${_hub_state_dir}/hub-vault-profile-${_hub_profile_key}"
    case "${_hub_profile_context}" in
      ubuntu-hostinger)
        if [[ ! -r "${HUB_VAULT_PROFILE_STATE_FILE}" && -r "${_hub_legacy_state_file}" ]]; then
          HUB_VAULT_PROFILE_STATE_FILE="${_hub_legacy_state_file}"
        fi
        ;;
    esac
  else
    HUB_VAULT_PROFILE_STATE_FILE="${_hub_legacy_state_file}"
  fi
  unset _hub_profile_key _hub_profile_context _hub_legacy_state_file _hub_state_dir
fi
export HUB_VAULT_PROFILE_STATE_FILE

if [[ -z "${HUB_VAULT_PROFILE:-}" && -r "${HUB_VAULT_PROFILE_STATE_FILE}" ]]; then
  _hub_persisted="$(tr -d '[:space:]' < "${HUB_VAULT_PROFILE_STATE_FILE}" 2>/dev/null || true)"
  case "${_hub_persisted}" in
    laptop|hostinger) HUB_VAULT_PROFILE="${_hub_persisted}" ;;
  esac
  unset _hub_persisted
fi
export HUB_VAULT_PROFILE="${HUB_VAULT_PROFILE:-laptop}"
case "${HUB_VAULT_PROFILE}" in
  hostinger)
    export HUB_VAULT_CSS_SERVER="${HUB_VAULT_CSS_SERVER:-http://vault.${VAULT_NS}.svc:8200}"
    export HUB_VAULT_USE_BRIDGE="${HUB_VAULT_USE_BRIDGE:-0}"
    export HUB_VAULT_CSS_AUTH="${HUB_VAULT_CSS_AUTH:-kubernetes}"
    ;;
  *)
    export HUB_VAULT_CSS_SERVER="${HUB_VAULT_CSS_SERVER:-http://vault-bridge.secrets.svc.cluster.local:8201}"
    export HUB_VAULT_USE_BRIDGE="${HUB_VAULT_USE_BRIDGE:-1}"
    export HUB_VAULT_CSS_AUTH="${HUB_VAULT_CSS_AUTH:-token}"
    ;;
esac

# Auto-unseal watchdog (Tier 3 P2a) — pinned image for the in-cluster unseal CronJob.
export VAULT_UNSEAL_IMAGE="${VAULT_UNSEAL_IMAGE:-hashicorp/vault:1.18.3}"
