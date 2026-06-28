#!/usr/bin/env bash
# shellcheck disable=SC2155,SC2184,SC2016
# k3d-manager :: HashiCorp Vault helpers (ESO-friendly)
# Style: uses command / _kubectl / _helm, no set -e, minimal locals.

# Defaults (override via env or args to the top-levels)
VAULT_NS_DEFAULT="${VAULT_NS_DEFAULT:-secrets}"
VAULT_RELEASE_DEFAULT="${VAULT_RELEASE_DEFAULT:-vault}"
VAULT_CHART_VERSION="${VAULT_CHART_VERSION:-0.30.1}"
VAULT_SC="${VAULT_SC:-local-path}"   # k3d/k3s default

# --- primitives ----------------------------------------------------

ESO_PLUGIN="$PLUGINS_DIR/eso.sh"
if [[ ! -f "$ESO_PLUGIN" ]]; then
   _err "[vault] missing required plugin: $ESO_PLUGIN" >&2
fi

# shellcheck disable=SC1090
source "$ESO_PLUGIN"

VAULT_PKI_HELPERS="$SCRIPT_DIR/lib/vault_pki.sh"
if [[ -f "$VAULT_PKI_HELPERS" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_PKI_HELPERS"
else
   _warn "[vault] missing optional helper file: $VAULT_PKI_LIB" >&2
fi

command -v _info >/dev/null 2>&1 || _info() { printf '%s\n' "$*" >&2; }
command -v _warn >/dev/null 2>&1 || _warn() { printf '%s\n' "$*" >&2; }

declare -Ag _VAULT_CONTAINER_CACHE=()
declare -Ag _VAULT_SESSION_TOKENS=()

function __vault_exec_kubectl() {
   local use_container="${1:-0}" ns="${2:-$VAULT_NS_DEFAULT}" release="${3:-$VAULT_RELEASE_DEFAULT}"
   shift 3
   local -a cmd_args=("$@")
   local output rc
   local retries=0
   local max_retries=5
   local container_removed=0

   while :; do
      output=$(_kubectl "${cmd_args[@]}" 2>&1)
      rc=$?
      if (( rc == 0 )); then
         if (( container_removed )); then
            _VAULT_CONTAINER_CACHE["${ns}/${release}"]=""
         fi
         printf '%s' "$output"
         return 0
      fi

      if [[ "$output" == *"container not found"* ]]; then
         if (( use_container )) && (( !container_removed )); then
            local -a fallback=()
            local skip_next=0 past_double_dash=0 removed=0
            for arg in "${cmd_args[@]}"; do
               if (( skip_next )); then
                  skip_next=0
                  continue
               fi
               if (( !past_double_dash )) && [[ "$arg" == "--" ]]; then
                  past_double_dash=1
               fi
               if (( !past_double_dash )) && [[ "$arg" == "-c" ]] && (( !removed )); then
                  skip_next=1
                  removed=1
                  continue
               fi
               fallback+=("$arg")
            done
            cmd_args=("${fallback[@]}")
            use_container=0
            container_removed=1
            _VAULT_CONTAINER_CACHE["${ns}/${release}"]=""
            retries=$((retries + 1))
            sleep 2
            continue
         fi

         if (( retries < max_retries )); then
            retries=$((retries + 1))
            sleep 2
            continue
         fi
      fi

      printf '%s' "$output"
      return $rc
   done
}

function _vault_container_name() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local key="${ns}/${release}"

   if [[ "${VAULT_CONTAINER_NAME_OVERRIDE+x}" == x ]]; then
      local override="${VAULT_CONTAINER_NAME_OVERRIDE}"
      _VAULT_CONTAINER_CACHE["${key}"]="$override"
      printf '%s\n' "$override"
      return 0
   fi

   if [[ -n "${_VAULT_CONTAINER_CACHE[$key]:-}" ]]; then
      printf '%s\n' "${_VAULT_CONTAINER_CACHE[$key]}"
      return 0
   fi

   local pod="${release}-0"
   local name=""
   name=$(_kubectl --no-exit -n "$ns" get pod "$pod" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null || true)
   if [[ -n "$name" ]]; then
      _VAULT_CONTAINER_CACHE[$key]="$name"
      printf '%s\n' "$name"
      return 0
   fi

   _VAULT_CONTAINER_CACHE[$key]=""
   printf '\n'
}

function _vault_exec_stream() {
   local kflags=()
   local pod_override=""
   while [[ $# -gt 0 ]]; do
      case "$1" in
         --no-exit|--prefer-sudo|--require-sudo)
            kflags+=("$1")
            shift
            ;;
         --pod)
            pod_override="${2:-}"
            shift 2
            ;;
         --pod=*)
            pod_override="${1#*=}"
            shift
            ;;
         *)
            break
            ;;
      esac
   done
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   shift 2
   local pod="${pod_override:-${release}-0}"
   local container
   container=$(_vault_container_name "$ns" "$release")
   local -a args=("${kflags[@]}" --quiet -n "$ns" exec -i "$pod")
   local use_container=0
   if [[ -n "$container" ]]; then
      args+=(-c "$container")
      use_container=1
   fi
   local key="${ns}/${release}"
   local session_token="${_VAULT_SESSION_TOKENS[$key]:-}"
   if [[ -n "$session_token" ]]; then
      local -a cmd_args=()
      local inserted=0
      if (( $# == 0 )); then
         cmd_args+=("env" "VAULT_TOKEN=$session_token")
      else
         while [[ $# -gt 0 ]]; do
            local arg="$1"
            shift
            if (( !inserted )) && [[ "$arg" == "--" ]]; then
               cmd_args+=("$arg" "env" "VAULT_TOKEN=$session_token")
               inserted=1
               continue
            fi
            cmd_args+=("$arg")
         done
         if (( !inserted )); then
            cmd_args=("env" "VAULT_TOKEN=$session_token" "${cmd_args[@]}")
         fi
      fi
      __vault_exec_kubectl "$use_container" "$ns" "$release" "${args[@]}" "${cmd_args[@]}"
   else
      __vault_exec_kubectl "$use_container" "$ns" "$release" "${args[@]}" "$@"
   fi
}

function _vault_exec() {
  local kflags=()
  while [[ "${1:-}" == "--no-exit" ]]  || \
     [[ "${1:-}" == "--prefer-sudo" ]] || \
     [[ "${1:-}" == "--require-sudo" ]]; do
     kflags+=("$1")
     shift
  done

  local ns="${1:-$VAULT_NS_DEFAULT}" cmd="${2:-sh}" release="${3:-$VAULT_RELEASE_DEFAULT}"
  local pod="${release}-0"
  local container
  container=$(_vault_container_name "$ns" "$release")
  local -a exec_args=("${kflags[@]}" --quiet -n "$ns" exec -i "$pod")
  local use_container=0
  if [[ -n "$container" ]]; then
     exec_args+=(-c "$container")
     use_container=1
  fi

  local key="${ns}/${release}"
  local session_token="${_VAULT_SESSION_TOKENS[$key]:-}"
  local shell_cmd="$cmd"
  if [[ -n "$session_token" ]]; then
     printf -v shell_cmd 'VAULT_TOKEN=%q %s' "$session_token" "$cmd"
  fi

  __vault_exec_kubectl "$use_container" "$ns" "$release" "${exec_args[@]}" -- sh -lc "$shell_cmd"
}
function _vault_ns_ensure() {
   ns="${1:-$VAULT_NS_DEFAULT}"

   if ! _kubectl --no-exit get ns "$ns" >/dev/null 2>&1 ; then
      _kubectl create ns "$ns"
   fi
}

function _vault_repo_setup() {
   _helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
   _helm repo update >/dev/null 2>&1
}

function _vault_cache_unseal_keys() {
   local cluster_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local cluster_release="${2:-${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}}"
   shift 2 || true
   local -a keys=("$@")
   local service="k3d-manager-vault-unseal"
   local type="vault-unseal"

   if (( ${#keys[@]} == 0 )); then
      _warn "[vault] no unseal keys provided for caching (${cluster_ns}/${cluster_release})"
      return 1
   fi

   local cluster="${cluster_ns}/${cluster_release}"

   local previous_count
   if previous_count=$(_secret_load_data "$service" "${cluster}:count" "$type" 2>/dev/null); then
      previous_count=${previous_count%$'\r'}
      if [[ "$previous_count" =~ ^[0-9]+$ ]]; then
         local i
         for (( i=1; i<=previous_count; i++ )); do
            _secret_clear_data "$service" "${cluster}:shard${i}" "$type" >/dev/null 2>&1 || true
         done
      fi
      _secret_clear_data "$service" "${cluster}:count" "$type" >/dev/null 2>&1 || true
   fi

   local count=0
   local idx
   for (( idx=0; idx<${#keys[@]}; idx++ )); do
      local shard="${keys[$idx]}"
      shard=${shard%$'\r'}
      if [[ -z "$shard" ]]; then
         _warn "[vault] unseal shard $((idx+1)) is empty; skipping cache entry"
         continue
      fi
      local shard_pos=$((count + 1))
      local shard_key="${cluster}:shard${shard_pos}"
      if ! _secret_store_data "$service" "$shard_key" "$shard" "Vault unseal shard ${shard_pos}" "$type"; then
         _warn "[vault] unable to store unseal shard ${shard_pos} for ${cluster}"
         continue
      fi
      ((count++))
   done

   if (( count == 0 )); then
      _warn "[vault] no unseal shards cached for ${cluster}"
      return 1
   fi

   if ! _secret_store_data "$service" "${cluster}:count" "$count" "Vault unseal shard count" "$type"; then
      _warn "[vault] unable to persist unseal shard count for ${cluster}"
      return 1
   fi

   _info "[vault] cached ${count} unseal shard(s) for cluster ${cluster}"
   return 0
}

function _vault_collect_unseal_shards_from_secret() {
   local cluster_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local secret_json=""

   secret_json=$(_kubectl --no-exit -n "$cluster_ns" get secret vault-unseal -o json 2>/dev/null || true)
   if [[ -z "$secret_json" ]]; then
      return 1
   fi

   local -a shards=()
   while IFS= read -r encoded; do
      [[ -z "$encoded" || "$encoded" == "null" ]] && continue
      local decoded
      decoded=$(printf '%s' "$encoded" | base64 -d 2>/dev/null || true)
      [[ -z "$decoded" ]] && continue
      shards+=("$decoded")
   done < <(printf '%s' "$secret_json" | jq -r '.data | to_entries | sort_by(.key)[] | select(.key|startswith("shard-")) | .value // ""' 2>/dev/null)

    if (( ${#shards[@]} == 0 )); then
      return 1
   fi

   printf '%s\n' "${shards[@]}"
}

function _vault_cache_unseal_from_secret() {
   local cluster_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local cluster_release="${2:-${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}}"
   local -a shards=()

   if ! mapfile -t shards < <(_vault_collect_unseal_shards_from_secret "$cluster_ns"); then
      _warn "[vault] secret vault-unseal not found in ${cluster_ns}; unable to cache shards"
      return 1
   fi

   if (( ${#shards[@]} == 0 )); then
      _warn "[vault] vault-unseal secret in ${cluster_ns} lacks shard data"
      return 1
   fi

   _vault_cache_unseal_keys "$cluster_ns" "$cluster_release" "${shards[@]}" >/dev/null 2>&1 || true
   return 0
}

function _vault_parse_sealed_from_status() {
   local status="${1:-}"
   local sealed=""

   # Note: Don't use '// empty' with boolean fields - false is a valid value!
   sealed=$(printf '%s' "$status" | jq -r '.sealed' 2>/dev/null || true)
   if [[ -n "$sealed" ]] && [[ "$sealed" != "null" ]]; then
      printf '%s' "$sealed"
      return 0
   fi

   if printf '%s\n' "$status" | grep -Eq 'Sealed[[:space:]]+false'; then
      printf 'false'
      return 0
   fi

   if printf '%s\n' "$status" | grep -Eq 'Sealed[[:space:]]+true'; then
      printf 'true'
      return 0
   fi

   return 1
}

function _vault_is_sealed() {
   local cluster_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local cluster_release="${2:-${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}}"

   local status_json=""
   status_json=$(_vault_exec --no-exit "$cluster_ns" "vault status -format=json" "$cluster_release" 2>/dev/null || true)

   if [[ -z "$status_json" ]]; then
      # Cannot determine status - return "unknown" via exit code 2
      return 2
   fi

   local sealed=""
   sealed=$(_vault_parse_sealed_from_status "$status_json" 2>/dev/null || true)

   if [[ "$sealed" == "true" ]]; then
      # Vault is sealed
      return 0
   elif [[ "$sealed" == "false" ]]; then
      # Vault is unsealed
      return 1
   else
      # Cannot determine status
      return 2
   fi
}

# _vault_load_cached_shards
# Loads unseal shards from the k3d-manager-vault-unseal keychain service.
# Sets global: _VAULT_CACHED_SHARDS (array) _VAULT_CACHED_COUNT
# Args: $1=service $2=cluster $3=type
function _vault_load_cached_shards() {
   local service="$1" cluster="$2" type="$3"
   _VAULT_CACHED_SHARDS=()
   _VAULT_CACHED_COUNT=0

   local count=""
   count=$(_secret_load_data "$service" "${cluster}:count" "$type" 2>/dev/null || true)
   count=${count%$'\r'}

   local cached_ok=1
   if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )); then
      local idx
      for (( idx=1; idx<=count; idx++ )); do
         local shard=""
         shard=$(_secret_load_data "$service" "${cluster}:shard${idx}" "$type" 2>/dev/null || true)
         shard=${shard%$'\r'}
         if [[ -z "$shard" ]]; then
            cached_ok=0
            break
         fi
         _VAULT_CACHED_SHARDS+=("$shard")
      done
      (( ! cached_ok )) && _VAULT_CACHED_SHARDS=()
   else
      cached_ok=0
   fi
   _VAULT_CACHED_COUNT="${#_VAULT_CACHED_SHARDS[@]}"
}

# _vault_clear_cached_shards
# Clears unseal shards from the keychain service after a successful unseal.
# Args: $1=service $2=cluster $3=type $4=shard_count
function _vault_clear_cached_shards() {
   local service="$1" cluster="$2" type="$3" shard_count="$4"
   _secret_clear_data "$service" "${cluster}:count" "$type" >/dev/null 2>&1 || true
   local j
   for (( j=1; j<=shard_count; j++ )); do
      _secret_clear_data "$service" "${cluster}:shard${j}" "$type" >/dev/null 2>&1 || true
   done
}

function _vault_replay_cached_unseal() {
   local cluster_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local cluster_release="${2:-${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}}"
   local clear_after="${3:-0}"
   case "${clear_after,,}" in
      1|true|yes) clear_after=1 ;;
      *) clear_after=0 ;;
   esac
   local service="k3d-manager-vault-unseal"
   local type="vault-unseal"
   local cluster="${cluster_ns}/${cluster_release}"

   _vault_load_cached_shards "$service" "$cluster" "$type"
   local -a shards=("${_VAULT_CACHED_SHARDS[@]}")
   local count="${_VAULT_CACHED_COUNT}"

   (( ${#shards[@]} > 0 )) || {
      _warn "[vault] cached shards unavailable for ${cluster}; attempting vault-unseal secret"
      mapfile -t shards < <(_vault_collect_unseal_shards_from_secret "$cluster_ns") || {
         _warn "[vault] unable to read shards from vault-unseal secret in ${cluster_ns}; manual unseal required"
         return 43
      }
      (( ${#shards[@]} > 0 )) || {
         _warn "[vault] vault-unseal secret lacks shard data; manual unseal required"
         return 43
      }
      _vault_cache_unseal_keys "$cluster_ns" "$cluster_release" "${shards[@]}" >/dev/null 2>&1 || true
      count=${#shards[@]}
   }

   local pod="${cluster_release}-0"
   _kubectl --no-exit -n "$cluster_ns" get pod "$pod" >/dev/null 2>&1 || {
      _warn "[vault] pod ${pod} not found in namespace ${cluster_ns}; skipping auto-unseal"
      return 1
   }

   local status_json=""
   status_json=$(_vault_exec --no-exit "$cluster_ns" "vault status -format=json" "$cluster_release" 2>/dev/null || true)
   [[ -n "$status_json" ]] || {
      _warn "[vault] unable to query status for ${cluster}; skipping auto-unseal"
      return 1
   }

   local sealed=""
   sealed=$(printf '%s' "$status_json" | jq -r '.sealed' 2>/dev/null || true)
   [[ "$sealed" == "false" ]] && {
      _info "[vault] instance ${cluster} already unsealed"
      return 0
   }

   local threshold=""
   threshold=$(printf '%s' "$status_json" | jq -r '.t // empty' 2>/dev/null || true)
   [[ -n "$threshold" ]] && (( count < threshold )) &&       _warn "[vault] only ${count} shard(s) cached, but cluster reports threshold ${threshold}"

   _info "[vault] applying ${count} cached unseal shard(s) to ${cluster}"
   local shard_count=$count

   local shard unsealed=0 invalid_key=0
   for shard in "${shards[@]}"; do
      local unseal_output="" unseal_rc=0
      unseal_output=$(_no_trace _vault_exec_stream --no-exit --pod "$pod" "$cluster_ns" "$cluster_release" -- vault operator unseal "$shard" 2>&1) || unseal_rc=$?
      (( unseal_rc != 0 )) && {
         _warn "[vault] unseal command returned rc=${unseal_rc}; output:"
         printf '%s\n' "$unseal_output" >&2
      }

      [[ "$unseal_output" == *"invalid key"* || "$unseal_output" == *"failed to decrypt keys from storage"* ]] && {
         invalid_key=1
         _warn "[vault] detected stale cached shard for ${cluster}; will regenerate"
      }

      status_json=$(_vault_exec --no-exit "$cluster_ns" "vault status -format=json" "$cluster_release" 2>/dev/null || true)
      sealed=$(_vault_parse_sealed_from_status "$status_json" 2>/dev/null || true)

      [[ "$sealed" == "false" ]] && {
         unsealed=1
         _info "[vault] vault ${cluster} is now unsealed"
         (( clear_after == 1 )) && {
            _vault_clear_cached_shards "$service" "$cluster" "$type" "$shard_count"
            _info "[vault] cleared cached unseal shards for ${cluster}"
         }
         return 0
      }
      sleep 1
   done

   (( unsealed == 0 )) && {
      status_json=$(_vault_exec --no-exit "$cluster_ns" "vault status -format=json" "$cluster_release" 2>/dev/null || true)
      sealed=$(_vault_parse_sealed_from_status "$status_json" 2>/dev/null || true)
   }
   [[ "$sealed" == "false" ]] && {
      _info "[vault] vault ${cluster} is now unsealed"
      (( clear_after == 1 )) && {
         _vault_clear_cached_shards "$service" "$cluster" "$type" "$shard_count"
         _info "[vault] cleared cached unseal shards for ${cluster}"
      }
      return 0
   }

   _warn "[vault] ${cluster} remains sealed after applying cached shards; manual intervention required"
   (( invalid_key )) && return 42
   return 1
}

function _mount_vault_immediate_sc() {
   local sc="${1:-local-path-immediate}"

   if _kubectl --no-exit get sc "$sc" >/dev/null 2>&1 ; then
      local mode=$(_kubectl --no-exit get sc "$sc" -o jsonpath='{.volumeBinding.mode}' 2>/dev/null)
      local prov=$(_kubectl --no-exit get sc "$sc" -o jsonpath='{.provisioner}' 2>/dev/null)
      if [[ "$mode" == "Immediate" ]] && [[ "$prov" == "rancher.io/local-path"  ]]; then
         if ! _kubectl --no-exit get sc local-path-immediate >/dev/null 2>&1; then
            cat <<YAML | _kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: "$sc"
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: rancher.io/local-path
volumeBindingMode: Immediate
reclaimPolicy: Retain
allowVolumeExpansion: true
YAML
         fi
         sc="local-path-immediate"
      fi
   fi
}

function _vault_resolve_data_path() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local default_pvc="data-${release}-0"
   local pvc_name=""
   local deadline=$((SECONDS + 60))

   while (( SECONDS < deadline )); do
      pvc_name=$(_kubectl --no-exit -n "$ns" get pvc "$default_pvc" -o jsonpath='{.metadata.name}' 2>/dev/null || true)
      if [[ -n "$pvc_name" ]]; then
         break
      fi
      pvc_name=$(_kubectl --no-exit -n "$ns" get pvc -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -E "^data-${release}-[0-9]+$" | head -n1 || true)
      if [[ -n "$pvc_name" ]]; then
         break
      fi
      sleep 2
   done

   if [[ -z "$pvc_name" ]]; then
      return 0
   fi

   local pv_name=""
   pv_name=$(_kubectl --no-exit -n "$ns" get pvc "$pvc_name" -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)
   if [[ -z "$pv_name" ]]; then
      return 0
   fi

   local host_path=""
   host_path=$(_kubectl --no-exit get pv "$pv_name" -o jsonpath='{.spec.local.path}' 2>/dev/null || true)
   if [[ -z "$host_path" ]]; then
      return 0
   fi

   printf '%s' "$host_path"
}

function _vault_ensure_data_path() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local host_path
   host_path=$(_vault_resolve_data_path "$ns" "$release")
   if [[ -z "$host_path" ]]; then
      return 0
   fi

   # local-path PV directories live inside the OrbStack/Docker VM on macOS.
   # Skipping host mkdir avoids permission errors like /var/lib/rancher.
   if _is_mac; then
      return 0
   fi

   if [[ ! -d "$host_path" ]]; then
      _info "[vault] creating data directory: $host_path"
      _run_command --prefer-sudo -- mkdir -p "$host_path"
   fi
}

function _vault_reset_data_path() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local host_path backup_path timestamp
   host_path=$(_vault_resolve_data_path "$ns" "$release")
   if [[ -z "$host_path" ]]; then
      _warn "[vault] unable to determine data path for $ns/$release"
      return 1
   fi

   if [[ ! -d "$host_path" ]]; then
      return 0
   fi

   if [[ "$host_path" != *"vault_data-"* ]]; then
      _warn "[vault] refusing to reset unexpected data path: $host_path"
      return 1
   fi

   timestamp=$(date +%s)
   backup_path="${host_path}.backup.${timestamp}"
   _info "[vault] backing up existing data directory to $backup_path"
   if ! _run_command --soft --prefer-sudo -- mv "$host_path" "$backup_path"; then
      _warn "[vault] failed to backup existing data directory"
      return 1
   fi

   if ! _run_command --soft --prefer-sudo -- mkdir -p "$host_path"; then
      _warn "[vault] failed to recreate data directory: $host_path"
      return 1
   fi
   return 0
}

function _vault_restart_pod() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local pod="${release}-0"
   _kubectl --no-exit -n "$ns" delete pod "$pod" --ignore-not-found=true >/dev/null 2>&1 || true
}

function _vault_purge_unseal_cache() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local service="k3d-manager-vault-unseal"
   local type="vault-unseal"
   local cluster="${ns}/${release}"
   local count

   count=$(_secret_load_data "$service" "${cluster}:count" "$type" 2>/dev/null || true)
   count=${count%$'\r'}
   if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )); then
      local idx
      for (( idx=1; idx<=count; idx++ )); do
         _secret_clear_data "$service" "${cluster}:shard${idx}" "$type" >/dev/null 2>&1 || true
      done
      _secret_clear_data "$service" "${cluster}:count" "$type" >/dev/null 2>&1 || true
   fi

   _kubectl --no-exit -n "$ns" delete secret vault-unseal >/dev/null 2>&1 || true
   _kubectl --no-exit -n "$ns" delete secret vault-root >/dev/null 2>&1 || true
   unset _VAULT_SESSION_TOKENS["$cluster"]
}

function __vault_plan_emit() {
   local state="$1" desc="$2" detail="${3:-}"
   printf '[%s] %s' "$state" "$desc"
   if [[ -n "$detail" ]]; then
      printf ' — %s' "$detail"
   fi
   printf '\n'
}

function __vault_plan_check_eso_operator() {
   local eso_ns="$1"
   if _kubectl --no-exit -n "$eso_ns" get deploy/external-secrets >/dev/null 2>&1; then
      __vault_plan_emit OK "External Secrets Operator present (${eso_ns})"
   else
      __vault_plan_emit TODO "External Secrets Operator missing" "Would run: deploy_eso --confirm"
   fi
}

function __vault_plan_check_namespace_exists() {
   local ns="$1"
   if _kubectl --no-exit get ns "$ns" >/dev/null 2>&1; then
      __vault_plan_emit OK "Namespace ${ns} exists"
   else
      __vault_plan_emit TODO "Namespace ${ns} missing" "Would run: kubectl create namespace ${ns}"
   fi
}

function __vault_plan_check_release_state() {
   local ns="$1" release="$2" chart_version="$3"
   if _helm --no-exit -n "$ns" status "$release" >/dev/null 2>&1; then
      __vault_plan_emit OK "Helm release ${release} installed"
      return 0
   fi
   __vault_plan_emit TODO "Helm release ${release} not found" "Would run: helm upgrade --install ${release} hashicorp/vault --version ${chart_version}"
   return 1
}

function __vault_plan_fetch_status_flags() {
   local ns="$1" release="$2"
   local status_json initialized="false" sealed="true"
   status_json=$(_vault_exec --no-exit "$ns" "vault status -format=json" "$release" 2>/dev/null || true)
   if [[ -n "$status_json" ]]; then
      initialized=$(printf '%s' "$status_json" | jq -r 'if .initialized == true then "true" elif .initialized == false then "false" else empty end' 2>/dev/null || printf '')
      sealed=$(printf '%s' "$status_json" | jq -r 'if .sealed == true then "true" elif .sealed == false then "false" else empty end' 2>/dev/null || printf '')
      [[ -z "$initialized" ]] && initialized="false"
      [[ -z "$sealed" ]] && sealed="true"
   fi
   printf '%s %s\n' "$initialized" "$sealed"
}

function __vault_plan_check_downstream() {
   local ns="$1" release="$2"
   if _vault_policy_exists "$ns" "$release" "eso-reader"; then
      __vault_plan_emit OK "ESO Kubernetes auth policies present"
   else
      __vault_plan_emit TODO "ESO policies missing" "Would run: _enable_kv2_k8s_auth"
   fi

   local mount_trim="${LDAP_VAULT_KV_MOUNT:-secret}"
   local secret_trim="${LDAP_JENKINS_SERVICE_ACCOUNT_VAULT_PATH:-ldap/service-accounts/jenkins-admin}"
   mount_trim="${mount_trim%/}"
   secret_trim="${secret_trim#/}"
   secret_trim="${secret_trim%/}"
   local full_path="${mount_trim}/${secret_trim}"
   if _vault_exec --no-exit "$ns" "vault kv get -format=json -- '${full_path}'" "$release" >/dev/null 2>&1; then
      __vault_plan_emit OK "LDAP service account secret (${full_path}) present"
   else
      __vault_plan_emit TODO "LDAP service account secret missing" "Would run: _vault_seed_ldap_service_accounts"
   fi

   if _is_vault_pki_mounted "$ns" "$release" "${VAULT_PKI_PATH:-pki}"; then
      __vault_plan_emit OK "PKI mount ${VAULT_PKI_PATH:-pki} present"
   else
      __vault_plan_emit TODO "PKI mount ${VAULT_PKI_PATH:-pki} missing" "Would run: _vault_setup_pki"
   fi
}

function _vault_plan_report() {
   local ns="${1:-$VAULT_NS_DEFAULT}"
   local release="${2:-$VAULT_RELEASE_DEFAULT}"
   local chart_version="${3:-$VAULT_CHART_VERSION}"
   local eso_ns="${ESO_NAMESPACE:-secrets}"
   printf '[vault] plan for %s/%s\n' "$ns" "$release"

   __vault_plan_check_eso_operator "$eso_ns"
   __vault_plan_check_namespace_exists "$ns"

   local release_ready=0
   if __vault_plan_check_release_state "$ns" "$release" "$chart_version"; then
      release_ready=1
   fi

   local initialized="false" sealed="true"
   if (( release_ready )); then
      read -r initialized sealed <<< "$(__vault_plan_fetch_status_flags "$ns" "$release")"
   fi

   if [[ "$initialized" == "true" && "$sealed" == "false" ]]; then
      __vault_plan_emit OK "Vault initialized and unsealed"
      __vault_plan_check_downstream "$ns" "$release"
   elif [[ "$initialized" == "true" ]]; then
      __vault_plan_emit TODO "Vault sealed" "Would run: deploy_vault --re-unseal"
      __vault_plan_emit WARN "Skipping downstream checks until Vault is unsealed"
   else
      __vault_plan_emit TODO "Vault not initialized" "Would run: deploy_vault"
      __vault_plan_emit WARN "Skipping downstream checks until Vault is initialized"
   fi

   printf '\n'
}

function _deploy_vault_ha() {
   local ns="${1:-$VAULT_NS_DEFAULT}"
   local release="${2:-$VAULT_RELEASE_DEFAULT}"
   local chart_version="${3:-$VAULT_CHART_VERSION}"
   local f="$(mktemp -t vault-ha-vaules.XXXXXX.yaml)"
   trap '$(_cleanup_trap_command "$f")' EXIT TERM

   sc="${VAULT_SC:-local-path}"
   cat >"$f" <<YAML
server:
  ha:
    enabled: true
    replicas: 1
    raft:
      enabled: true
  dataStorage:
    enabled: true
    size: 1Gi
    storageClass: "${sc}"
injector:
  enabled: false
csi:
  enabled: false
YAML
   _mount_vault_immediate_sc "$sc"
   local -a args=(upgrade --install "$release" hashicorp/vault -n "$ns" -f "$f")
   [[ -n "$chart_version" ]] && args+=("--version" "$chart_version")
   _helm "${args[@]}"

   _vault_ensure_data_path "$ns" "$release"
   _cleanup_on_success "$f"
   trap - EXIT TERM
}

# _vault_parse_deploy_opts
# Parses deploy_vault CLI args. Sets globals:
#   _VAULT_DEPLOY_NS _VAULT_DEPLOY_RELEASE _VAULT_DEPLOY_VERSION
#   _VAULT_DEPLOY_RE_UNSEAL _VAULT_DEPLOY_PLAN_MODE
# Args: all original "$@" from deploy_vault (pass after the -h|--help and CLUSTER_ROLE guards)
function _vault_parse_deploy_opts() {
   _VAULT_DEPLOY_NS="${VAULT_NS:-$VAULT_NS_DEFAULT}"
   _VAULT_DEPLOY_RELEASE="$VAULT_RELEASE_DEFAULT"
   _VAULT_DEPLOY_VERSION="$VAULT_CHART_VERSION"
   _VAULT_DEPLOY_RE_UNSEAL=0
   _VAULT_DEPLOY_PLAN_MODE=0

   local ns_set=0 release_set=0 version_set=0
   local -a positional=()

   while [[ $# -gt 0 ]]; do
      case "$1" in
         --namespace)
            [[ -z "${2:-}" ]] && _err "[vault] --namespace flag requires an argument"
            _VAULT_DEPLOY_NS="$2"; ns_set=1; shift 2; continue ;;
         --namespace=*)
            _VAULT_DEPLOY_NS="${1#*=}"
            [[ -z "$_VAULT_DEPLOY_NS" ]] && _err "[vault] --namespace flag requires a non-empty argument"
            ns_set=1; shift; continue ;;
         --release)
            [[ -z "${2:-}" ]] && _err "[vault] --release flag requires an argument"
            _VAULT_DEPLOY_RELEASE="$2"; release_set=1; shift 2; continue ;;
         --release=*)
            _VAULT_DEPLOY_RELEASE="${1#*=}"
            [[ -z "$_VAULT_DEPLOY_RELEASE" ]] && _err "[vault] --release flag requires a non-empty argument"
            release_set=1; shift; continue ;;
         --chart-version)
            [[ -z "${2:-}" ]] && _err "[vault] --chart-version flag requires an argument"
            _VAULT_DEPLOY_VERSION="$2"; version_set=1; shift 2; continue ;;
         --chart-version=*)
            _VAULT_DEPLOY_VERSION="${1#*=}"
            [[ -z "$_VAULT_DEPLOY_VERSION" ]] && _err "[vault] --chart-version flag requires a non-empty argument"
            version_set=1; shift; continue ;;
         --plan)  _VAULT_DEPLOY_PLAN_MODE=1; shift; continue ;;
         --re-unseal)  _VAULT_DEPLOY_RE_UNSEAL=1; shift; continue ;;
         --re-unseal=*)
            case "${1#*=}" in
               1|true|yes|TRUE|YES) _VAULT_DEPLOY_RE_UNSEAL=1 ;;
               0|false|no|FALSE|NO|"") _VAULT_DEPLOY_RE_UNSEAL=0 ;;
               *) _err "[vault] --re-unseal expects yes/no" ;;
            esac
            shift; continue ;;
         --) shift; while [[ $# -gt 0 ]]; do positional+=("$1"); shift; done; break ;;
         -*) _err "[vault] unknown option: $1" ;;
         *) positional+=("$1"); shift; continue ;;
      esac
   done

   local mode="" idx=0
   local positional_count="${#positional[@]}"
   if (( positional_count > 0 )); then
      case "${positional[0]}" in
         ha) mode="ha"; idx=1 ;;
         dev) _err "[vault] dev mode is no longer supported; Vault deploys in HA by default" ;;
      esac
   fi

   for (( ; idx < positional_count; idx++ )); do
      local value="${positional[idx]}"
      (( ns_set == 0 )) && { _VAULT_DEPLOY_NS="$value"; ns_set=1; continue; }
      (( release_set == 0 )) && { _VAULT_DEPLOY_RELEASE="$value"; release_set=1; continue; }
      (( version_set == 0 )) && { _VAULT_DEPLOY_VERSION="$value"; version_set=1; continue; }
      _err "[vault] too many positional arguments"
   done

   _VAULT_DEPLOY_MODE="$mode"
}

