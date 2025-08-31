export TENANT_ID="$(_az account show --query tenantId -o tsv 2>/dev/null)"
export KV_ID="${KV_ID:-$(az keyvault show --name "${KV_NAME}" --query id -o tsv)}"
# Fixed, predictable infra anchors for ESO
export ESO_RG="rg-k3d-eso"
export ESO_LOC="westus3"
export ESO_KV_NAME="kv-k3d-eso"
export ESO_APP_NAME="eso-${ESO_KV_NAME}-$(date +%s)"
export ESO_APP_ID="$(az ad app create --display-name azure-eso --query appId -o tsv)"
# Optional: set true to require RBAC-enabled KV (recommended)
export ESO_KV_REQUIRE_RBAC=true
