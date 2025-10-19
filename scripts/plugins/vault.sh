#!/usr/bin/env bash
# k3d-manager :: HashiCorp Vault helpers (ESO-friendly)
# Style: uses command / _kubectl / _helm, no set -e, minimal locals.

# Defaults (override via env or args to the top-levels)
VAULT_NS_DEFAULT="${VAULT_NS_DEFAULT:-vault}"
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

function cache_vault_unseal_keys() {
   local cluster_ns="${VAULT_NS_DEFAULT:-vault}"
   local cluster_release="${VAULT_RELEASE_DEFAULT:-vault}"
   local service="k3d-manager-vault-unseal"
   local type="vault-unseal"
   local -a keys=()

   while [[ $# -gt 0 ]]; do
      case "$1" in
         -h|--help)
            cat <<EOF
Usage: cache_vault_unseal_keys [--namespace <ns>] [--release <name>] [--cluster <ns/release>] [key1 key2 ...]

Provide unseal keys as arguments (in order) or via stdin (one key per line).
Defaults: namespace=${cluster_ns}, release=${cluster_release}
EOF
            return 0
            ;;
         --namespace)
            if [[ -z "${2:-}" ]]; then
               _err "[vault] --namespace flag requires an argument"
            fi
            cluster_ns="$2"
            shift 2
            continue
            ;;
         --namespace=*)
            cluster_ns="${1#*=}"
            if [[ -z "$cluster_ns" ]]; then
               _err "[vault] --namespace flag requires a non-empty argument"
            fi
            shift
            continue
            ;;
         --release)
            if [[ -z "${2:-}" ]]; then
               _err "[vault] --release flag requires an argument"
            fi
            cluster_release="$2"
            shift 2
            continue
            ;;
         --release=*)
            cluster_release="${1#*=}"
            if [[ -z "$cluster_release" ]]; then
               _err "[vault] --release flag requires a non-empty argument"
            fi
            shift
            continue
            ;;
         --cluster)
            if [[ -z "${2:-}" ]]; then
               _err "[vault] --cluster flag requires an argument"
            fi
            local cluster_arg="$2"
            shift 2
            if [[ "$cluster_arg" == */* ]]; then
               cluster_ns="${cluster_arg%%/*}"
               cluster_release="${cluster_arg##*/}"
            else
               cluster_release="$cluster_arg"
            fi
            continue
            ;;
         --cluster=*)
            local cluster_arg="${1#*=}"
            shift
            if [[ "$cluster_arg" == */* ]]; then
               cluster_ns="${cluster_arg%%/*}"
               cluster_release="${cluster_arg##*/}"
            else
               cluster_release="$cluster_arg"
            fi
            continue
            ;;
         --)
            shift
            break
            ;;
         -*)
            _err "[vault] unknown option: $1"
            ;;
         *)
            keys+=("$1")
            shift
            continue
            ;;
      esac
   done

   while [[ $# -gt 0 ]]; do
      keys+=("$1")
      shift
   done

   if (( ${#keys[@]} == 0 )) && [[ ! -t 0 ]]; then
      local line
      while IFS= read -r line; do
         line=${line%$'\r'}
         [[ -z "$line" ]] && continue
         keys+=("$line")
      done
   fi

   if (( ${#keys[@]} == 0 )); then
      _err "[vault] provide unseal keys via arguments or stdin"
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

   local count=${#keys[@]}
   local idx
   for (( idx=0; idx<count; idx++ )); do
      local shard="${keys[$idx]}"
      shard=${shard%$'\r'}
      if [[ -z "$shard" ]]; then
         _err "[vault] unseal shard $((idx+1)) is empty"
      fi
      local shard_key="${cluster}:shard$((idx+1))"
      _secret_store_data "$service" "$shard_key" "$shard" "Vault unseal shard $((idx+1))" "$type" || \
         _err "[vault] unable to store unseal shard $((idx+1))"
   done

   _secret_store_data "$service" "${cluster}:count" "$count" "Vault unseal shard count" "$type" || \
      _err "[vault] unable to persist unseal shard count"

   _info "[vault] cached ${count} unseal shard(s) for cluster ${cluster}"
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

function _deploy_vault_ha() {
   local ns="${1:-$VAULT_NS_DEFAULT}"
   local release="${2:-$VAULT_RELEASE_DEFAULT}"
   local f="$(mktemp -t vault-ha-vaules.XXXXXX.yaml)"

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
   args=(upgrade --install "$release" hashicorp/vault -n "$ns" -f "$f")
   [[ -n "$version" ]] && args+=("--version" "$version")
   _helm "${args[@]}"
   trap '$(_cleanup_trap_command "$f")' EXIT TERM
}

function deploy_vault() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      echo "Usage: deploy_vault <dev|ha> [namespace=${VAULT_NS_DEFAULT}] [release=${VAULT_RELEASE_DEFAULT}] [chart-version=${VAULT_CHART_VERSION}]"
      return 0
   fi

   VAULT_VARS="$SCRIPT_DIR/etc/vault/vars.sh"
   if [[ -f "$VAULT_VARS" ]]; then
      # shellcheck disable=SC1090
      source "$VAULT_VARS"
   else
      _warn "[vault] missing optional config file: $VAULT_VARS"
   fi

   local mode="${1:-}"
   local ns="${2:-$VAULT_NS_DEFAULT}"
   local release="${3:-$VAULT_RELEASE_DEFAULT}"
   local version="${4:-$VAULT_CHART_VERSION}"  # optional

   if [[ "$mode" != "dev" && "$mode" != "ha" ]]; then
      echo "[vault] usage: deploy_vault <dev|ha> [<ns> [<release> [<chart-version>]]]" >&2
      return 1
   fi

   deploy_eso

   _vault_ns_ensure "$ns"
   _vault_repo_setup

   _deploy_vault_ha "$ns" "$release"

   _vault_bootstrap_ha "$ns" "$release"
   _enable_kv2_k8s_auth "$ns" "$release"
   _vault_setup_pki "$ns" "$release"
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

function _vault_bootstrap_ha() {
  local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
  local leader="${release}-0"
  if ! _is_vault_deployed "$ns" "$release"; then
      _err "[vault] not deployed in ns=$ns release=$release" >&2
  fi

  if  _run_command --no-exit -- \
     kubectl --no-exit exec -n "$ns" -it "$leader" -- vault status >/dev/null 2>&1; then
      echo "[vault] already initialized"
      return 0
  fi

  # check if vault sealed or not
  if _run_command --no-exit -- \
     kubectl exec -n "$ns" -it "$leader" -- vault status 2>&1 | grep -q 'unseal'; then
      _warn "[vault] already initialized (sealed), skipping init"
      return 0
  fi

  local jsonfile="$(mktemp -t vault-init.XXXXXX.json)";
  trap '$(_cleanup_trap_command "$jsonfile")' EXIT TERM
  _kubectl wait -n "$ns" --for=condition=PodScheduled pod/"$leader" --timeout=120s
  local vault_state=$(_kubectl --no-exit -n "$ns" get pod "$leader" -o jsonpath='{.status.phase}')
  end_time=$((SECONDS + 120))
  current_time=$SECONDS
  while [[ "$vault_state" != "Running" ]]; do
      echo "[vault] waiting for $leader to be Running (current=$vault_state)"
      sleep 2
      vault_state=$(_kubectl --no-exit -n "$ns" get pod "$leader" -o jsonpath='{.status.phase}')
      if (( current_time >= end_time )); then
         _err "[vault] timeout waiting for $leader to be Running (current=$vault_state)"
      fi
  done
  local vault_init=$(_kubectl --no-exit -n "$ns" exec -i "$leader" -- vault status -format json | jq -r '.initialized')
  if [[ "$vault_init" == "true" ]]; then
     _warn "[vault] already initialized, skipping init"
     return 0
  fi
  _kubectl -n "$ns" exec -it "$leader" -- \
     sh -lc 'vault operator init -key-shares=1 -key-threshold=1 -format=json' \
     > "$jsonfile"

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

  if [[ ! "$key_shares" =~ ^[0-9]+$ || key_shares -le 0 ]]; then
     key_shares=${#unseal_keys[@]}
  fi
  if [[ ! "$key_threshold" =~ ^[0-9]+$ || key_threshold -le 0 ]]; then
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

  local i shard
  # unseal all pods
  for pod in $(_kubectl --no-exit -n "$ns" get pod -l "app.kubernetes.io/name=vault,app.kubernetes.io/instance=${release}" -o name); do
     pod="${pod#pod/}"
     for (( i=0; i<threshold; i++ )); do
        shard="${unseal_keys[$i]}"
        _no_trace _kubectl -n "$ns" exec -i "$pod" -- \
           sh -lc "vault operator unseal $shard" >/dev/null 2>&1
     done
     _info "[vault] unsealed $pod"
  done

  if ! _is_vault_health "$ns" "$release" ; then
     _err "[vault] vault not healthy after init/unseal"
  else
     _info "[vault] vault is ready to serve"
     _vault_portforward_help "$ns" "$release"
  fi
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

  # this long pipe to check policy exist seems to be complicated but is to
  # prevent vault login output to leak to user and hide sensitive info from being
  # shown in the xtrace when that is turned on
  _kubectl "${kflags[@]}" -n "$ns" exec -i "$pod" -- sh -lc "$cmd"
}

function _vault_login() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local pod="${release}-0"

   _kubectl --no-exit -n "$ns" get secret vault-root -o jsonpath='{.data.root_token}' | \
      base64 -d | \
     _kubectl --no-exit -n "$ns" exec -i "$pod" -- \
     sh -lc "vault login - >/dev/null 2>&1"
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
  local eso_ns="${4:-external-secrets}"

  _vault_set_eso_reader "$ns" "$release" "$eso_sa" "$eso_ns"
  _vault_set_eso_writer "$ns" "$release" "$eso_sa" "$eso_ns"
  _vault_set_eso_init_jenkins_writer "$ns" "$release" "$eso_sa" "$eso_ns"
}

function _vault_set_eso_reader() {
  local ns="${1:-$VAULT_NS_DEFAULT}"
  local release="${2:-$VAULT_RELEASE_DEFAULT}"
  local eso_sa="${3:-external-secrets}"
  local eso_ns="${4:-external-secrets}"
  local pod="${release}-0"

  if _vault_policy_exists "$ns" "$release" "eso-reader"; then
     _info "[vault] policy 'eso-reader' already exists, skipping k8s auth setup"
     return 0
  fi

  _vault_login "$ns" "$release"
  # kubernetes auth so no token stored in k8s
  cat <<'SH' | _no_trace _kubectl -n "$ns" exec -i "$pod" -- \
    sh -
set -e
vault secrets enable -path=secret kv-v2 || true
vault auth enable kubernetes || true

vault write auth/kubernetes/config \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
SH

  # create a policy -- eso-reader
  cat <<'HCL' | _kubectl -n "$ns" exec -i "$pod" -- \
    vault policy write eso-reader -
     # file: eso-reader.hcl
     # read any keys under eso/*
     path "secret/data/eso/*"      { capabilities = ["read"] }
     path "secret/metadata/eso"    { capabilities = ["list"] }
     path "secret/metadata/eso/*"  { capabilities = ["read","list"] }

HCL

  # map ESO service account to the policy
  _kubectl -n "$ns" exec -i "$pod" -- \
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
  local eso_ns="${4:-external-secrets}"
  local pod="${release}-0"

  if _vault_policy_exists "$ns" "$release" "eso-writer"; then
     _info "[vault] policy 'eso-writer' already exists, skipping k8s auth setup"
     return 0
  fi

  # create a policy -- eso-writer
  cat <<'HCL' | _kubectl -n "$ns" exec -i "$pod" -- sh - \
    vault policy write eso-writer
     # file: eso-writer.hcl
     path "secret/data/eso/*"      { capabilities = ["create","update","read"] }
     path "secret/metadata/eso"    { capabilities = ["list"] }
     path "secret/metadata/eso/*"  { capabilities = ["read","list"] }
HCL

  # map ESO service account to the policy
  _kubectl -n "$ns" exec -i "$pod" -- \
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
  local eso_ns="${4:-external-secrets}"
  local pod="${release}-0"

  if _vault_policy_exists "$ns" "$release" "eso-init-jenkins-writer"; then
     _info "[vault] policy 'eso-writer' already exists, skipping k8s auth setup"
     return 0
  fi

  # create a policy -- eso-writer
  _vault_login "$ns" "$release"
  cat <<'HCL' | _no_trace _kubectl -n "$ns" exec -i "$pod" -- \
    vault policy write eso-init-jenkins-writer -
     # file: eso-writer.hcl
     path "secret/data/eso/jenkins-admin"     { capabilities = ["create","update","read"] }
     path "secret/metadata/eso/jenkins-admin" { capabilities = ["read","list"] }

HCL

  # map ESO service account to the policy
  _kubectl -n "$ns" exec -i "$pod" -- \
    vault write auth/kubernetes/role/eso-writer \
      bound_service_account_names="$eso_sa" \
      bound_service_account_namespaces="$eso_ns" \
      policies=eso-writer \
      ttl=15m
}

function _vault_configure_secret_reader_role() {
  local ns="${1:-$VAULT_NS_DEFAULT}"
  local release="${2:-$VAULT_RELEASE_DEFAULT}"
  local service_account="${3:-external-secrets}"
  local service_namespace="${4:-external-secrets}"
  local mount="${5:-secret}"
  local secret_prefix="${6:-ldap}"
  local role="${7:-eso-ldap-directory}"
  local policy="${8:-${role}}"
  local pod="${release}-0"

  if [[ -z "$secret_prefix" ]]; then
     _err "[vault] secret prefix required for role configuration"
  fi

  _vault_login "$ns" "$release"

  local mount_path="${mount%/}"
  local mount_json=""
  mount_json=$(_vault_exec --no-exit "$ns" "vault secrets list -format=json" "$release" 2>/dev/null || true)
  if [[ -z "$mount_json" ]] || ! printf '%s' "$mount_json" | jq -e --arg PATH "${mount_path}/" 'has($PATH)' >/dev/null 2>&1; then
     _vault_exec "$ns" "vault secrets enable -path=${mount_path} kv-v2" "$release" || \
        _err "[vault] failed to enable kv engine at ${mount_path}"
  fi

  local auth_json=""
  auth_json=$(_vault_exec --no-exit "$ns" "vault auth list -format=json" "$release" 2>/dev/null || true)
  if [[ -z "$auth_json" ]] || ! printf '%s' "$auth_json" | jq -e --arg PATH "kubernetes/" 'has($PATH)' >/dev/null 2>&1; then
     _vault_exec "$ns" "vault auth enable kubernetes" "$release" || \
        _err "[vault] failed to enable kubernetes auth method"
  fi

  cat <<'SH' | _no_trace _kubectl -n "$ns" exec -i "$pod" -- sh -
set -e
vault write auth/kubernetes/config \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
SH

  local prefix_trimmed="${secret_prefix#/}"
  prefix_trimmed="${prefix_trimmed%/}"

  local policy_hcl

  printf -v policy_hcl '%s\n' \
    "path \"${mount_path}/data/${prefix_trimmed}\"       { capabilities = [\"read\"] }" \
    "path \"${mount_path}/data/${prefix_trimmed}/*\"     { capabilities = [\"read\"] }" \
    "path \"${mount_path}/metadata/${prefix_trimmed}\"   { capabilities = [\"read\", \"list\"] }" \
    "path \"${mount_path}/metadata/${prefix_trimmed}/*\" { capabilities = [\"read\", \"list\"] }"

  local parent_prefix="${prefix_trimmed%/*}"
  while [[ -n "$parent_prefix" && "$parent_prefix" != "$prefix_trimmed" ]]; do
    policy_hcl=$(printf '%s\npath "%s/metadata/%s"   { capabilities = ["read", "list"] }\npath "%s/metadata/%s/*" { capabilities = ["read", "list"] }\n' \
      "$policy_hcl" "$mount_path" "$parent_prefix" "$mount_path" "$parent_prefix")

    local next_parent="${parent_prefix%/*}"
    if [[ "$next_parent" == "$parent_prefix" ]]; then
      break
    fi
    parent_prefix="$next_parent"
  done

  printf '%s\n' "$policy_hcl" | _no_trace _kubectl -n "$ns" exec -i "$pod" -- \
    vault policy write "${policy}" -

  local token_audience="${K8S_TOKEN_AUDIENCE:-https://kubernetes.default.svc.cluster.local}"
  local role_cmd=""
  printf -v role_cmd 'vault write "auth/kubernetes/role/%s" bound_service_account_names="%s" bound_service_account_namespaces="%s" policies="%s" ttl=1h token_audiences="%s"' \
     "$role" "$service_account" "$service_namespace" "$policy" "$token_audience"

  _vault_exec "$ns" "$role_cmd" "$release"
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
   fi
   _vault_exec "$ns" "VAULT_HTTP_DEBUG=\${VAULT_HTTP_DEBUG:-1} vault write ${path} serial_number=${serial}" "$release"
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
   trap '$(_cleanup_trap_command "$manifest")' EXIT TERM

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