# _vault_source_optional_vars
# Sources the optional Vault vars file if present, warns otherwise.
function _vault_source_optional_vars() {
   VAULT_VARS="$SCRIPT_DIR/etc/vault/vars.sh"
   [[ -f "$VAULT_VARS" ]] || { _warn "[vault] missing optional config file: $VAULT_VARS"; return 0; }
   # shellcheck disable=SC1090
   source "$VAULT_VARS"
}

# vault_install_unseal_watchdog [ns] [context]
# Renders + applies the in-cluster auto-unseal watchdog CronJob (Tier 3 P2a).
# Idempotent; safe to apply before a Vault exists (optional secret mount + early exit).
function vault_install_unseal_watchdog() {
   local ns="${1:-${VAULT_NS:-$VAULT_NS_DEFAULT}}"
   local app_context="${2:-}"
   _vault_source_optional_vars
   local template="$SCRIPT_DIR/etc/vault/unseal-watchdog.yaml.tmpl"
   [[ -f "$template" ]] || _err "[vault] missing template: $template"
   local rendered
   rendered="$(mktemp -t vault-unseal-watchdog.XXXXXX.yaml)"
   trap '$(_cleanup_trap_command "$rendered")' EXIT TERM
   VAULT_NS="$ns" \
   VAULT_UNSEAL_IMAGE="${VAULT_UNSEAL_IMAGE:-hashicorp/vault:1.18.3}" \
   VAULT_ENDPOINT="${VAULT_ENDPOINT:-http://vault.${ns}.svc:8200}" \
   envsubst '$VAULT_NS $VAULT_UNSEAL_IMAGE $VAULT_ENDPOINT' < "$template" > "$rendered"
   if [[ -n "$app_context" ]]; then
      kubectl apply --context "$app_context" -f "$rendered" \
         || _err "[vault] failed to apply unseal watchdog to context '$app_context'"
   else
      _kubectl apply -f "$rendered" \
         || _err "[vault] failed to apply unseal watchdog"
   fi
   _cleanup_on_success "$rendered"
   trap - EXIT TERM
}

