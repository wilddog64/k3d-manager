TENANT_ID="$(_az account show --query tenantId -o tsv 2>/dev/null)"
export TENANT_ID
KV_ID="${KV_ID:-${KV_NAME:+$(az keyvault show --name "${KV_NAME}" --query id -o tsv)}}"
export KV_ID
# Fixed, predictable infra anchors for ESO
ESO_RG="rg-k3d-eso"
export ESO_RG
ESO_LOC="westus3"
export ESO_LOC
ESO_KV_NAME="kv-k3d-eso"
export ESO_KV_NAME
ESO_APP_NAME="eso-${ESO_KV_NAME}-$(date +%s)"
export ESO_APP_NAME
ESO_APP_ID="$(az ad app create --display-name azure-eso --query appId -o tsv)"
export ESO_APP_ID
# Optional: set true to require RBAC-enabled KV (recommended)
ESO_KV_REQUIRE_RBAC=true
export ESO_KV_REQUIRE_RBAC
