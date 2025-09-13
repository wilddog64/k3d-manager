#!/usr/bin/env bash

# shellcheck disable=SC1090
az_eso_vars="${SCRIPT_DIR}/etc/azure/azure-vars.sh"
if [[ -r "${az_eso_vars}" ]]; then
   source "${az_eso_vars}"
fi

function _ensure_azure_cli() {
   if command_exist az ; then
      return 0
   fi

   if _is_mac && command_exist brew ; then
      brew install azure-cli
      return 0
   fi

   if _is_debian_family ; then
      curl -sL https://aka.ms/InstallAzureCLIDeb | _run_command --require-sudo -- bash
   elif _is_redhat_family ; then
      _run_command --require-sudo -- dnf install -y https://packages.microsoft.com/config/centos/7/packages-microsoft-prod.rpm
      _run_command --require-sudo -- dnf install -y azure-cli
   elif _is_wsl && grep -qi "debian" /etc/os-release &> /dev/null; then
      curl -sL https://aka.ms/InstallAzureCLIDeb | _run_command --require-sudo -- bash
   elif _is_wsl && grep -qi "redhat" /etc/os-release &> /dev/null; then
      _run_command --require-sudo -- dnf install -y https://packages.microsoft.com/config/centos/7/packages-microsoft-prod.rpm
      _run_command --require-sudo -- dnf install -y azure-cli
   else
      echo "Cannot install azure-cli: unsupported OS or missing package manager" >&2
      exit 127
   fi
}

function _az() {
   _ensure_azure_cli
   _run_command -- az "$@"
}

function _az_ok() {
   _az account show > /dev/null 2>&1
}

function create_az_sp() {
   local rg="${RG:-k3d-rg-eso}"
   local region=${REGION:-eastus}
   local kv_name="${KV_NAME:-k3d-kv-eso}"
   local secret_name="${SECRET_NAME:-k3d-sp-secret}"

   AZ_JSON=$(_az account show)

   _az keyvault create -n "${kv_name}" -g "${rg}" -l "${region}" --enable-rbac-authorization true > /dev/null
   _az keyvault secret set --vault-name "${kv_name}" -n "${secret_name}" --value "$(openssl rand -base64 32)"
   _az ad sp create-for-rbac -n "sp-${rg}-${kv_name}" --skip-assignment -o json > "${AZ_JSON}"
   _az role assignment create --assignee "$(jq -r .appId < "${AZ_JSON}")" --role "Key Vault Secrets User" --scope "$(_az keyvault show --name "${kv_name}" --query id -o tsv)" > /dev/null
}

function _install_azure_eso() {
   local ns="${NS:-azure-external-secrets}"

   _helm repo add external-secrets https://charts.external-secrets.io
   _helm repo update >/dev/null 2>&1

   echo '>>> install/upgrade external secrets operator <<<'
   _helm upgrade --install eso external-secrets/external-secrets  \
      --namespace "$ns" --create-namespace \
      --set installCRDs=true \
      --set serviceAccount.create=true \
      --set serviceAccount.name=azure-external-secrets \
      --set metrics.enabled=true \
      --set webhook.enabled=true \
      --wait --timeout 5m >/dev/null 2>&1
}

function _create_azure_eso_store() {
   local ns="${NS:-azure-external-secrets}"

   # shellcheck disable=SC2155
   local yamlfile="$(mktemp -t)"
   trap 'cleanup_on_success "'"$yamlfile"'"' EXIT INT TERM

   azure_config_template="${SCRIPT_DIR}/etc/azure/azure-eso.yaml.tmpl"
   if [[ ! -f "${azure_config_template}" ]]; then
      echo "Azure eso template file ${azure_config_template} not found!" >&2
      exit 127
   fi

   azure_vars="${SCRIPT_DIR}/etc/azure/azure-vars.sh"
   if [[ ! -f "${azure_vars}" ]]; then
      echo "Azure vars file ${azure_vars} not found!" >&2
      exit 127
   fi
   source "${azure_vars}"

   _kubectl create namespace "$ns" 2>/dev/null
   _kubectl apply -n "$ns" -f <(envsubst < "$azure_config_template") --dry-run=client | _kubectl apply -n "$ns" -f -
}

function deploy_azure_eso() {
   local ns="${NS:-azure-external-secrets}"
   local kv_name="${KV_NAME:-k3d-kv-eso}"
   local ns="${1:-azure-external-secrets}"

   _ensure_azure_cli
   if ! _az_ok; then
      echo "Please 'az login' first!" >&2
      exit 127
   fi


   _create_az_sp
   _install_azure_eso
   _create_azure_eso_store
}

#   eso_akv up   <resource-group> <keyvault-name> [namespace=external-secrets] [ttl_hours=8]
#   eso_akv down <keyvault-name>  [namespace=external-secrets]

# ---------- macOS TTL (BSD date) ----------
# sets END_ISO
function _compute_end_iso_macos() {
  local hours="$1"
  END_ISO="$(date -u -v+"${hours}"H '+%Y-%m-%dT%H:%M:%SZ')" || return 1
}

# ---------- context discovery ----------
# sets TENANT_ID, KV_ID, KV_URI (sub id not needed further)
# function _resolve_context() {
#   local rg="$1" kv="$2"
#   _az account show >/dev/null 2>&1 || { _err "not logged in to Azure CLI; run az login"; return 1; }
#   TENANT_ID="$(_az account show --query tenantId -o tsv 2>/dev/null)" || return 1
#   KV_ID="$(_az keyvault show -g "$rg" -n "$kv" --query id -o tsv 2>/dev/null)" || { _err "cannot find Key Vault ${kv} in RG ${rg}"; return 1; }
#   KV_URI="$(_az keyvault show -g "$rg" -n "$kv" --query properties.vaultUri -o tsv 2>/dev/null)" || { _err "cannot read Key Vault URI"; return 1; }
# }