function deploy_vault() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      cat <<EOF
Usage: deploy_vault [options]
       deploy_vault --re-unseal [options]

Options:
  --namespace <ns>       Vault namespace (default: ${VAULT_NS_DEFAULT})
  --release <name>       Helm release name (default: ${VAULT_RELEASE_DEFAULT})
  --chart-version <ver>  Vault chart version (default: ${VAULT_CHART_VERSION})
  --re-unseal            Replay cached unseal shards and exit
  --plan                 Inspect current state and display the planned actions
  -h, --help             Show this message
EOF
      return 0
   fi

   if [[ "${CLUSTER_ROLE:-infra}" == "app" && "${HUB_VAULT_INCLUSTER:-0}" != "1" ]]; then
      _info "[vault] CLUSTER_ROLE=app — skipping deploy_vault"
      return 0
   fi

   _vault_source_optional_vars

   _vault_parse_deploy_opts "$@"
   local ns="$_VAULT_DEPLOY_NS"
   local release="$_VAULT_DEPLOY_RELEASE"
   local version="$_VAULT_DEPLOY_VERSION"
   local re_unseal="$_VAULT_DEPLOY_RE_UNSEAL"
   local plan_mode="$_VAULT_DEPLOY_PLAN_MODE"
   local mode="$_VAULT_DEPLOY_MODE"

   if (( plan_mode )) && [[ "${K3DM_DEPLOY_DRY_RUN:-0}" == "1" ]]; then
      _err "[vault] --plan cannot be combined with --dry-run"
   fi

   if (( plan_mode )); then
      if (( re_unseal )); then
         _err "[vault] --plan cannot be combined with --re-unseal"
      fi
      _vault_plan_report "$ns" "$release" "$version"
      return 0
   fi

   if (( re_unseal )) && [[ -z "$mode" ]]; then
      _vault_replay_cached_unseal "$ns" "$release"
      return $?
   fi

   if [[ "$mode" == "ha" ]]; then
      _warn "[vault] positional 'ha' is deprecated; deploy_vault always provisions HA"
   fi

   deploy_eso
   _vault_ns_ensure "$ns"
   _vault_repo_setup
   _deploy_vault_ha "$ns" "$release" "$version"
   _vault_bootstrap_ha "$ns" "$release"
   _enable_kv2_k8s_auth "$ns" "$release"
   _vault_seed_ldap_service_accounts "$ns" "$release"
   _vault_setup_pki "$ns" "$release"

   if (( re_unseal )); then
      _vault_replay_cached_unseal "$ns" "$release"
      return $?
   fi

   return 0
}

