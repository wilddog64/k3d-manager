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
export HUB_VAULT_PROFILE="${HUB_VAULT_PROFILE:-laptop}"
case "${HUB_VAULT_PROFILE}" in
  hostinger)
    export HUB_VAULT_CSS_SERVER="${HUB_VAULT_CSS_SERVER:-http://vault.${VAULT_NS}.svc:8200}"
    export HUB_VAULT_USE_BRIDGE="${HUB_VAULT_USE_BRIDGE:-0}"
    ;;
  *)
    export HUB_VAULT_CSS_SERVER="${HUB_VAULT_CSS_SERVER:-http://vault-bridge.secrets.svc.cluster.local:8201}"
    export HUB_VAULT_USE_BRIDGE="${HUB_VAULT_USE_BRIDGE:-1}"
    ;;
esac

# Auto-unseal watchdog (Tier 3 P2a) — pinned image for the in-cluster unseal CronJob.
export VAULT_UNSEAL_IMAGE="${VAULT_UNSEAL_IMAGE:-hashicorp/vault:1.18.3}"
