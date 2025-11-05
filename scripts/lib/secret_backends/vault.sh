#!/usr/bin/env bash
# scripts/lib/secret_backends/vault.sh
# HashiCorp Vault secret backend provider

# Vault configuration defaults
VAULT_SECRET_BACKEND_NS="${VAULT_SECRET_BACKEND_NS:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
VAULT_SECRET_BACKEND_RELEASE="${VAULT_SECRET_BACKEND_RELEASE:-${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}}"
VAULT_SECRET_BACKEND_MOUNT="${VAULT_SECRET_BACKEND_MOUNT:-${VAULT_KV_MOUNT:-secret}}"

# Ensure Vault helpers are available
if ! declare -f _vault_exec >/dev/null 2>&1; then
   VAULT_PLUGIN="${PLUGINS_DIR:-${SCRIPT_DIR}/plugins}/vault.sh"
   if [[ -r "$VAULT_PLUGIN" ]]; then
      # shellcheck disable=SC1090
      source "$VAULT_PLUGIN"
   else
      _err "[secret_backend:vault] vault plugin not available at $VAULT_PLUGIN"
   fi
fi

function _secret_backend_vault_init() {
   local ns="${1:-$VAULT_SECRET_BACKEND_NS}"
   local release="${2:-$VAULT_SECRET_BACKEND_RELEASE}"

   # Ensure Vault is accessible
   if ! _vault_exec --no-exit "$ns" "vault status" "$release" >/dev/null 2>&1; then
      _err "[secret_backend:vault] Vault not accessible at ${ns}/${release}"
   fi

   # Login to ensure we have a session token
   if declare -f _vault_login >/dev/null 2>&1; then
      _vault_login "$ns" "$release"
   fi

   return 0
}

function _secret_backend_vault_put() {
   local path="${1:?secret path required}"
   shift

   if [[ $# -eq 0 ]]; then
      _err "[secret_backend:vault] at least one key=value pair required"
   fi

   local ns="$VAULT_SECRET_BACKEND_NS"
   local release="$VAULT_SECRET_BACKEND_RELEASE"
   local mount="$VAULT_SECRET_BACKEND_MOUNT"

   # Build vault kv put command
   local -a kv_args=()
   local arg
   for arg in "$@"; do
      if [[ "$arg" == *"="* ]]; then
         kv_args+=("$arg")
      else
         _err "[secret_backend:vault] invalid argument format: $arg (expected key=value)"
      fi
   done

   local full_path="${mount}/${path}"

   # Build command with proper quoting to handle special characters
   # Use printf %q to properly quote each argument
   local cmd="vault kv put"
   cmd+=" $(printf '%q' "$full_path")"
   for arg in "${kv_args[@]}"; do
      cmd+=" $(printf '%q' "$arg")"
   done

   # Execute with trace disabled and suppress command echo on error
   if ! _no_trace _vault_exec "$ns" "$cmd" "$release" 2>&1 | grep -v "vault kv put"; then
      # Mask the path to avoid leaking secret names in errors
      local safe_path="${path%%/*}/***"
      _err "[secret_backend:vault] failed to write secret at ${safe_path} (check Vault logs for details)"
      return 1
   fi

   return 0
}

function _secret_backend_vault_get() {
   local path="${1:?secret path required}"
   local key="${2:?secret key required}"

   local ns="$VAULT_SECRET_BACKEND_NS"
   local release="$VAULT_SECRET_BACKEND_RELEASE"
   local mount="$VAULT_SECRET_BACKEND_MOUNT"

   local full_path="${mount}/${path}"
   local cmd="vault kv get -field=${key} ${full_path}"

   _no_trace _vault_exec "$ns" "$cmd" "$release"
}

function _secret_backend_vault_get_json() {
   local path="${1:?secret path required}"

   local ns="$VAULT_SECRET_BACKEND_NS"
   local release="$VAULT_SECRET_BACKEND_RELEASE"
   local mount="$VAULT_SECRET_BACKEND_MOUNT"

   local full_path="${mount}/${path}"
   local cmd="vault kv get -format=json ${full_path}"

   _vault_exec --no-exit "$ns" "$cmd" "$release" 2>/dev/null
}

function _secret_backend_vault_exists() {
   local path="${1:?secret path required}"

   local ns="$VAULT_SECRET_BACKEND_NS"
   local release="$VAULT_SECRET_BACKEND_RELEASE"
   local mount="$VAULT_SECRET_BACKEND_MOUNT"

   local full_path="${mount}/${path}"
   local cmd="vault kv get ${full_path}"

   if _vault_exec --no-exit "$ns" "$cmd" "$release" >/dev/null 2>&1; then
      return 0
   fi

   return 1
}

function _secret_backend_vault_delete() {
   local path="${1:?secret path required}"

   local ns="$VAULT_SECRET_BACKEND_NS"
   local release="$VAULT_SECRET_BACKEND_RELEASE"
   local mount="$VAULT_SECRET_BACKEND_MOUNT"

   local full_path="${mount}/${path}"
   local cmd="vault kv delete ${full_path}"

   _vault_exec "$ns" "$cmd" "$release"
}

function _secret_backend_vault_config() {
   local key="${1:?config key required}"

   case "$key" in
      namespace)
         printf '%s' "$VAULT_SECRET_BACKEND_NS"
         ;;
      release)
         printf '%s' "$VAULT_SECRET_BACKEND_RELEASE"
         ;;
      mount)
         printf '%s' "$VAULT_SECRET_BACKEND_MOUNT"
         ;;
      *)
         _err "[secret_backend:vault] unknown config key: $key"
         ;;
   esac
}