# Mirror the canonical app-cluster secrets from the laptop (source-of-truth) Vault into the
# in-cluster Vault of an app context, backing each up to the keyring and a native k8s Secret.
# Operator-dispatched only (no auto-caller). Gates the HUB_VAULT_PROFILE default flip.
# Usage: vault_seed_hub_into_context <app-kube-context>
function vault_seed_hub_into_context() {
  local _app_ctx="${1:-}"
  if [[ -z "${_app_ctx}" ]]; then
    _err "[vault] vault_seed_hub_into_context requires an app cluster kube-context"
    return 1
  fi
  if ! _kubectl config get-contexts -o name 2>/dev/null | grep -qx "${_app_ctx}"; then
    _err "[vault] kube-context '${_app_ctx}' not found in kubeconfig"
    return 1
  fi

  local _hub_ctx="k3d-k3d-cluster"
  local _vault_ns="${VAULT_NS:-secrets}"

  # Source (laptop) root token — source of truth.
  local _src_token
  _src_token=$(_kubectl get secret vault-root -n "${_vault_ns}" --context "${_hub_ctx}" \
    -o jsonpath='{.data.root_token}' 2>/dev/null | base64 --decode 2>/dev/null \
    || _kubectl get secret vault-root -n "${_vault_ns}" --context "${_hub_ctx}" \
    -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -D 2>/dev/null || true)
  if [[ -z "${_src_token}" ]]; then
    _err "[vault] could not read source vault-root token from ${_hub_ctx}/${_vault_ns}"
    return 1
  fi

  # Target (in-cluster) root token — provisioned by vault_deploy_hub_into_context (P2b).
  local _dst_token
  _dst_token=$(_kubectl get secret vault-root -n "${_vault_ns}" --context "${_app_ctx}" \
    -o jsonpath='{.data.root_token}' 2>/dev/null | base64 --decode 2>/dev/null \
    || _kubectl get secret vault-root -n "${_vault_ns}" --context "${_app_ctx}" \
    -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -D 2>/dev/null || true)
  if [[ -z "${_dst_token}" ]]; then
    _err "[vault] could not read target vault-root token from ${_app_ctx}/${_vault_ns} — run vault_deploy_hub_into_context first"
    return 1
  fi

  # Token headers via curl --config files (mode 600) so the Vault tokens never appear in argv/ps.
  local _src_hdr _dst_hdr
  _src_hdr=$(mktemp) || { _err "[vault] could not create temp header file"; return 1; }
  _dst_hdr=$(mktemp) || { rm -f "${_src_hdr}" 2>/dev/null || true; _err "[vault] could not create temp header file"; return 1; }
  chmod 600 "${_src_hdr}" "${_dst_hdr}"
  printf 'header = "X-Vault-Token: %s"\n' "${_src_token}" > "${_src_hdr}"
  printf 'header = "X-Vault-Token: %s"\n' "${_dst_token}" > "${_dst_hdr}"

  # Local port-forwards to both Vaults (distinct local ports). SC2064-safe trap (single quotes).
  local _src_port=18250 _dst_port=18251
  local _src_pf_pid="" _dst_pf_pid=""
  _kubectl port-forward -n "${_vault_ns}" --context "${_hub_ctx}" svc/vault "${_src_port}:8200" >/dev/null 2>&1 &
  _src_pf_pid=$!
  _kubectl port-forward -n "${_vault_ns}" --context "${_app_ctx}" svc/vault "${_dst_port}:8200" >/dev/null 2>&1 &
  _dst_pf_pid=$!
  # shellcheck disable=SC2064
  trap '[[ -n "'"${_src_pf_pid}"'" ]] && kill "'"${_src_pf_pid}"'" >/dev/null 2>&1 || true; [[ -n "'"${_dst_pf_pid}"'" ]] && kill "'"${_dst_pf_pid}"'" >/dev/null 2>&1 || true; rm -f "'"${_src_hdr}"'" "'"${_dst_hdr}"'" 2>/dev/null || true' RETURN
  sleep 3

  local _keys=(
    redis/cart redis/orders-cache
    postgres/orders postgres/products postgres/payment
    payment/encryption payment/stripe payment/paypal
    rabbitmq/default minio/credentials
    ldap/admin keycloak/admin keycloak/clients
  )

  local _k8s_args=()
  local _key _json _missing=0
  for _key in "${_keys[@]}"; do
    # 1. canonical source Vault
    _json=$(curl -sf --config "${_src_hdr}" \
      "http://localhost:${_src_port}/v1/secret/data/${_key}" | jq -c '.data.data // empty' 2>/dev/null || true)
    # 2. Keychain backup fallback
    if [[ -z "${_json}" ]] && declare -f _secret_load_data >/dev/null 2>&1; then
      _json=$(_secret_load_data "${SEED_KEYCHAIN_SERVICE:-k3d-manager-app-cluster-secrets}" "${_key}" 2>/dev/null || true)
    fi
    if [[ -z "${_json}" ]]; then
      _warn "[vault] canonical secret '${_key}' absent in source Vault and keyring — skipping"
      _missing=$((_missing + 1))
      continue
    fi
    # write to target in-cluster Vault
    if ! curl -sf -X POST --config "${_dst_hdr}" -H "Content-Type: application/json" \
      -d "{\"data\":${_json}}" "http://localhost:${_dst_port}/v1/secret/data/${_key}" >/dev/null; then
      _err "[vault] failed writing '${_key}' to target Vault on ${_app_ctx}"
      return 1
    fi
    # back up to keyring
    if declare -f _secret_store_data >/dev/null 2>&1; then
      _secret_store_data "${SEED_KEYCHAIN_SERVICE:-k3d-manager-app-cluster-secrets}" "${_key}" "${_json}" >/dev/null 2>&1 \
        || _warn "[vault] keyring backup failed for '${_key}' (continuing)"
    fi
    # accumulate for the native k8s Secret (key path '/' -> '__')
    _k8s_args+=("--from-literal=${_key//\//__}=${_json}")
  done

  # native in-cluster disaster-recovery copy
  _kubectl create namespace "${SEED_K8S_BACKUP_NS:-secrets}" --context "${_app_ctx}" \
    --dry-run=client -o yaml | _kubectl apply --context "${_app_ctx}" -f - >/dev/null 2>&1 || true
  if (( ${#_k8s_args[@]} > 0 )); then
    _kubectl create secret generic "${SEED_K8S_BACKUP_NAME:-vault-seed-backup}" \
      -n "${SEED_K8S_BACKUP_NS:-secrets}" --context "${_app_ctx}" \
      "${_k8s_args[@]}" \
      --dry-run=client -o yaml | _kubectl apply --context "${_app_ctx}" -f - >/dev/null
  fi

  if (( _missing > 0 )); then
    _warn "[vault] seeded in-cluster Vault on ${_app_ctx} with ${_missing} canonical key(s) missing"
  else
    _info "[vault] seeded in-cluster Vault + keyring + k8s backup on ${_app_ctx} (all 13 canonical keys)"
  fi
  return 0
}

# Pure: given the active profile, echo the fallback profile (the other one).
function _vault_hub_fallback_profile() {
  case "${1:-laptop}" in
    hostinger) printf 'laptop\n' ;;
    *)         printf 'hostinger\n' ;;
  esac
}

# Pure: 0 if the Vault /sys/health HTTP status means "reachable" (mirror _is_vault_health).
function _vault_health_status_ok() {
  case "${1:-}" in
    200|429|472|473) return 0 ;;
    *)               return 1 ;;
  esac
}

# Probe the active hub Vault via a short-lived port-forward + curl /sys/health.
# laptop ⇒ probe k3d-k3d-cluster; hostinger ⇒ probe the app context.
# Returns 0 healthy, 1 unreachable. SC2064-safe RETURN trap (single-quoted, pre-expanded).
function _vault_probe_hub_endpoint() {
  local _profile="${1:-laptop}" _app_ctx="${2:-}"
  local _vault_ns="${VAULT_NS:-secrets}"
  local _probe_ctx
  case "${_profile}" in
    hostinger) _probe_ctx="${_app_ctx}" ;;
    *)         _probe_ctx="k3d-k3d-cluster" ;;
  esac
  if [[ -z "${_probe_ctx}" ]]; then
    _err "[vault] _vault_probe_hub_endpoint: hostinger profile requires an app kube-context"
    return 1
  fi
  if ! _kubectl config get-contexts -o name 2>/dev/null | grep -qx "${_probe_ctx}"; then
    return 1
  fi
  local _port=18260 _pid="" _code
  _kubectl port-forward -n "${_vault_ns}" --context "${_probe_ctx}" svc/vault "${_port}:8200" >/dev/null 2>&1 &
  _pid=$!
  # shellcheck disable=SC2064
  trap '[[ -n "'"${_pid}"'" ]] && kill "'"${_pid}"'" >/dev/null 2>&1 || true' RETURN
  sleep 3
  _code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${_port}/v1/sys/health" 2>/dev/null || true)
  _vault_health_status_ok "${_code}"
}

# Assisted failover: probe the active hub Vault; on sustained unreachability flip
# HUB_VAULT_PROFILE to the fallback (persisted), re-seed in-cluster when flipping to
# hostinger, then re-run the Hostinger reconcile so the CSS repoints and ESO re-syncs.
# Operator-dispatched only (no auto-caller). Drives the HUB_VAULT_PROFILE flip.
# Usage: vault_failover_hub_into_context <app-kube-context> [--probe-only]
function vault_failover_hub_into_context() {
  local _app_ctx="" _probe_only=0 _arg
  for _arg in "$@"; do
    case "${_arg}" in
      --probe-only) _probe_only=1 ;;
      -*) _err "[vault] vault_failover_hub_into_context: unknown flag '${_arg}'"; return 1 ;;
      *) [[ -z "${_app_ctx}" ]] && _app_ctx="${_arg}" ;;
    esac
  done
  if [[ -z "${_app_ctx}" ]]; then
    _err "[vault] vault_failover_hub_into_context requires an app cluster kube-context"
    return 1
  fi
  if ! _kubectl config get-contexts -o name 2>/dev/null | grep -qx "${_app_ctx}"; then
    _err "[vault] kube-context '${_app_ctx}' not found in kubeconfig"
    return 1
  fi

  # shellcheck disable=SC1091
  [[ -r "${SCRIPT_DIR}/etc/vault/vars.sh" ]] && source "${SCRIPT_DIR}/etc/vault/vars.sh"

  local _active="${HUB_VAULT_PROFILE:-laptop}"
  local _threshold="${HUB_VAULT_FAILOVER_THRESHOLD:-3}"
  local _interval="${HUB_VAULT_FAILOVER_INTERVAL:-10}"

  local _attempt _healthy=0
  for ((_attempt = 1; _attempt <= _threshold; _attempt++)); do
    if _vault_probe_hub_endpoint "${_active}" "${_app_ctx}"; then
      _healthy=1
      break
    fi
    _warn "[vault] hub Vault probe ${_attempt}/${_threshold} failed (profile=${_active})"
    (( _attempt < _threshold )) && sleep "${_interval}"
  done

  if (( _healthy )); then
    _info "[vault] hub Vault healthy (profile=${_active}); no failover needed"
    return 0
  fi
  if (( _probe_only )); then
    _warn "[vault] hub Vault unreachable (profile=${_active}); --probe-only set, not flipping"
    return 1
  fi

  local _fallback
  _fallback="$(_vault_hub_fallback_profile "${_active}")"
  _warn "[vault] hub Vault unreachable after ${_threshold} probes — failing over ${_active} -> ${_fallback}"

  local _state_file="${HUB_VAULT_PROFILE_STATE_FILE:-${K3DM_STATE_DIR:-${HOME}/.local/share/k3d-manager}/hub-vault-profile}"
  mkdir -p "$(dirname "${_state_file}")" 2>/dev/null || true
  printf '%s\n' "${_fallback}" > "${_state_file}" \
    || { _err "[vault] failed to persist failover profile to ${_state_file}"; return 1; }

  if [[ "${_fallback}" == "hostinger" ]]; then
    _info "[vault] re-seeding in-cluster Vault on ${_app_ctx} before repointing CSS"
    ( vault_seed_hub_into_context "${_app_ctx}" ) \
      || _warn "[vault] re-seed reported issues — relying on existing in-cluster data / DR backup; continuing"
  fi

  unset HUB_VAULT_CSS_SERVER HUB_VAULT_USE_BRIDGE HUB_VAULT_CSS_AUTH
  export HUB_VAULT_PROFILE="${_fallback}"
  # shellcheck disable=SC1091
  [[ -r "${SCRIPT_DIR}/etc/vault/vars.sh" ]] && source "${SCRIPT_DIR}/etc/vault/vars.sh"

  if declare -f _hostinger_reconcile_vault_cluster_store >/dev/null 2>&1; then
    _info "[vault] re-running Hostinger reconcile to repoint CSS (profile=${_fallback})"
    _hostinger_reconcile_vault_cluster_store \
      || { _err "[vault] reconcile failed after failover to ${_fallback}"; return 1; }
  else
    _warn "[vault] _hostinger_reconcile_vault_cluster_store not loaded — CSS not repointed; run 'CLUSTER_PROVIDER=k3s-hostinger make refresh' to apply HUB_VAULT_PROFILE=${_fallback}"
  fi

  _info "[vault] failover complete: HUB_VAULT_PROFILE=${_fallback} (persisted to ${_state_file})"
  return 0
}

