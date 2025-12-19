# Secret Backend Interface Design

## Overview

Design a pluggable interface for ESO secret backends to support Vault, Azure Key Vault, AWS Secrets Manager, and GCP Secret Manager while removing Bitwarden support.

**Date**: 2025-11-04
**Status**: Design Proposal
**Related**: jenkins-authentication-analysis.md, ldap-integration.md

---

## Current State Analysis

### Existing Providers

**Vault** (scripts/plugins/vault.sh):
- ✅ Fully integrated with deploy_vault, deploy_jenkins, deploy_ldap
- ✅ SecretStore creation embedded in deployment functions
- ✅ Authentication via Kubernetes auth method
- ✅ Policy-based access control

**Azure Key Vault** (scripts/plugins/azure.sh):
- ✅ Standalone plugin with `eso_akv up/down` commands
- ✅ Creates ClusterSecretStore via template (etc/azure/azure-eso.yaml.tmpl)
- ✅ Service Principal authentication
- ⚠️ **NOT** integrated with Jenkins/LDAP deployments

**Bitwarden** (scripts/plugins/bitwarden.sh):
- ❌ To be removed per user request
- Contains SecretStore logic but not used in production

### Current Jenkins Integration

**Hardcoded Vault dependency** (scripts/plugins/jenkins.sh):
```bash
# Line 864-866: ESO deployment tied to Vault
if (( enable_vault )); then
   deploy_eso
fi

# Line 869-874: Vault deployment
if (( enable_vault )); then
   deploy_vault "$vault_namespace" "$vault_release"
fi

# Line 882-884: Vault-specific policy creation (ALWAYS runs)
_create_jenkins_admin_vault_policy "$vault_namespace" "$vault_release"
_create_jenkins_vault_ad_policy "$vault_namespace" "$vault_release" "$jenkins_namespace"
_create_jenkins_cert_rotator_policy "$vault_namespace" "$vault_release" "" "" "$jenkins_namespace"
```

**LDAP Integration** (scripts/plugins/ldap.sh):
- Hardcoded to Vault LDAP secrets engine
- Creates secrets at `secret/ldap/service-accounts/jenkins-admin`
- Requires Vault policies

---

## Design Goals

1. **Provider Abstraction**: Support multiple ESO backends transparently
2. **Backward Compatibility**: Existing Vault deployments continue to work
3. **Minimal Refactoring**: Reuse existing plugin structure
4. **Clear Interface**: Standard functions all providers must implement
5. **Remove Bitwarden**: Clean up unused code

---

## Proposed Interface

### Core Abstraction Layer

Create `scripts/lib/secret_backend.sh` with provider interface:

```bash
#!/usr/bin/env bash
# scripts/lib/secret_backend.sh
# Secret backend abstraction for ESO providers

# Supported backends: vault, azure, aws, gcp
SECRET_BACKEND="${SECRET_BACKEND:-vault}"

# Provider Interface - all providers must implement these functions:
#
# 1. backend_init()
#    - Deploy/configure the secret backend
#    - Install ESO if needed
#    - Returns: 0 on success
#
# 2. backend_create_secret(secret_path, key1=val1, key2=val2, ...)
#    - Create or update a secret with key-value pairs
#    - Args: path to secret, followed by key=value pairs
#    - Returns: 0 on success
#
# 3. backend_create_secret_store(namespace, store_name, backend_config)
#    - Create ESO SecretStore or ClusterSecretStore
#    - Args: namespace, store name, backend-specific config
#    - Returns: 0 on success
#
# 4. backend_create_external_secret(namespace, es_name, secret_name, mappings)
#    - Create ESO ExternalSecret resource
#    - Args: namespace, ExternalSecret name, target K8s secret name, path->key mappings
#    - Returns: 0 on success
#
# 5. backend_wait_for_secret(namespace, secret_name, timeout_sec)
#    - Wait for ESO to sync secret to Kubernetes
#    - Args: namespace, secret name, timeout
#    - Returns: 0 if secret exists, 1 on timeout

function _get_secret_backend() {
   echo "${SECRET_BACKEND}"
}

function _load_backend_provider() {
   local backend="${1:-$SECRET_BACKEND}"
   local provider_plugin="$PLUGINS_DIR/${backend}.sh"

   if [[ ! -f "$provider_plugin" ]]; then
      _err "[secret-backend] Provider plugin not found: $provider_plugin"
      return 1
   fi

   # Source the provider plugin
   # shellcheck disable=SC1090
   source "$provider_plugin"

   # Verify provider implements required interface
   local -a required_functions=(
      "${backend}_init"
      "${backend}_create_secret"
      "${backend}_create_secret_store"
      "${backend}_create_external_secret"
      "${backend}_wait_for_secret"
   )

   local func
   for func in "${required_functions[@]}"; do
      if ! declare -F "$func" >/dev/null 2>&1; then
         _err "[secret-backend] Provider '$backend' missing required function: $func"
         return 1
      fi
   done
}

# Generic wrapper functions that delegate to active backend
function backend_init() {
   local backend="$(_get_secret_backend)"
   _load_backend_provider "$backend" || return 1
   "${backend}_init" "$@"
}

function backend_create_secret() {
   local backend="$(_get_secret_backend)"
   _load_backend_provider "$backend" || return 1
   "${backend}_create_secret" "$@"
}

function backend_create_secret_store() {
   local backend="$(_get_secret_backend)"
   _load_backend_provider "$backend" || return 1
   "${backend}_create_secret_store" "$@"
}

function backend_create_external_secret() {
   local backend="$(_get_secret_backend)"
   _load_backend_provider "$backend" || return 1
   "${backend}_create_external_secret" "$@"
}

function backend_wait_for_secret() {
   local backend="$(_get_secret_backend)"
   _load_backend_provider "$backend" || return 1
   "${backend}_wait_for_secret" "$@"
}
```

---

## Provider Implementations

### Vault Provider (scripts/plugins/vault.sh)

Add standardized interface functions:

```bash
# Implement backend interface
function vault_init() {
   local vault_namespace="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${2:-$VAULT_RELEASE_DEFAULT}"

   # Deploy ESO
   deploy_eso

   # Deploy Vault
   deploy_vault "$vault_namespace" "$vault_release"

   return 0
}

function vault_create_secret() {
   local secret_path="$1"
   shift
   local -a kv_pairs=("$@")

   local vault_namespace="${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}"
   local vault_release="${VAULT_RELEASE:-$VAULT_RELEASE_DEFAULT}"
   local mount_path="${VAULT_KV_MOUNT:-secret}"

   # Build vault kv put command
   local cmd="vault kv put ${mount_path}/${secret_path}"
   for pair in "${kv_pairs[@]}"; do
      cmd+=" $pair"
   done

   _vault_exec "$vault_namespace" "$cmd" "$vault_release"
}

function vault_create_secret_store() {
   local namespace="$1"
   local store_name="$2"
   local vault_namespace="${3:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${4:-$VAULT_RELEASE_DEFAULT}"
   local vault_sa="${5:-eso-${store_name}-sa}"
   local vault_role="${6:-eso-${store_name}}"

   # Create SecretStore using existing _create_eso_secret_store logic
   # (extract from current embedded code)

   local yaml_content
   yaml_content=$(cat <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${vault_sa}
  namespace: ${namespace}
---
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: ${store_name}
  namespace: ${namespace}
spec:
  provider:
    vault:
      server: "http://vault.${vault_namespace}.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "${vault_role}"
          serviceAccountRef:
            name: "${vault_sa}"
EOF
)

   echo "$yaml_content" | _kubectl apply -n "$namespace" -f -
}

function vault_create_external_secret() {
   local namespace="$1"
   local es_name="$2"
   local secret_name="$3"
   shift 3
   local -a mappings=("$@")  # Format: "vault/path/key:k8s-secret-key"

   # Generate data mapping
   local data_yaml=""
   for mapping in "${mappings[@]}"; do
      local vault_ref="${mapping%%:*}"
      local secret_key="${mapping##*:}"
      local vault_path="${vault_ref%/*}"
      local vault_key="${vault_ref##*/}"

      data_yaml+="  - secretKey: ${secret_key}
    remoteRef:
      key: ${vault_path}
      property: ${vault_key}
"
   done

   local yaml_content
   yaml_content=$(cat <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${es_name}
  namespace: ${namespace}
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: vault-kv-store
    kind: SecretStore
  target:
    name: ${secret_name}
    creationPolicy: Owner
  data:
${data_yaml}
EOF
)

   echo "$yaml_content" | _kubectl apply -n "$namespace" -f -
}

function vault_wait_for_secret() {
   local namespace="$1"
   local secret_name="$2"
   local timeout_sec="${3:-60}"

   local elapsed=0
   while (( elapsed < timeout_sec )); do
      if _kubectl --no-exit -n "$namespace" get secret "$secret_name" >/dev/null 2>&1; then
         _info "[vault] secret ${namespace}/${secret_name} available"
         return 0
      fi
      sleep 5
      (( elapsed += 5 ))
   done

   _err "[vault] Timeout waiting for secret ${namespace}/${secret_name}"
   return 1
}
```