# ---------- AAD app / SP lifecycle ----------

# sets CLIENT_SECRET; requires END_ISO
function _create_client_secret() {
  CLIENT_SECRET="$(_az ad app credential reset --id "$APP_ID" --display-name "azure-eso" --end-date "$END_ISO" --query password -o tsv 2>/dev/null)" \
    || { _err "failed to create client secret"; return 1; }
}

# ---------- Kubernetes bits ----------
function _ensure_namespace() {
  local ns="$1"
  _kubectl get ns "$ns" >/dev/null 2>&1 || _kubectl create ns "$ns" >/dev/null 2>&1 || { _err "cannot ensure namespace ${ns}"; return 1; }
}

function _update_k8s_secret() {
  local ns="$1" name="$2" key="$3" value="$4"
  _kubectl -n "$ns" create secret generic "$name" \
    --from-literal="$key=$value" \
    --dry-run=client -o yaml | _kubectl apply -f - || { _err "failed to create kubernetes secret ${name}"; return 1; }
}

function _apply_clustersecretstore() {
   local ns="${NS:-external-secrets}"

   # shellcheck disable=SC2155
   local yamlfile="$(mktemp -t)"
   trap 'cleanup_on_success "'"$yamlfile"'"' EXIT INT TERM
   local yamltempl="${SCRIPT_DIR}/etc/azure/azure-eso.yaml.tmpl"
   if [[ ! -f "${yamltempl}" ]]; then
      echo "Azure eso template file ${yamltempl} not found!" >&2
      exit 127
   fi

   envsbst < "$yamltempl" > "$yamlfile"
   _kubectl apply -n "$ns" --dry-run=client -f "$yamlfile" | \
      _kubectl apply -n "$ns" -f -

}

function _delete_k8s_resources() {
  local ns="$1" kv_name="$2"
  _kubectl delete clustersecretstore "azure-kv-${kv_name}" --ignore-not-found >/dev/null 2>&1
  _kubectl -n "$ns" delete secret azure-sp-eso --ignore-not-found >/dev/null 2>&1
}

# ---------- AAD cleanup ----------
function _find_latest_app_for_kv() {
  local kv="$1"
  _az ad app list --display-name "eso-${kv}-" --query "[].appId" -o tsv 2>/dev/null | tail -n1
}

function _remove_role_assignments_for() {
  local app_id="$1"

  # get all role assignment IDs for this principal
  local ids
  ids="$(_az role assignment list \
            --assignee "$app_id" \
            --query "[].id" \
            -o tsv 2>/dev/null)"

  # if nothing, bail quietly
  [[ -z "$ids" ]] && return 0

  # loop and delete with _az (no xargs, no subshell)
  while IFS= read -r id; do
    [[ -n "$id" ]] && _az role assignment delete --ids "$id" >/dev/null 2>&1 || true
  done <<<"$ids"
}

function _delete_sp_and_app() {
  local app_id="$1"
  _az ad sp delete --id "$app_id" >/dev/null 2>&1 || true
  local app_obj_id
  app_obj_id="$(_az ad app show --id "$app_id" --query id -o tsv 2>/dev/null || true)"
  [[ -n "$app_obj_id" ]] && _az ad app delete --id "$app_obj_id" >/dev/null 2>&1 || true
}

# ---------- public commands ----------
function eso_akv() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    up)   _eso_akv_up "$@";;
    down) _eso_akv_down "$@";;
    *)    printf 'usage: eso_akv {up|down}\n'; return 2;;
  esac
}

function _grant_kv_access() {
   if ! _az role assignment create --assignee "$APP_ID" --role "az-eso" --scope "$KV_ID" >/dev/null 2>&1; then
      _warn "RBAC assignment failed; trying access policy get/list"
      _az keyvalult set-policy -n "$(basename "$KV_ID")" \
         --spn "$APP_ID" --secret-permissions get list >/dev/null 2>&1 \
         || { _err "failed to grant Key Vault access"; }
   fi
}
function _eso_akv_up() {
  local ttl="${1:-8}"

  _compute_end_iso_macos "$ttl" ||  _err "could not compute TTL"
  _create_app_sp "$kv" || return 1
  _create_client_secret || return 1
  _grant_kv_access || return 1
  _ensure_namespace "$ns" || return 1
  _upsert_k8s_secret "$ns" "azure-sp-eso" "clientSecret" "$CLIENT_SECRET" || return 1
  _apply_clustersecretstore "$ns" "$kv" || return 1

  _info "ClusterSecretStore azure-kv-${kv} ready in namespace ${ns}"
  _info "Client secret for ${APP_ID} expires at ${END_ISO} UTC"
}

function _eso_akv_down() {
  local kv="${1:-}" ns="${2:-external-secrets}"
  [ -n "$kv" ] || { _err "key vault name required"; return 2; }

  _delete_k8s_resources "$ns" "$kv"

  local app_id
  app_id=$(_find_latest_app_for_kv "$kv")
  if [ -n "$app_id" ]; then
    _remove_role_assignments_for "$app_id"
    _delete_sp_and_app "$app_id"
    _info "deleted app and service principal for ${app_id}"
  else
    _warn "no matching app found for prefix eso-${kv}-"
  fi

  _info "cleanup complete"
}