# Install the periodic failover watchdog LaunchAgent (control-plane laptop, macOS).
# Idempotent: re-render + bootout/bootstrap. Operator-dispatched.
# Usage: vault_install_failover_watchdog [<app-kube-context>]
function vault_install_failover_watchdog() {
  local _app_ctx="${1:-${HUB_VAULT_FAILOVER_APP_CONTEXT:-ubuntu-hostinger}}"
  local _label="com.k3d-manager.vault-failover"
  local _tmpl="${SCRIPT_DIR}/etc/launchd/${_label}.plist.tmpl"
  local _dst="${HOME}/Library/LaunchAgents/${_label}.plist"
  local _repo_root
  _repo_root="$(cd "${SCRIPT_DIR}/.." && pwd)"
  [[ -f "${_tmpl}" ]] || { _err "[vault] missing template: ${_tmpl}"; return 1; }
  sed \
    -e "s|{{K3DM_REPO_ROOT}}|${_repo_root}|g" \
    -e "s|{{HOME}}|${HOME}|g" \
    -e "s|{{HUB_VAULT_FAILOVER_APP_CONTEXT}}|${_app_ctx}|g" \
    "${_tmpl}" > "${_dst}" \
    || { _err "[vault] failed to render ${_dst}"; return 1; }
  launchctl bootout "gui/$(id -u)/${_label}" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "${_dst}" \
    || { _err "[vault] failed to bootstrap ${_label}"; return 1; }
  _info "[vault] failover watchdog installed (${_label}); probes ${_app_ctx} every 300s"
}

function vault_deploy_hub_into_context() {
   local app_context="${1:-}"
   [[ -n "${app_context}" ]] || _err "[vault] vault_deploy_hub_into_context requires an app cluster kube-context"
   shift || true
   kubectl config get-contexts "${app_context}" >/dev/null 2>&1 \
      || _err "[vault] kube-context '${app_context}' not found in kubeconfig"

   local prev_ctx
   prev_ctx="$(kubectl config current-context 2>/dev/null || true)"
   _VAULT_DEPLOY_PREV_CTX="${prev_ctx}"
   trap '[[ -n "${_VAULT_DEPLOY_PREV_CTX:-}" ]] && kubectl config use-context "${_VAULT_DEPLOY_PREV_CTX}" >/dev/null 2>&1 || true' EXIT TERM

   kubectl config use-context "${app_context}" >/dev/null 2>&1 \
      || _err "[vault] failed to switch to kube-context '${app_context}'"
   _info "[vault] deploying hub Vault into '${app_context}' (in-cluster relocation)"

   local rc=0
   HUB_VAULT_INCLUSTER=1 CLUSTER_ROLE=infra deploy_vault "$@" || rc=$?

   if [[ -n "${prev_ctx}" ]] && kubectl config get-contexts "${prev_ctx}" >/dev/null 2>&1; then
      kubectl config use-context "${prev_ctx}" >/dev/null 2>&1 || true
   fi
   trap - EXIT TERM
   unset _VAULT_DEPLOY_PREV_CTX
   return "${rc}"
}

function _vault_wait_ready() {
   ns="${1:-$VAULT_NS_DEFAULT}"
   release="${2:-$VAULT_RELEASE_DEFAULT}"
   # StatefulSet name is <release>-server per chart
   _kubectl --no-exit -n "$ns" rollout status statefulset/"$release"-server --timeout=180s || true

   _kubectl -n "$ns" wait --for=condition=ready pod \
   -l "app.kubernetes.io/name=vault,app.kubernetes.io/instance=$release" \
   --timeout=180s
}

function _is_vault_deployed() {
   local ns="${1:?}" release="${2:?}"
   _helm --no-exit -n "$ns" status "$release" >/dev/null 2>&1
}

# _vault_reinit_from_reset
# Purges unseal cache, resets data path, restarts pod, re-initializes Vault.
# Args: $1=ns $2=release
function _vault_reinit_from_reset() {
   local ns="$1" release="$2"
   _vault_purge_unseal_cache "$ns" "$release"
   if ! _vault_reset_data_path "$ns" "$release"; then
      _warn "[vault] failed to reset data directory; manual intervention required"
      return 1
   fi
   _vault_restart_pod "$ns" "$release"
   local jsonfile=""
   jsonfile=$(_vault_operator_init "$ns" "$release")
   if [[ -z "$jsonfile" || ! -f "$jsonfile" ]]; then
      _cleanup_on_success "$jsonfile"
      _err "[vault] operator init did not produce artifacts"
   fi
   trap '$(_cleanup_trap_command "$jsonfile")' EXIT TERM
   _vault_process_init_artifacts "$ns" "$release" "$jsonfile"
   trap - EXIT TERM
   _vault_clear_init_json "$jsonfile"
   _info "[vault] vault data directory reset and cluster re-initialized"
}

function _vault_bootstrap_ha() {
  local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
  if [[ "${K3DM_DEPLOY_DRY_RUN:-0}" == "1" ]]; then
     _info "[vault] dry-run requested; skipping bootstrap phase for ${ns}/${release}"
     return 0
  fi
  _info "[vault] bootstrap sequence starting for ${ns}/${release}"
  _is_vault_deployed "$ns" "$release" || _err "[vault] not deployed in ns=$ns release=$release" >&2

  local status_output sealed_state init_state
  status_output=$(_vault_exec --no-exit "$ns" "vault status -format=json 2>/dev/null || vault status 2>&1 || true" "$release")
  sealed_state=$(_vault_parse_sealed_from_status "$status_output" 2>/dev/null || true)
  init_state=$(printf '%s' "$status_output" | jq -r '.initialized // empty' 2>/dev/null || true)

  local root_secret_present=0
  _kubectl --no-exit -n "$ns" get secret vault-root >/dev/null 2>&1 && root_secret_present=1

  if [[ "${init_state,,}" == "true" ]]; then
     if [[ "${sealed_state,,}" == "true" ]]; then
        _vault_cache_unseal_from_secret "$ns" "$release" >/dev/null 2>&1 || true
        local replay_rc
        _vault_replay_cached_unseal "$ns" "$release" 1
        replay_rc=$?
        _info "[vault] cached unseal replay exit=${replay_rc}"
        if (( replay_rc == 0 )); then
           _vault_login "$ns" "$release"
           _info "[vault] already initialized; applied cached unseal shards"
           return 0
        fi
        if (( replay_rc == 42 )); then
           _warn "[vault] cached unseal shards rejected; resetting data directory and re-initializing"
        elif (( replay_rc == 43 )); then
           _warn "[vault] cached unseal shards missing; resetting data directory and re-initializing"
        fi
        if (( replay_rc == 42 || replay_rc == 43 )); then
           _vault_reinit_from_reset "$ns" "$release" || return 1
           return 0
        fi
        _warn "[vault] already initialized (sealed) but automatic unseal failed; manual intervention required"
        return 1
     fi
     if (( !root_secret_present )); then
        _warn "[vault] root token secret missing; resetting data directory and re-initializing"
        _vault_reinit_from_reset "$ns" "$release" || return 1
        return 0
     fi
     _vault_login "$ns" "$release"
     _info "[vault] already initialized and unsealed"
     return 0
  fi

  local jsonfile=""
  jsonfile=$(_vault_operator_init "$ns" "$release")
  if [[ -z "$jsonfile" || ! -f "$jsonfile" ]]; then
     _cleanup_on_success "$jsonfile"
     _err "[vault] operator init did not produce artifacts"
  fi
  trap '$(_cleanup_trap_command "$jsonfile")' EXIT TERM
  _vault_process_init_artifacts "$ns" "$release" "$jsonfile"
  trap - EXIT TERM
  _vault_clear_init_json "$jsonfile"
}

function _vault_portforward_help() {
   ns="${1:-$VAULT_NS_DEFAULT}"
   release="${2:-$VAULT_RELEASE_DEFAULT}"
   cat <<EOF
[vault] Port-forward UI/API (run in another terminal):
  _kubectl -n ${ns} port-forward svc/${release} 8200:8200

Then:
  export VAULT_ADDR='http://127.0.0.1:8200'
  # For dev mode, get token:
  _kubectl -n ${ns} exec -it sts/${release}-server -- printenv VAULT_DEV_ROOT_TOKEN_ID
  # Or from logs:
  _kubectl -n ${ns} logs sts/${release}-server -c vault | grep -m1 'Root Token'
  # For HA mode, use stored secret:
  export VAULT_TOKEN="\$(_kubectl -n ${ns} get secret vault-root -o jsonpath='{.data.root_token}' | base64 -d)"
EOF
}

function _vault_operator_init() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local leader="${release}-0"
   local jsonfile

   jsonfile=$(mktemp -t vault-init.XXXXXX.json)
   trap '$(_cleanup_trap_command "$jsonfile")' EXIT TERM

   local pod_deadline=$((SECONDS + 180))
   while (( SECONDS < pod_deadline )); do
      if _kubectl --no-exit -n "$ns" get pod "$leader" >/dev/null 2>&1; then
         break
      fi
      sleep 2
   done
   if (( SECONDS >= pod_deadline )); then
      _cleanup_on_success "$jsonfile"
      _err "[vault] pod $leader did not appear within timeout"
   fi

   local vault_state=""
   local end_time=$((SECONDS + 240))
   while (( SECONDS < end_time )); do
      vault_state=$(_kubectl --no-exit -n "$ns" get pod "$leader" -o jsonpath='{.status.phase}' 2>/dev/null || true)
      if [[ "$vault_state" == "Running" ]]; then
         break
      fi
      _info "[vault] waiting for $leader to be Running (current=${vault_state:-unknown})"
      sleep 3
   done
   if [[ "$vault_state" != "Running" ]]; then
      _cleanup_on_success "$jsonfile"
      _err "[vault] timeout waiting for $leader to be Running (last=${vault_state:-unknown})"
   fi

   if ! _vault_exec "$ns" "vault operator init -key-shares=1 -key-threshold=1 -format=json" "$release" >"$jsonfile"; then
      _cleanup_on_success "$jsonfile"
      _err "[vault] failed to execute vault operator init"
   fi

   trap - EXIT TERM
   printf '%s\n' "$jsonfile"
}

