function _ensure_azure_cli() {
   if command_exist az ; then
      return 0
   fi

   if is_mac && command_exist brew ; then
      brew install azure-cli
      return 0
   fi

   if is_debian_family ; then
      curl -sL https://aka.ms/InstallAzureCLIDeb | _run_command --require-sudo -- bash
   elif is_redhat_family ; then
      _run_command --require-sudo -- dnf install -y https://packages.microsoft.com/config/centos/7/packages-microsoft-prod.rpm
      _run_command --require-sudo -- dnf install -y azure-cli
   elif is_wsl && grep -qi "debian" /etc/os-release &> /dev/null; then
      curl -sL https://aka.ms/InstallAzureCLIDeb | _run_command --require-sudo -- bash
   elif is_wsl && grep -qi "redhat" /etc/os-release &> /dev/null; then
      _run_command --require-sudo -- dnf install -y https://packages.microsoft.com/config/centos/7/packages-microsoft-prod.rpm
      _run_command --require-sudo -- dnf install -y azure-cli
   else
      echo "Cannot install azure-cli: unsupported OS or missing package manager" >&2
      exit 127
   fi
}

function _az() {
   _ensure_azure_cli >/dev/null 2>&1
   _run_command --quiet -- az "$@"
}

function _az() {
   _ensure_azure_cli
   _run_command -- az "$@"
}

function _az_ok() {
   _az account show > /dev/null 2>&1
}

function _create_az_sp() {
   local rg="${RG:-k3d-rg-eso}"
   local region=${REGION:-eastus}
   local kv_name="${KV_NAME:-k3d-kv-eso}"
   local secret_name="${SECRET_NAME:-k3d-sp-secret}"

   AZ_JSON=$(mktemp -t)
   _cleanup_on_success "$az_json" EXIT INT TERM

   _az keyvault create -n "${kv_name}" -g "${rg}" -l "${region}" --enable-rbac-authorization true > /dev/null
   _az keyvault secret set --vault-name "${kv_name}" -n "${secret_name}" --value "$(openssl rand -base64 32)
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
   local yamlfile="$(mktemp -t)"
   trap 'cleanup_on_success "'"$yamlfile"'"' EXIT INT TERM

   azure_config_template="${SCRIPT_DIR}/etc/azure/azure-eso.yaml.tmpl"
   if [[ ! -f "${azure_config_template}" ]]; then
      echo "Azure eso template file ${azure_config_template} not found!" >&2
      exit -1
   fi

   azure_vars="${SCRIPT_DIR}/etc/azure/azure-vars.sh"
   if [[ ! -f "${azure_vars}" ]]; then
      echo "Azure vars file ${azure_vars} not found!" >&2
      exit -1
   fi
   source "${azure_vars}"

   _kubectl create namespace "${NS:-azure-external-secrets}" 2>/dev/null
   _kubectl apply -n "${NS:-azure-external-secrets}" -f <(envsubst < "$azure_config_template") --dry-run=cient | _kubectl apply -n "" -f -
}

function deploy_azure_eso() {
   local ns="${NS:-azure-external-secrets}"
   local rg="${RG:-k3d-rg-eso}"
   local region=${REGION:-eastus}
   local kv_name="${KV_NAME:-k3d-kv-eso}"
   local secret_name="${SECRET_NAME:-k3d-sp-secret}"
   local ns="${1:-azure-external-secrets}"

   _ensure_azure_cli
   if ! _az_ok; then
      echo "Please 'az login' first!" >&2
      exit -1
   fi


   _create_az_sp
   _install_azure_eso
   _create_azure_eso_store
}