### Azure Provider (scripts/plugins/azure.sh)

Refactor existing code to match interface:

```bash
function azure_init() {
   local resource_group="${1:-${AZURE_RESOURCE_GROUP}}"
   local keyvault_name="${2:-${AZURE_KEYVAULT_NAME}}"
   local namespace="${3:-external-secrets}"

   # Deploy ESO
   deploy_eso "$namespace"

   # Call existing eso_akv up logic
   eso_akv up "$resource_group" "$keyvault_name" "$namespace"
}

function azure_create_secret() {
   local secret_path="$1"  # Used as Azure secret name
   shift
   local -a kv_pairs=("$@")

   local keyvault_name="${AZURE_KEYVAULT_NAME}"

   # Azure Key Vault stores secrets as name=value, not KV pairs
   # Combine all pairs into JSON object and store as single secret
   local json_value="{"
   local first=1
   for pair in "${kv_pairs[@]}"; do
      local key="${pair%%=*}"
      local value="${pair#*=}"
      (( first )) || json_value+=","
      json_value+="\"${key}\":\"${value}\""
      first=0
   done
   json_value+="}"

   _az keyvault secret set \
      --vault-name "$keyvault_name" \
      --name "$secret_path" \
      --value "$json_value"
}

function azure_create_secret_store() {
   local namespace="$1"
   local store_name="$2"
   local keyvault_name="${3:-${AZURE_KEYVAULT_NAME}}"

   # Use existing _apply_clustersecretstore logic
   export KV="$keyvault_name"
   export NS="$namespace"
   _apply_clustersecretstore "$namespace"
}

function azure_create_external_secret() {
   local namespace="$1"
   local es_name="$2"
   local secret_name="$3"
   shift 3
   local -a mappings=("$@")

   # Azure-specific ExternalSecret YAML generation
   # Similar to vault_create_external_secret but uses Azure schema
   # ... implementation ...
}

function azure_wait_for_secret() {
   local namespace="$1"
   local secret_name="$2"
   local timeout_sec="${3:-60}"

   # Same logic as vault_wait_for_secret (provider-agnostic)
   vault_wait_for_secret "$namespace" "$secret_name" "$timeout_sec"
}
```

### AWS Provider (NEW - scripts/plugins/aws.sh)