function _vault_process_init_artifacts() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}" jsonfile="${3:?json file required}"

   local root_token
   local key_shares
   local key_threshold
   local -a unseal_keys=()

   root_token=$(jq -r '.root_token' "$jsonfile")
   key_shares=$(jq -r '.key_shares' "$jsonfile")
   key_threshold=$(jq -r '.key_threshold' "$jsonfile")
   while IFS= read -r shard; do
      shard=${shard%$'\r'}
      [[ -z "$shard" ]] && continue
      unseal_keys+=("$shard")
   done < <(jq -r '.unseal_keys_b64[]' "$jsonfile")

   if (( ${#unseal_keys[@]} == 0 )); then
      _err "[vault] no unseal keys returned during init"
   fi

   if [[ ! "$key_shares" =~ ^[0-9]+$ || $key_shares -le 0 ]]; then
      key_shares=${#unseal_keys[@]}
   fi

   if [[ ! "$key_threshold" =~ ^[0-9]+$ || $key_threshold -le 0 ]]; then
      key_threshold=1
   fi

   local threshold=$key_threshold
   if (( threshold > ${#unseal_keys[@]} )); then
      threshold=${#unseal_keys[@]}
   fi

   _kubectl --no-exit -n "$ns" delete secret vault-root >/dev/null 2>&1 || true
   _no_trace _kubectl -n "$ns" create secret generic vault-root \
      --from-literal=root_token="$root_token"

   local -a shard_literals=(
      "--from-literal=key-shares=${key_shares}"
      "--from-literal=key-threshold=${key_threshold}"
   )
   local shard_idx
   for (( shard_idx=0; shard_idx<${#unseal_keys[@]}; shard_idx++ )); do
      shard_literals+=("--from-literal=shard-$((shard_idx+1))=${unseal_keys[$shard_idx]}")
   done
   _kubectl --no-exit -n "$ns" delete secret vault-unseal >/dev/null 2>&1 || true
   _no_trace _kubectl -n "$ns" create secret generic vault-unseal "${shard_literals[@]}"

  _vault_cache_unseal_keys "$ns" "$release" "${unseal_keys[@]}"

  local i shard
  for pod in $(_kubectl --no-exit -n "$ns" get pod -l "app.kubernetes.io/name=vault,app.kubernetes.io/instance=${release}" -o name); do
      pod="${pod#pod/}"
      for (( i=0; i<threshold; i++ )); do
         shard="${unseal_keys[$i]}"
         _no_trace _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
            sh -lc "vault operator unseal $shard" >/dev/null 2>&1 || true
      done
      _info "[vault] unsealed $pod"
   done

  if ! _is_vault_health "$ns" "$release" ; then
     _err "[vault] vault not healthy after init/unseal"
  else
     _info "[vault] vault is ready to serve"
     _vault_portforward_help "$ns" "$release"
  fi

  _vault_login "$ns" "$release"
}

function _vault_clear_init_json() {
   local jsonfile="${1:-}"
   [[ -z "$jsonfile" ]] && return 0
   _cleanup_on_success "$jsonfile"
}

function _is_vault_health() {
  local ns="${1:?}" release="${2:?}" scheme="${3:-http}" port="${4:-8200}"
  local host="${release}.${ns}.svc" status_marker="VAULT_HTTP_STATUS"
  local rc status attempt max_attempts=3

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    local name="vault-health-$RANDOM$RANDOM"
    rc=$(_kubectl --no-exit -n "$ns" run "$name" --rm -i --restart=Never \
      --image=curlimages/curl:8.10.1 --command -- sh -c \
      "curl -o /dev/null -s -w '${status_marker}:%{http_code}' '${scheme}://${host}:${port}/v1/sys/health'")

    # kubectl may emit interactive prompts and deletion messages before or after
    # the command output; locate the explicit status marker to avoid false hits.
    rc=${rc//$'\r'/}

    local status_line
    status_line=$(printf '%s\n' "$rc" | grep -Eo "${status_marker}:[0-9]{3}" | tail -n1)
    status="${status_line##*:}"
    if [[ "$status" == "$status_line" ]]; then
      status=""
    fi

    local status_display="${status:-<missing>}"

    case "$status" in
      200|429|472|473)
        _info "return code: $status_display"
        return 0
        ;;
      *)
        _info "return code: $status_display"
        if (( attempt < max_attempts )); then
          _warn "[vault] health check attempt ${attempt}/${max_attempts} returned ${status_display}; retrying"
        fi
        ;;
    esac
  done

  return 1
}

function _vault_login() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local token_b64 token=""

   if [[ "${K3DM_DEPLOY_DRY_RUN:-0}" == "1" ]]; then
      _info "[vault] dry-run requested; skipping login for ${ns}/${release}"
      return 0
   fi

   token_b64=$(_no_trace _kubectl --no-exit -n "$ns" get secret vault-root -o jsonpath='{.data.root_token}' 2>/dev/null || true)
   if [[ -z "$token_b64" ]]; then
      _err "[vault] root token secret vault-root missing in ${ns}"
   fi

  token=$(_no_trace bash -c 'printf %s "$1" | base64 -d 2>/dev/null' _ "$token_b64")
  if [[ -z "$token" ]]; then
     _err "[vault] unable to decode root token from secret vault-root"
  fi
  token=${token//$'\r'/}
  token=${token//$'\n'/}
  if [[ -z "$token" ]]; then
      _err "[vault] decoded root token is empty for namespace ${ns}"
  fi

  local login_rc=0
  local login_output=""
  login_output=$(_no_trace _vault_exec_stream --no-exit "$ns" "$release" -- env VAULT_TOKEN="$token" vault token lookup -format=json 2>&1) || login_rc=$?
  if (( login_rc != 0 )); then
      login_output=${login_output//$'\n'/ }
      login_output=${login_output//$'\r'/ }
      _err "[vault] failed to login to ${release} in namespace ${ns}: ${login_output:-unknown error}"
  fi

  _VAULT_SESSION_TOKENS["${ns}/${release}"]="$token"
}

function _vault_policy_exists() {
  local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}" name="${3:-eso-reader}"

  if _vault_exec --no-exit "$ns" "vault policy list" "$release" | grep -q "^${name}\$"; then
     return 0
  fi

  return 1
}

function _enable_kv2_k8s_auth() {
  local ns="${1:-$VAULT_NS_DEFAULT}"
  local release="${2:-$VAULT_RELEASE_DEFAULT}"
  local eso_sa="${3:-external-secrets}"
  local eso_ns="${4:-${ESO_NAMESPACE:-secrets}}"

  _vault_set_eso_reader "$ns" "$release" "$eso_sa" "$eso_ns"
  _vault_set_eso_writer "$ns" "$release" "$eso_sa" "$eso_ns"
  if [[ "${ENABLE_JENKINS:-0}" == "1" ]]; then
    _vault_set_eso_init_jenkins_writer "$ns" "$release" "$eso_sa" "$eso_ns"
  fi
}

function configure_vault_app_auth() {
  local ns="${VAULT_NS:-$VAULT_NS_DEFAULT}"
  local release="${VAULT_RELEASE:-$VAULT_RELEASE_DEFAULT}"
  local app_api_url="${APP_CLUSTER_API_URL:-}"
  local app_ca_path="${APP_CLUSTER_CA_CERT_PATH:-}"
  local mount="${APP_K8S_AUTH_MOUNT:-kubernetes-app}"
  local role="${APP_ESO_VAULT_ROLE:-eso-app-cluster}"
  local eso_sa="${APP_ESO_SA_NAME:-external-secrets}"
  local eso_ns="${APP_ESO_SA_NS:-secrets}"

  if [[ -z "$app_api_url" ]]; then
    _err "[vault] APP_CLUSTER_API_URL is required for configure_vault_app_auth"
  fi

  if [[ -z "$app_ca_path" ]]; then
    _err "[vault] APP_CLUSTER_CA_CERT_PATH is required for configure_vault_app_auth"
  fi

  if [[ ! -f "$app_ca_path" ]]; then
    _err "[vault] app cluster CA cert file not found at $app_ca_path"
  fi

  _info "[vault] configuring app cluster auth at mount: ${mount}"

  # Ensure we are logged in
  _vault_login "$ns" "$release"

  # a. Copy CA cert into vault-0 pod
  _kubectl -n "$ns" cp "$app_ca_path" "${release}-0:/tmp/app-cluster-ca.crt"

  # b. Enable kubernetes auth mount (idempotent)
  _vault_exec "$ns" "vault auth enable -path=${mount} kubernetes" "$release" || true

  # c. Configure mount with app cluster API server + CA cert
  #    Default local JWT validation — Vault verifies JWTs against the provided CA cert
  #    without calling the Ubuntu k3s TokenReview API (avoids OrbStack networking issues)
  _vault_exec "$ns" "vault write auth/${mount}/config \
    kubernetes_host=${app_api_url} \
    kubernetes_ca_cert=@/tmp/app-cluster-ca.crt" "$release"

  # d. Ensure eso-reader policy exists
  if ! _vault_policy_exists "$ns" "$release" "eso-reader"; then
    _info "[vault] creating policy 'eso-reader'"
    cat <<'HCL' | _vault_exec_stream --no-exit --pod "${release}-0" "$ns" "$release" -- \
      vault policy write eso-reader -
       # file: eso-reader.hcl
       # read any keys under eso/*
       path "secret/data/eso/*"      { capabilities = ["read"] }
       path "secret/metadata/eso"    { capabilities = ["list"] }
       path "secret/metadata/eso/*"  { capabilities = ["read","list"] }
HCL
  fi

  # d2. Ensure app-cluster-reader policy exists (least-privilege: app business paths only)
  if ! _vault_policy_exists "$ns" "$release" "app-cluster-reader"; then
    _info "[vault] creating policy 'app-cluster-reader'"
    cat <<'HCL' | _vault_exec_stream --no-exit --pod "${release}-0" "$ns" "$release" -- \
      vault policy write app-cluster-reader -
       # file: app-cluster-reader.hcl
       # least-privilege read for the app-cluster ESO ClusterSecretStore
       path "secret/data/postgres/*"     { capabilities = ["read"] }
       path "secret/data/payment/*"      { capabilities = ["read"] }
       path "secret/data/redis/*"        { capabilities = ["read"] }
       path "secret/data/rabbitmq/*"     { capabilities = ["read"] }
       path "secret/data/keycloak/*"     { capabilities = ["read"] }
       path "secret/data/ldap/*"         { capabilities = ["read"] }
       path "secret/data/minio/*"        { capabilities = ["read"] }
       path "secret/metadata/postgres/*" { capabilities = ["read","list"] }
       path "secret/metadata/payment/*"  { capabilities = ["read","list"] }
       path "secret/metadata/redis/*"    { capabilities = ["read","list"] }
       path "secret/metadata/rabbitmq/*" { capabilities = ["read","list"] }
       path "secret/metadata/keycloak/*" { capabilities = ["read","list"] }
       path "secret/metadata/ldap/*"     { capabilities = ["read","list"] }
       path "secret/metadata/minio/*"    { capabilities = ["read","list"] }
HCL
  fi

  # e. Create ESO role bound to app cluster ESO service account
  local audience="${APP_K8S_TOKEN_AUDIENCE:-https://kubernetes.default.svc.cluster.local}"
  local safe_mount_role safe_eso_sa safe_eso_ns safe_audience
  printf -v safe_mount_role '%s' "auth/${mount}/role/${role}"
  printf -v safe_eso_sa '%q' "$eso_sa"
  printf -v safe_eso_ns '%q' "$eso_ns"
  printf -v safe_audience '%q' "$audience"
  _vault_exec "$ns" "vault write ${safe_mount_role} \
    bound_service_account_names=${safe_eso_sa} \
    bound_service_account_namespaces=${safe_eso_ns} \
    audience=${safe_audience} \
    policies=app-cluster-reader \
    ttl=1h" "$release"

  _info "[vault] app cluster auth configured successfully"
}

function configure_vault_app_auth_for_context() {
  local app_context="${1:-}"
  local app_kubeconfig="${2:-${KUBECONFIG:-}}"
  if [[ -z "${app_context}" ]]; then
    _err "[vault] configure_vault_app_auth_for_context requires an app cluster kube-context"
  fi

  local -a kctl=(kubectl)
  [[ -n "${app_kubeconfig}" ]] && kctl=(kubectl --kubeconfig "${app_kubeconfig}")

  local cluster_name
  cluster_name="$("${kctl[@]}" config view --raw \
    -o jsonpath="{.contexts[?(@.name==\"${app_context}\")].context.cluster}" 2>/dev/null)"
  [[ -n "${cluster_name}" ]] || cluster_name="${app_context}"

  local server ca_data ca_file
  server="$("${kctl[@]}" config view --raw \
    -o jsonpath="{.clusters[?(@.name==\"${cluster_name}\")].cluster.server}" 2>/dev/null)"
  ca_data="$("${kctl[@]}" config view --raw \
    -o jsonpath="{.clusters[?(@.name==\"${cluster_name}\")].cluster.certificate-authority-data}" 2>/dev/null)"
  ca_file="$("${kctl[@]}" config view --raw \
    -o jsonpath="{.clusters[?(@.name==\"${cluster_name}\")].cluster.certificate-authority}" 2>/dev/null)"

  if [[ -z "${server}" ]]; then
    _warn "[vault] no API server for context '${app_context}' — skipping app-cluster Vault auth"
    [[ "${APP_VAULT_AUTH_REQUIRED:-false}" == "true" ]] && return 1
    return 0
  fi

  local tmp_ca="" ca_path=""
  if [[ -n "${ca_data}" ]]; then
    tmp_ca="$(mktemp "${TMPDIR:-/tmp}/app-cluster-ca.XXXXXX")" || return 1
    printf '%s' "${ca_data}" | base64 --decode > "${tmp_ca}" 2>/dev/null \
      || printf '%s' "${ca_data}" | base64 -D > "${tmp_ca}" 2>/dev/null || {
      rm -f "${tmp_ca}"
      _warn "[vault] could not decode CA data for '${app_context}' — skipping app-cluster Vault auth"
      [[ "${APP_VAULT_AUTH_REQUIRED:-false}" == "true" ]] && return 1
      return 0
    }
    ca_path="${tmp_ca}"
  elif [[ -n "${ca_file}" && -f "${ca_file}" ]]; then
    ca_path="${ca_file}"
  else
    _warn "[vault] no CA for context '${app_context}' — skipping app-cluster Vault auth"
    [[ "${APP_VAULT_AUTH_REQUIRED:-false}" == "true" ]] && return 1
    return 0
  fi

  local rc=0
  local _prev_ctx="" _switched_ctx=0
  if [[ "${HUB_VAULT_USE_BRIDGE:-1}" == "0" ]]; then
    _prev_ctx="$("${kctl[@]}" config current-context 2>/dev/null || true)"
    if [[ -n "${_prev_ctx}" && "${_prev_ctx}" != "${app_context}" ]]; then
      if "${kctl[@]}" config use-context "${app_context}" >/dev/null 2>&1; then
        _switched_ctx=1
        _info "[vault] in-cluster profile: configuring app-cluster auth on '${app_context}' Vault"
      else
        _warn "[vault] could not switch to context '${app_context}' for in-cluster Vault auth"
      fi
    fi
  fi
  (
    APP_CLUSTER_API_URL="${server}" \
    APP_CLUSTER_CA_CERT_PATH="${ca_path}" \
    configure_vault_app_auth
  ) || rc=$?
  if (( _switched_ctx )) && [[ -n "${_prev_ctx}" ]]; then
    "${kctl[@]}" config use-context "${_prev_ctx}" >/dev/null 2>&1 || true
  fi

  [[ -n "${tmp_ca}" ]] && rm -f "${tmp_ca}"

  if (( rc != 0 )); then
    _warn "[vault] app-cluster Vault auth for '${app_context}' did not complete (rc=${rc})"
    [[ "${APP_VAULT_AUTH_REQUIRED:-false}" == "true" ]] && return "${rc}"
  fi
  return 0
}

function _vault_set_eso_reader() {
  local ns="${1:-$VAULT_NS_DEFAULT}"
  local release="${2:-$VAULT_RELEASE_DEFAULT}"
  local eso_sa="${3:-external-secrets}"
  local eso_ns="${4:-${ESO_NAMESPACE:-secrets}}"
  local pod="${release}-0"

  if _vault_policy_exists "$ns" "$release" "eso-reader"; then
     _info "[vault] policy 'eso-reader' already exists, skipping k8s auth setup"
     return 0
  fi

  _vault_login "$ns" "$release"
  # kubernetes auth so no token stored in k8s
  cat <<'SH' | _no_trace _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
    sh -
set -e
vault secrets enable -path=secret kv-v2 || true
vault auth enable kubernetes || true

vault write auth/kubernetes/config \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
SH

  _kubectl create clusterrolebinding vault-auth-delegator \
    --clusterrole=system:auth-delegator \
    --serviceaccount="${ns}:${release}" \
    --dry-run=client -o yaml | _kubectl apply -f -

  # create a policy -- eso-reader
  cat <<'HCL' | _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
    vault policy write eso-reader -
     # file: eso-reader.hcl
     # read any keys under eso/*
     path "secret/data/eso/*"      { capabilities = ["read"] }
     path "secret/metadata/eso"    { capabilities = ["list"] }
     path "secret/metadata/eso/*"  { capabilities = ["read","list"] }

HCL

  # map ESO service account to the policy
  _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
    vault write auth/kubernetes/role/eso-reader \
      bound_service_account_names="$eso_sa" \
      bound_service_account_namespaces="$eso_ns" \
      policies=eso-reader \
      ttl=1h
}

function _vault_set_eso_writer() {
  local ns="${1:-$VAULT_NS_DEFAULT}"
  local release="${2:-$VAULT_RELEASE_DEFAULT}"
  local eso_sa="${3:-external-secrets}"
  local eso_ns="${4:-${ESO_NAMESPACE:-secrets}}"
  local pod="${release}-0"

  if _vault_policy_exists "$ns" "$release" "eso-writer"; then
     _info "[vault] policy 'eso-writer' already exists, skipping k8s auth setup"
     return 0
  fi

  # create a policy -- eso-writer
  cat <<'HCL' | _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- sh - \
    vault policy write eso-writer
     # file: eso-writer.hcl
     path "secret/data/eso/*"      { capabilities = ["create","update","read"] }
     path "secret/metadata/eso"    { capabilities = ["list"] }
     path "secret/metadata/eso/*"  { capabilities = ["read","list"] }
HCL

  # map ESO service account to the policy
  _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
    sh - \
    vault write auth/kubernetes/role/eso-writer \
      bound_service_account_names="$eso_sa" \
      bound_service_account_namespaces="$eso_ns" \
      policies=eso-writer \
      ttl=30m
}

function _vault_set_eso_init_jenkins_writer() {
  local ns="${1:-$VAULT_NS_DEFAULT}"
  local release="${2:-$VAULT_RELEASE_DEFAULT}"
  local eso_sa="${3:-external-secrets}"
  local eso_ns="${4:-${ESO_NAMESPACE:-secrets}}"
  local pod="${release}-0"

  if _vault_policy_exists "$ns" "$release" "eso-init-jenkins-writer"; then
     _info "[vault] policy 'eso-writer' already exists, skipping k8s auth setup"
     return 0
  fi

  # create a policy -- eso-writer
  _vault_login "$ns" "$release"
  cat <<'HCL' | _no_trace _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
    vault policy write eso-init-jenkins-writer -
     # file: eso-writer.hcl
     path "secret/data/eso/jenkins-admin"     { capabilities = ["create","update","read"] }
     path "secret/metadata/eso/jenkins-admin" { capabilities = ["read","list"] }

HCL

  # map ESO service account to the policy
  _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
    vault write auth/kubernetes/role/eso-writer \
      bound_service_account_names="$eso_sa" \
      bound_service_account_namespaces="$eso_ns" \
      policies=eso-writer \
      ttl=15m
}

# _vault_build_policy_hcl
# Builds a Vault policy HCL string granting read on a list of secret prefixes.
# Sets global: _VAULT_POLICY_HCL
# Args: $1=mount_path, remaining args=prefix list
function _vault_build_policy_hcl() {
   local mount_path="$1"; shift
   local -a secret_prefixes=("$@")

   _VAULT_POLICY_HCL=""
   local prefixes_added=0
   local -a metadata_paths=()

   local prefix
   for prefix in "${secret_prefixes[@]}"; do
      local prefix_trimmed="${prefix#/}"
      prefix_trimmed="${prefix_trimmed%/}"
      [[ -z "$prefix_trimmed" ]] && continue

      local data_block
      printf -v data_block '%s\n%s\n%s\n%s' \
        "path \"${mount_path}/data/${prefix_trimmed}\"       { capabilities = [\"read\"] }" \
        "path \"${mount_path}/data/${prefix_trimmed}/*\"     { capabilities = [\"read\"] }" \
        "path \"${mount_path}/metadata/${prefix_trimmed}\"   { capabilities = [\"read\", \"list\"] }" \
        "path \"${mount_path}/metadata/${prefix_trimmed}/*\" { capabilities = [\"read\", \"list\"] }"

      (( prefixes_added )) && _VAULT_POLICY_HCL+=$'\n'
      _VAULT_POLICY_HCL+="$data_block"
      prefixes_added=1

      local parent_prefix="${prefix_trimmed%/*}"
      while [[ -n "$parent_prefix" && "$parent_prefix" != "$prefix_trimmed" ]]; do
         local skip_parent=0
         local seen_prefix
         for seen_prefix in "${metadata_paths[@]}"; do
            [[ "$seen_prefix" == "$parent_prefix" ]] && { skip_parent=1; break; }
         done
         if (( ! skip_parent )); then
            metadata_paths+=("$parent_prefix")
            _VAULT_POLICY_HCL+=$'\n'
            local metadata_block
            printf -v metadata_block '%s\n%s' \
              "path \"${mount_path}/metadata/${parent_prefix}\"   { capabilities = [\"read\", \"list\"] }" \
              "path \"${mount_path}/metadata/${parent_prefix}/*\" { capabilities = [\"read\", \"list\"] }"
            _VAULT_POLICY_HCL+="$metadata_block"
         fi
         local next_parent="${parent_prefix%/*}"
         [[ "$next_parent" == "$parent_prefix" ]] && break
         parent_prefix="$next_parent"
      done
   done

   if (( ! prefixes_added )); then
      _err "[vault] secret prefix required for role configuration"
   fi
}

function _vault_configure_secret_reader_role() {
  local ns="${1:-$VAULT_NS_DEFAULT}"
  local release="${2:-$VAULT_RELEASE_DEFAULT}"
  local service_account="${3:-secrets}"
  local service_namespace="${4:-secrets}"
  local mount="${5:-secret}"
  local secret_prefix_arg="${6:-ldap}"
  local role="${7:-eso-ldap-directory}"
  local policy="${8:-${role}}"
  local role_namespaces_override="${9:-}"
  local pod="${release}-0"

  local sanitized_prefixes="${secret_prefix_arg//,/ }"
  local -a secret_prefixes=()
  if [[ -n "$sanitized_prefixes" ]]; then
     read -r -a secret_prefixes <<< "$sanitized_prefixes"
  fi

  if (( ${#secret_prefixes[@]} == 0 )); then
     _err "[vault] secret prefix required for role configuration"
  fi

  _vault_login "$ns" "$release"

  local mount_path="${mount%/}"
  local mount_json=""
  mount_json=$(_vault_exec --no-exit "$ns" "vault secrets list -format=json" "$release" 2>/dev/null || true)
  if [[ -z "$mount_json" ]] || ! printf '%s' "$mount_json" | jq -e --arg PATH "${mount_path}/" 'has($PATH)' >/dev/null 2>&1; then
     _vault_exec "$ns" "vault secrets enable -path=${mount_path} kv-v2" "$release" ||         _err "[vault] failed to enable kv engine at ${mount_path}"
  fi

  local auth_json=""
  auth_json=$(_vault_exec --no-exit "$ns" "vault auth list -format=json" "$release" 2>/dev/null || true)
  if [[ -z "$auth_json" ]] || ! printf '%s' "$auth_json" | jq -e --arg PATH "kubernetes/" 'has($PATH)' >/dev/null 2>&1; then
     _vault_exec "$ns" "vault auth enable kubernetes" "$release" ||         _err "[vault] failed to enable kubernetes auth method"
  fi

  cat <<'SH' | _no_trace _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- sh -
set -e
vault write auth/kubernetes/config   token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"   kubernetes_host="https://kubernetes.default.svc:443"   kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
SH

  _kubectl create clusterrolebinding vault-auth-delegator     --clusterrole=system:auth-delegator     --serviceaccount="${ns}:${release}"     --dry-run=client -o yaml | _kubectl apply -f -

  _vault_build_policy_hcl "$mount_path" "${secret_prefixes[@]}"
  local policy_hcl="$_VAULT_POLICY_HCL"

  if ! printf '%s\n' "$policy_hcl" | _no_trace _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" --     vault policy write "${policy}" -; then
     _err "[vault] failed to apply policy ${policy}"
  fi

  local token_audience="${K8S_TOKEN_AUDIENCE:-https://kubernetes.default.svc.cluster.local}"
  local bound_namespaces="$service_namespace"
  if [[ -n "$role_namespaces_override" ]]; then
     bound_namespaces="$role_namespaces_override"
  elif [[ "$role" == "eso-ldap-directory" && "$service_namespace" != "identity" ]]; then
     bound_namespaces="${service_namespace},identity"
  fi

  local role_cmd=""
  printf -v role_cmd 'vault write "auth/kubernetes/role/%s" bound_service_account_names="%s" bound_service_account_namespaces="%s" policies="%s" ttl=1h token_audiences="%s"'      "$role" "$service_account" "$bound_namespaces" "$policy" "$token_audience"

  _vault_exec "$ns" "$role_cmd" "$release"
}

# _vault_build_parent_metadata_policy
# Appends parent-path metadata policy blocks to an existing policy HCL string.
# Sets global: _VAULT_PARENT_POLICY_HCL (appended)
# Args: $1=mount_trim $2=secret_trim $3=metadata_path (to skip if already present)
function _vault_build_parent_metadata_policy() {
   local mount_trim="$1" secret_trim="$2" metadata_path="$3"

   local parent="${secret_trim%/*}"
   while [[ -n "$parent" && "$parent" != "$secret_trim" ]]; do
      local parent_metadata="${mount_trim}/metadata/${parent}"
      if [[ "$parent_metadata" != "$metadata_path" ]]; then
         _VAULT_PARENT_POLICY_HCL+=$'\n'
         _VAULT_PARENT_POLICY_HCL+=$(cat <<EOF
path "${parent_metadata}" {
  capabilities = ["read", "list"]
}
EOF
)
      fi
      [[ "$parent" == "${parent%/*}" ]] && break
      parent="${parent%/*}"
   done
}

function _vault_seed_ldap_service_accounts() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local mount="${LDAP_VAULT_KV_MOUNT:-secret}"
   local secret_path="${LDAP_JENKINS_SERVICE_ACCOUNT_VAULT_PATH:-ldap/service-accounts/jenkins-admin}"
   local username="${LDAP_JENKINS_SERVICE_ACCOUNT_USERNAME:-jenkins-admin}"
   local group_cn="${LDAP_JENKINS_SERVICE_ACCOUNT_GROUP:-it develop}"
   local username_key="${LDAP_JENKINS_SERVICE_ACCOUNT_USERNAME_KEY:-username}"
   local password_key="${LDAP_JENKINS_SERVICE_ACCOUNT_PASSWORD_KEY:-password}"
   local group_key="${LDAP_JENKINS_SERVICE_ACCOUNT_GROUP_KEY:-group_cn}"
   local policy="${LDAP_JENKINS_SERVICE_ACCOUNT_POLICY:-jenkins-ldap-service-account}"
   local description="${LDAP_JENKINS_SERVICE_ACCOUNT_DESCRIPTION:-Jenkins LDAP service account}"

   local mount_trim="${mount%/}"
   local secret_trim="${secret_path#/}"
   secret_trim="${secret_trim%/}"

   [[ -z "$mount_trim" ]] && _err "[vault] KV mount required for LDAP service account seed"
   [[ -z "$secret_trim" ]] && _err "[vault] LDAP service account path required"
   [[ -z "$policy" ]] && _err "[vault] LDAP service account policy name required"

   local full_path="${mount_trim}/${secret_trim}"
   local pod="${release}-0"

   _vault_login "$ns" "$release"

   local check_cmd=""
   printf -v check_cmd 'vault kv get -format=json %q >/dev/null 2>&1' "$full_path"

   local secret_exists=0
   _vault_exec --no-exit "$ns" "$check_cmd" "$release" >/dev/null 2>&1 && secret_exists=1

   if (( !secret_exists )); then
      local password=""
      password=$(_no_trace bash -c 'openssl rand -base64 24 | tr -d "\n"' 2>/dev/null || true)
      [[ -z "$password" ]] && _err "[vault] failed to generate password for ${full_path}"

      local write_cmd=""
      if [[ -n "$description" ]]; then
         printf -v write_cmd 'vault kv put %q %s=%q %s=%q %s=%q description=%q'             "$full_path" "$username_key" "$username" "$password_key" "$password" "$group_key" "$group_cn" "$description"
      else
         printf -v write_cmd 'vault kv put %q %s=%q %s=%q %s=%q'             "$full_path" "$username_key" "$username" "$password_key" "$password" "$group_key" "$group_cn"
      fi

      if ! _no_trace _vault_exec "$ns" "$write_cmd" "$release"; then
         _err "[vault] failed to seed service account secret at ${full_path}"
      fi
      _info "[vault] seeded LDAP service account secret ${full_path}"
   else
      _info "[vault] service account secret ${full_path} already present; skipping seed"
   fi

   local data_path="${mount_trim}/data/${secret_trim}"
   local metadata_path="${mount_trim}/metadata/${secret_trim}"
   local policy_hcl
   policy_hcl=$(cat <<EOF
path "${data_path}" {
  capabilities = ["read"]
}
path "${metadata_path}" {
  capabilities = ["read", "list"]
}
EOF
)

   _VAULT_PARENT_POLICY_HCL=""
   _vault_build_parent_metadata_policy "$mount_trim" "$secret_trim" "$metadata_path"
   policy_hcl+="$_VAULT_PARENT_POLICY_HCL"

   if ! printf '%s\n' "$policy_hcl" | _no_trace _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- vault policy write "$policy" -; then
      _err "[vault] failed to write policy ${policy}"
   fi
   _info "[vault] ensured policy ${policy} for ${data_path}"
}

function _is_vault_pki_mounted() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}" path="${3:-pki}"
   _vault_exec --no-exit "$ns" "vault secrets list -format=json" "$release" |
      jq -e --arg PATH "${path}/" 'has($PATH) and .[$PATH].type == "pki"' >/dev/null 2>&1
}

function _vault_enable_pki() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local path="${3:-${VAULT_PKI_PATH:-pki}}"

   if ! _is_vault_pki_mounted "$ns" "$release" "$path"; then
      _vault_login "$ns" "$release"
      _vault_exec "$ns" "vault secrets enable -path=$path pki" "$release" || \
         _err "[vault] failed to enable pki at $path"
   fi

   _vault_exec "$ns" \
      "vault secrets tune -max-lease-ttl=${VAULT_PKI_MAX_TTL:-87600h} $path" "$release"
}

function _vault_pki_config_urls() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local path="${3:-${VAULT_PKI_PATH:-pki}}"
   local host="${release}.${ns}.svc"
   local base="http://${host}:8200"

   _vault_exec "$ns" \
      "vault write $path/config/urls \
        issuing_certificates=\"${base}/v1/${path}/ca\" \
        crl_distribution_points=\"${base}/v1/${path}/crl\"" "$release" || \
        _err "[vault] failed to configure pki URLs"
}

function _vault_ensure_pki_root_ca() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local path="${3:-${VAULT_PKI_PATH:-pki}}"
   local cn="${4:-${VAULT_PKI_CN:-dev.k3d.internal}}" ttl="${5:-${VAULT_PKI_MAX_TTL:-87600h}}"

   if _vault_exec --no-exit "$ns" "vault read -format=json $path/cert/ca" "$release" >/dev/null 2>&1; then
      _info "[vault] root CA already exists at $path, skipping creation"
      return 0
   fi

   _vault_exec "$ns" \
      "vault write -format=json $path/root/generate/internal \
        common_name=\"$cn\" ttl=\"$ttl\"" "$release" >/dev/null 2>&1 || \
        _err "[vault] failed to create root CA at $path"
}

function _vault_upsert_pki_role() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local path="${3:-${VAULT_PKI_PATH:-pki}}"
   local role="${4:-${VAULT_PKI_ROLE:-jenkins-tls}}"
   local ttl="${5:-${VAULT_PKI_ROLE_TTL:-720h}}"
   local allowed="${6:-${VAULT_PKI_ALLOWED:-}}"
   local enforce_hostnames="${7:-${VAULT_PKI_ENFORCE_HOSTNAMES:-true}}"

   local args=()
   if [[ -n "$allowed" ]]; then
      args+=("allowed_domains=${allowed}")
      [[ "$allowed" == *","* ]] || [[ "$allowed" == *"*"* ]] || args+=("allow_subdomains=true")
   else
      args+=("allow_any_name=true")
   fi
   args+=("enforce_hostnames=${enforce_hostnames}")
   args+=("max_ttl=${ttl}")

   _vault_exec "$ns" \
      "vault write $path/roles/$role ${args[*]}" "$release" || \
      _err "[vault] failed to create/update role $role at $path"
}

function _vault_post_revoke_request() {
   local method="$1" path="$2" payload="$3" ns="$4" release="$5"

   if [[ "$method" != "POST" ]]; then
      return 1
   fi

   local serial=$(printf '%s' "$payload" | jq -r '.serial_number // empty')
   if [[ -z "$serial" ]]; then
      _err "[vault] missing serial_number in payload"
   fi

   local mount="${path%/revoke}" serial_plain="${serial//:/}"
   if ! _vault_exec --no-exit "$ns" "vault read -format=json ${mount}/cert/${serial_plain}" >/dev/null 2>&1; then
      _warn "[vault] certificate with serial_number $serial not found at $mount/cert/"
      return 0
   fi

   if ! _vault_exec "$ns" "VAULT_HTTP_DEBUG=\${VAULT_HTTP_DEBUG:-1} vault write ${path} serial_number=${serial}" "$release"; then
      _warn "[vault] failed to revoke certificate with serial_number $serial at ${path}"
      return 1
   fi

   return 0
}

function _vault_issue_pki_tls_secret() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local path="${3:-${VAULT_PKI_PATH:-pki}}"
   local role="${4:-${VAULT_PKI_ROLE:-jenkins-tls}}"
   local host="${5:-${VAULT_PKI_LEAF_HOST:-jenkins.dev.k3d.internal}}"
   local secret_ns="${6:-${VAULT_PKI_SECRET_NS:-istio-system}}"
   local secret_name="${7:-${VAULT_PKI_SECRET_NAME:-jenkins-tls}}"

   local existing_serial="" existing_cert_file=""
   local secret_json cert_b64
   if secret_json=$(_kubectl -n "$secret_ns" get secret "$secret_name" -o json 2>/dev/null); then
      cert_b64=$(printf '%s' "$secret_json" | jq -r '.data["tls.crt"] // empty')
      if [[ -n "$cert_b64" ]]; then
         existing_cert_file=$(mktemp -t vault-existing-cert.XXXXXX)
         trap '$(_cleanup_trap_command "$existing_cert_file")' EXIT TERM
         if printf '%s' "$cert_b64" | base64 -d >"$existing_cert_file" 2>/dev/null; then
            if ! existing_serial=$(_vault_pki_extract_certificate_serial "$existing_cert_file"); then
               existing_serial=""
            fi
         else
            existing_cert_file=""
         fi
      fi
   fi

   local json="$(_vault_exec "$ns" "vault write -format=json ${path}/issue/${role} common_name=\"${host}\" alt_names=\"${host}\" ttl=\"${VAULT_PKI_ROLE_TTL:-720h}\"" "$release")"

   # Extract leaf cert, key, and CA chain
   local cert=$(printf '%s' "$json" | jq -r '.data.certificate')
   local key=$(printf '%s' "$json" | jq -r '.data.private_key')
   local ca=$(printf '%s' "$json" | jq -r '.data.issuing_ca')

   if [[ -z "$cert" || -z "$key" || -z "$ca" ]]; then
      _err "[vault] failed to issue certificate from role $role at $path"
   fi

   local manifest
   manifest="$(mktemp -t vault-pki-secret.XXXXXX)"
   trap '$(_cleanup_trap_command "$manifest" "$existing_cert_file")' EXIT TERM

   {
      printf 'apiVersion: v1\n'
      printf 'kind: Secret\n'
      printf 'metadata:\n'
      printf '  name: %s\n' "$secret_name"
      printf '  namespace: %s\n' "$secret_ns"
      printf 'type: kubernetes.io/tls\n'
      printf 'stringData:\n'
      printf '  tls.crt: |\n'
      printf '%s\n' "$cert" | sed 's/^/    /'
      printf '  tls.key: |\n'
      printf '%s\n' "$key" | sed 's/^/    /'
      printf '  ca.crt: |\n'
      printf '%s\n' "$ca" | sed 's/^/    /'
   } >"$manifest"

   _kubectl apply -f "$manifest" || \
      _err "[vault] failed to apply TLS secret manifest ${secret_ns}/${secret_name}"

   _cleanup_on_success "$manifest"
   if [[ -n "$existing_cert_file" ]]; then
      _cleanup_on_success "$existing_cert_file"
   fi
   trap - EXIT TERM

   if [[ -n "$existing_serial" ]]; then
      if ! _vault_pki_revoke_certificate_serial "$existing_serial" "$path" _vault_post_revoke_request "$ns" "$release"; then
         _warn "[vault] failed to revoke previous certificate serial $existing_serial"
      fi
   fi
}

# Verifies PKI mount and role exist; call _err to exit on failure.
function _is_vault_pki_ready() {
  local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
  local path="${3:-${VAULT_PKI_PATH:-pki}}" role="${4:-${VAULT_PKI_ROLE:-jenkins-tls}}"

  # mount present?
  _vault_exec "$ns" "vault secrets list -format=json" "$release" \
    | jq -e --arg p "${path}/" 'has($p)' >/dev/null 2>&1 \
    || _err "[vault] PKI mount '${path}/' not found (ns=${ns}, release=${release})"

  # role present?
  _vault_exec "$ns" "vault list -format=json ${path}/roles" "$release" \
    | jq -e --arg r "$role" '.[] | select(. == $r)' >/dev/null 2>&1 \
    || _err "[vault] PKI role '${role}' not found at ${path}/roles"
}
function _vault_setup_pki() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local path="${3:-${VAULT_PKI_PATH:-pki}}"
   local ca_cn="${4:-${VAULT_PKI_CN:-dev.k3d.internal}}"
   local allowd="${5:-${VAULT_PKI_ALLOWED:-}}"
   local role_ttl="${6:-${VAULT_PKI_ROLE_TTL:-720h}}"
   local role="${7:-${VAULT_PKI_ROLE:-jenkins-tls}}"

   if [[ "${VAULT_ENABLE_PKI:-0}" != 1 ]]; then
      _info "[vault] PKI setup disabled (VAULT_ENABLE_PKI=0), skipping"
      return 0
   fi

   _vault_enable_pki "$ns" "$release" "$path"
   _vault_pki_config_urls "$ns" "$release" "$path"
   _vault_ensure_pki_root_ca "$ns" "$release" "$path" "$ca_cn" "$VAULT_PKI_MAX_TTL"
   _vault_upsert_pki_role "$ns" "$release" "$path" "$role" "$role_ttl" "$allowd"

}

function _vault_pki_issue_tls_secret() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local path="${3:-${VAULT_PKI_PATH:-pki}}"
   local role="${4:-${VAULT_PKI_ROLE:-jenkins-tls}}"
   local host="${5:-${VAULT_PKI_LEAF_HOST:-jenkins.dev.k3d.internal}}"
   local secret_ns="${6:-${VAULT_PKI_SECRET_NS:-istio-system}}"
   local secret_name="${7:-${VAULT_PKI_SECRET_NAME:-jenkins-tls}}"

   if [[ "${VAULT_PKI_ISSUE_SECRET:-0}" -eq 0 ]]; then
      _info "[vault] PKI issue secret disabled (VAULT_PKI_ISSUE_SECRET=0), skipping"
      return 0
   fi

   _is_vault_pki_ready "$ns" "$release" "$path"

   _vault_issue_pki_tls_secret "$ns" "$release" "$path" "$role" \
      "$host" "$secret_ns" "$secret_name"

   _info "[vault] PKI setup complete (path=$path, role=$role)"
}