```bash
function aws_init() {
   local region="${1:-${AWS_REGION:-us-east-1}}"
   local namespace="${2:-external-secrets}"

   deploy_eso "$namespace"

   # Verify AWS credentials
   if ! _run_command --no-exit -- aws sts get-caller-identity >/dev/null 2>&1; then
      _err "[aws] AWS credentials not configured"
      return 1
   fi

   _info "[aws] Using AWS Secrets Manager in region: $region"
}

function aws_create_secret() {
   local secret_path="$1"
   shift
   local -a kv_pairs=("$@")

   # AWS Secrets Manager stores JSON
   local json_value="{"
   local first=1
   for pair in "${kv_pairs[@]}"; do
      local key="${pair%%=*}"
      local value="${pair#*=}"
      (( first )) || json_value+=","
      json_value+="\"${key}\":\"${value}\""
      first=0
   done
   json_value+="}"

   _run_command -- aws secretsmanager create-secret \
      --name "$secret_path" \
      --secret-string "$json_value" \
      --region "${AWS_REGION:-us-east-1}" \
      || _run_command -- aws secretsmanager update-secret \
         --secret-id "$secret_path" \
         --secret-string "$json_value" \
         --region "${AWS_REGION:-us-east-1}"
}

# ... implement other interface functions ...
```

### GCP Provider (NEW - scripts/plugins/gcp.sh)

```bash
function gcp_init() {
   local project_id="${1:-${GCP_PROJECT_ID}}"
   local namespace="${2:-external-secrets}"

   deploy_eso "$namespace"

   # Verify gcloud auth
   if ! _run_command --no-exit -- gcloud auth list --filter=status:ACTIVE >/dev/null 2>&1; then
      _err "[gcp] No active GCP authentication"
      return 1
   fi

   _info "[gcp] Using GCP Secret Manager in project: $project_id"
}

function gcp_create_secret() {
   local secret_path="$1"
   shift
   local -a kv_pairs=("$@")

   # GCP Secret Manager stores versions of payloads
   local json_value="{"
   local first=1
   for pair in "${kv_pairs[@]}"; do
      local key="${pair%%=*}"
      local value="${pair#*=}"
      (( first )) || json_value+=","
      json_value+="\"${key}\":\"${value}\""
      first=0
   done
   json_value+="}"

   echo "$json_value" | _run_command -- gcloud secrets create "$secret_path" \
      --data-file=- \
      --project="${GCP_PROJECT_ID}" \
      || echo "$json_value" | _run_command -- gcloud secrets versions add "$secret_path" \
         --data-file=- \
         --project="${GCP_PROJECT_ID}"
}

# ... implement other interface functions ...
```

---

## Jenkins Integration Refactoring

Update `scripts/plugins/jenkins.sh` to use abstraction layer:

```bash
# After argument parsing (~line 850)
local enable_vault=0
local enable_ldap=0
local secret_backend="${SECRET_BACKEND:-vault}"

# Validate secret backend
case "$secret_backend" in
   vault|azure|aws|gcp) ;;
   *)
      _err "[jenkins] Unsupported SECRET_BACKEND: $secret_backend (supported: vault, azure, aws, gcp)"
      ;;
esac

# Load secret backend library
source "$SCRIPT_DIR/lib/secret_backend.sh"

# Initialize secret backend
if (( enable_vault || enable_ldap )); then
   backend_init || _err "[jenkins] Failed to initialize secret backend: $secret_backend"
fi

# Create jenkins-admin secret
if (( enable_vault )); then
   # Generate random password (backend-specific logic)
   case "$secret_backend" in
      vault)
         _create_jenkins_admin_vault_policy "$vault_namespace" "$vault_release"
         ;;
      azure|aws|gcp)
         # Generate password locally and store in backend
         local admin_pass
         admin_pass=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9!@#$%^&*()-_=+[]{};:,.?' | head -c 24)
         backend_create_secret "eso/jenkins-admin" "username=jenkins-admin" "password=$admin_pass"
         ;;
   esac
fi

# Create SecretStore and ExternalSecret (provider-agnostic)
backend_create_secret_store "$jenkins_namespace" "vault-kv-store"
backend_create_external_secret "$jenkins_namespace" "jenkins-admin" "jenkins-admin" \
   "eso/jenkins-admin/username:jenkins-admin-user" \
   "eso/jenkins-admin/password:jenkins-admin-password"

backend_wait_for_secret "$jenkins_namespace" "jenkins-admin" 60
```

---

## Migration Plan

### Phase 1: Remove Bitwarden (Immediate)
1. Delete `scripts/plugins/bitwarden.sh`
2. Remove any references in documentation
3. Update `.gitignore` if needed

### Phase 2: Create Abstraction Layer (Week 1)
1. Create `scripts/lib/secret_backend.sh` with interface definition
2. Add Vault provider functions to `scripts/plugins/vault.sh`
3. Write unit tests for interface

### Phase 3: Refactor Azure (Week 2)
1. Update `scripts/plugins/azure.sh` to implement interface
2. Test Azure integration with Jenkins
3. Document Azure-specific configuration

### Phase 4: Add AWS/GCP (Week 3-4)
1. Create `scripts/plugins/aws.sh` with interface implementation
2. Create `scripts/plugins/gcp.sh` with interface implementation
3. Test all providers with Jenkins deployment
4. Update documentation

### Phase 5: Update Jenkins/LDAP (Week 5)
1. Refactor `scripts/plugins/jenkins.sh` to use abstraction
2. Refactor `scripts/plugins/ldap.sh` to use abstraction
3. Comprehensive testing across all providers
4. Update test suite

---

## Configuration

### Environment Variables

```bash
# Select secret backend (default: vault)
export SECRET_BACKEND=vault|azure|aws|gcp

# Provider-specific config
export VAULT_NS=vault
export VAULT_RELEASE=vault

export AZURE_RESOURCE_GROUP=my-rg
export AZURE_KEYVAULT_NAME=my-kv
export AZURE_TENANT_ID=...

export AWS_REGION=us-east-1
export AWS_SECRETS_MANAGER_ENDPOINT=...

export GCP_PROJECT_ID=my-project
export GCP_SECRET_MANAGER_ENDPOINT=...
```

### Usage Examples

```bash
# Vault (default)
./scripts/k3d-manager deploy_jenkins --enable-vault --enable-ldap

# Azure Key Vault
export SECRET_BACKEND=azure
export AZURE_KEYVAULT_NAME=my-keyvault
./scripts/k3d-manager deploy_jenkins --enable-ldap

# AWS Secrets Manager
export SECRET_BACKEND=aws
export AWS_REGION=us-west-2
./scripts/k3d-manager deploy_jenkins --enable-ldap

# GCP Secret Manager
export SECRET_BACKEND=gcp
export GCP_PROJECT_ID=my-project
./scripts/k3d-manager deploy_jenkins --enable-ldap
```

---

## Testing Strategy

### Unit Tests
- Test each provider's interface implementation
- Mock backend API calls
- Verify secret creation, retrieval, and deletion

### Integration Tests
- Deploy Jenkins with each backend
- Verify admin credentials work
- Verify LDAP integration
- Test secret rotation

### Multi-Provider Tests
- Switch between providers
- Verify secrets isolated per provider
- Test migration scenarios

---

## Open Questions

1. **Password Policy**: Should AWS/Azure/GCP use local password generation or provider-specific policies?
   - Vault: Uses password policy (24-char complex)
   - Azure/AWS/GCP: Generate locally with openssl/pwgen?

2. **Secret Structure**: How to handle provider differences?
   - Vault: Native KV pairs
   - Azure/AWS/GCP: JSON-encoded secrets

3. **LDAP Secrets**: Should LDAP use Vault's LDAP engine or generic KV for all providers?
   - Vault: Can use dedicated LDAP secrets engine
   - Others: Must use generic secret storage

4. **Backward Compatibility**: How to handle existing Vault deployments?
   - Default SECRET_BACKEND=vault maintains compatibility
   - Migration path for moving between providers?

---

## Related Files

- `scripts/lib/secret_backend.sh` - NEW: Abstraction layer
- `scripts/plugins/vault.sh` - UPDATE: Add interface functions
- `scripts/plugins/azure.sh` - UPDATE: Refactor to interface
- `scripts/plugins/aws.sh` - NEW: AWS provider
- `scripts/plugins/gcp.sh` - NEW: GCP provider
- `scripts/plugins/jenkins.sh` - UPDATE: Use abstraction
- `scripts/plugins/ldap.sh` - UPDATE: Use abstraction
- `scripts/plugins/bitwarden.sh` - DELETE: Remove per user request
