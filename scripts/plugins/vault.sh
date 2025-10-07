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

_ensure_jq

VAULT_PKI_HELPERS="$SCRIPT_DIR/lib/vault_pki.sh"
if [[ -f "$VAULT_PKI_HELPERS" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_PKI_HELPERS"
else
   _warn "[vault] missing optional helper file: $VAULT_PKI_LIB" >&2
fi

: "${VAULT_TLS_SECRET_TEMPLATE:=${SCRIPT_DIR}/etc/vault/jenkins-tls-secret.yaml.tmpl}"

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
reclaimPolicy: Reclaim
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
   local enable_injector="false"
   case "${VAULT_ENABLE_INJECTOR:-false}" in
      1|true|TRUE|True|yes|YES)
         enable_injector="true"
         ;;
   esac

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
  enabled: ${enable_injector}
  metrics:
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

function _vault_has_injector() {
   local ns="${1:-$VAULT_NS_DEFAULT}"
   _kubectl --no-exit -n "$ns" get deploy/vault-agent-injector >/dev/null 2>&1
}

function _ensure_vault_agent_injector() {
   local ns="${1:-$VAULT_NS_DEFAULT}"
   local release="${2:-$VAULT_RELEASE_DEFAULT}"
   local enable="${3:-1}"

   case "$enable" in
      1|true|TRUE|True|yes|YES)
         ;;
      *)
         return 0
         ;;
   esac

   if _vault_has_injector "$ns" "$release"; then
      return 0
   fi

   _vault_repo_setup

   local version="${VAULT_CHART_VERSION:-}"
   local -a args=(upgrade --install "$release" hashicorp/vault -n "$ns" --reuse-values --wait \
                  --set injector.enabled=true --set injector.metrics.enabled=false)
   [[ -n "$version" ]] && args+=(--version "$version")

   _helm "${args[@]}"

   if ! _kubectl --no-exit -n "$ns" rollout status deployment/vault-agent-injector --timeout=180s >/dev/null 2>&1; then
      _err "[vault] vault-agent-injector failed to reach Ready state"
   fi
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
   _ensure_vault_agent_injector "$ns" "$release" "${VAULT_ENABLE_INJECTOR:-false}"

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
  local status_json=$(_kubectl --no-exit -n "$ns" exec -i "$leader" -- \
     vault status -format json 2>/dev/null || true)
  local vault_sealed=$(printf '%s' "$status_json" | jq -r '.sealed')

  if [[ "$vault_init" == "true" ]]; then
     if [[ "$vault_sealed" == "true" ]]; then
        local unseal_key=""
        if _kubectl --no-exit -n "$ns" get secret vault-root >/dev/null 2>&1; then
           unseal_key=$(_kubectl --no-exit -n "$ns" get secret vault-root -o jsonpath='{.data.unseal_key}' 2>/dev/null || true)
        fi

        if [[ -z "$unseal_key" ]]; then
           _err "[vault] vault-root secret missing unseal_key in namespace '$ns'"
        fi

        if [[ -n "$unseal_key" ]]; then
           for pod in $(_kubectl -n "$ns" get pod -o name); do
              pod="${pod#pod/}"
              printf '%s' "$unseal_key" | base64 -d | _kubectl -n "$ns" exec -i "$pod" -- \
                 sh -lc "vault operator unseal /dev/stdin" >/dev/null 2>&1
              _info "[vault] unsealed $pod"
           done
        fi
     else
        _warn "[vault] already initialized, skipping init"
     fi
     return 0
  fi

  _kubectl -n "$ns" exec -it "$leader" -- \
     sh -lc 'vault operator init -key-shares=1 -key-threshold=1 -format=json' \
     > "$jsonfile"

  local root_token=$(jq -r '.root_token' "$jsonfile")
  local unseal_key=$(jq -r '.unseal_keys_b64[0]' "$jsonfile")

  local secret_manifest="$(mktemp -t vault-root-secret.XXXXXX.yaml)"
  trap '$(_cleanup_trap_command "$secret_manifest")' RETURN

  _no_trace cat >"$secret_manifest" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-root
  namespace: ${ns}
type: Opaque
stringData:
  root_token: ${root_token}
  unseal_key: ${unseal_key}
EOF

  _no_trace _kubectl -n "$ns" apply -f "$secret_manifest"

  # unseal all pods
  for pod in $(_kubectl --no-exit -n "$ns" get pod -l "app.kubernetes.io/name=vault,app.kubernetes.io/instance=${release}" -o name); do
     pod="${pod#pod/}"
     _no_trace _kubectl -n "$ns" exec -i "$pod" -- \
        sh -lc "vault operator unseal $unseal_key" >/dev/null 2>&1
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

  local kflags=() quiet=0
  while [[ "${1:-}" == "--no-exit" ]]  || \
     [[ "${1:-}" == "--prefer-sudo" ]] || \
     [[ "${1:-}" == "--require-sudo" ]] || \
     [[ "${1:-}" == "--quiet" ]]; do
     case "$1" in
        --quiet)
           quiet=1
           ;;
        *)
           kflags+=("$1")
           ;;
     esac
     shift
  done

  local ns="${1:-$VAULT_NS_DEFAULT}" cmd="${2:-sh}" release="${3:-$VAULT_RELEASE_DEFAULT}"
  local pod="${release}-0"
  local -a kubectl_args=("${kflags[@]}")
  (( quiet )) && kubectl_args+=(--quiet)

  # this long pipe to check policy exist seems to be complicated but is to
  # prevent vault login output to leak to user and hide sensitive info from being
  # shown in the xtrace when that is turned on
  _kubectl "${kubectl_args[@]}" -n "$ns" exec -i "$pod" -- sh -lc "$cmd"
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
   local root_b64 root_token
   root_b64=$(_kubectl --no-exit -n "$ns" get secret vault-root -o jsonpath='{.data.root_token}' 2>/dev/null || true)
   if [[ -z "$root_b64" ]]; then
      _err "[vault] vault-root secret not found in namespace '$ns'"
   fi

   root_token=$(printf '%s' "$root_b64" | base64 -d)
   if [[ -z "$root_token" ]]; then
      _err "[vault] vault root token is empty"
   fi

   local revoke_cmd revoke_out revoke_force_path revoke_force_cmd revoke_force_out
   revoke_cmd=$(printf 'VAULT_HTTP_DEBUG=${VAULT_HTTP_DEBUG:-1} VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=%q vault write %s serial_number=%q' "$root_token" "$path" "$serial")
   if ! revoke_out=$(_vault_exec --no-exit --quiet "$ns" "$revoke_cmd" "$release" 2>&1); then
      if [[ "$revoke_out" == *"not found"* ]]; then
         local revoke_force_path="${mount}/revoke-force"
         local revoke_force_cmd
         revoke_force_cmd=$(printf 'VAULT_HTTP_DEBUG=${VAULT_HTTP_DEBUG:-1} VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=%q vault write %s serial_number=%q' "$root_token" "$revoke_force_path" "$serial")
         if ! revoke_force_out=$(_vault_exec --no-exit --quiet "$ns" "$revoke_force_cmd" "$release" 2>&1); then
            _warn "[vault] failed to revoke certificate serial $serial via revoke-force: ${revoke_force_out:-<no output>}"
            return 1
         fi
         _info "[vault] serial $serial not found at ${mount}/cert, used revoke-force"
         return 0
      fi
      _warn "[vault] failed to revoke certificate serial $serial: ${revoke_out:-<no output>}"
      return 1
   fi
}

function _vault_issue_pki_tls_secret() {
   local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}"
   local path="${3:-${VAULT_PKI_PATH:-pki}}"
   local role="${4:-${VAULT_PKI_ROLE:-jenkins-tls}}"
   local host="${5:-${VAULT_PKI_LEAF_HOST:-jenkins.dev.k3d.internal}}"
   local secret_ns="${6:-${VAULT_PKI_SECRET_NS:-istio-system}}"
   local secret_name="${7:-${VAULT_PKI_SECRET_NAME:-jenkins-tls}}"

   local traced=0
   manifest="$(mktemp -t vault-pki-secret.XXXXXX.yaml)"
   trap '$(_cleanup_trap_command "$manifest")' EXIT TERM

   if [[ $- == *x* ]]; then
      traced=1
      set +x
   fi

   local existing_serial="" existing_cert_file="" secret_json_file=""
   secret_json_file="$(mktemp -t vault-existing-secret.XXXXXX.json)"
   if _kubectl -n "$secret_ns" get secret "$secret_name" -o json >"$secret_json_file" 2>/dev/null; then
      local cert_b64
      cert_b64=$(jq -r '.data["tls.crt"] // empty' <"$secret_json_file")
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

   local json
   json=$(_vault_exec "$ns" "vault write -format=json ${path}/issue/${role} common_name=\"${host}\" alt_names=\"${host}\" ttl=\"${VAULT_PKI_ROLE_TTL:-720h}\"" "$release")

   # Extract leaf cert, key, and CA chain
   local cert key ca
   cert=$(jq -r '.data.certificate' <<<"$json")
   key=$(jq -r '.data.private_key' <<<"$json")
   ca=$(jq -r '.data.issuing_ca' <<<"$json")

   if [[ -z "$cert" || -z "$key" || -z "$ca" ]]; then
      _err "[vault] failed to issue certificate from role $role at $path"
   fi

   local prev_secret_ns_set prev_secret_name_set prev_cert_set prev_key_set prev_ca_set
   prev_secret_ns_set=$([[ -n "${VAULT_TLS_SECRET_NS+x}" ]] && echo 1 || echo 0)
   prev_secret_name_set=$([[ -n "${VAULT_TLS_SECRET_NAME+x}" ]] && echo 1 || echo 0)
   prev_cert_set=$([[ -n "${VAULT_TLS_CERT+x}" ]] && echo 1 || echo 0)
   prev_key_set=$([[ -n "${VAULT_TLS_KEY+x}" ]] && echo 1 || echo 0)
   prev_ca_set=$([[ -n "${VAULT_TLS_CA+x}" ]] && echo 1 || echo 0)

   local prev_secret_ns prev_secret_name prev_cert prev_key prev_ca
   prev_secret_ns="${VAULT_TLS_SECRET_NS:-}"
   prev_secret_name="${VAULT_TLS_SECRET_NAME:-}"
   prev_cert="${VAULT_TLS_CERT:-}"
   prev_key="${VAULT_TLS_KEY:-}"
   prev_ca="${VAULT_TLS_CA:-}"

   export VAULT_TLS_SECRET_NS="$secret_ns"
   export VAULT_TLS_SECRET_NAME="$secret_name"
   export VAULT_TLS_CERT="$(printf '%s\n' "$cert" | sed 's/^/    /')"
   export VAULT_TLS_KEY="$(printf '%s\n' "$key" | sed 's/^/    /')"
   export VAULT_TLS_CA="$(printf '%s\n' "$ca" | sed 's/^/    /')"

   umask 077
   envsubst < "${VAULT_TLS_SECRET_TEMPLATE}" >"$manifest"

   _kubectl apply -f "$manifest" || \
      _err "[vault] failed to apply TLS secret manifest ${secret_ns}/${secret_name}"

   _cleanup_on_success "$manifest"
   _cleanup_on_success "$secret_json_file"
   if [[ -n "$existing_cert_file" ]]; then
      _cleanup_on_success "$existing_cert_file"
   fi

   if (( prev_secret_ns_set )); then
      export VAULT_TLS_SECRET_NS="$prev_secret_ns"
   else
      unset VAULT_TLS_SECRET_NS
   fi

   if (( prev_secret_name_set )); then
      export VAULT_TLS_SECRET_NAME="$prev_secret_name"
   else
      unset VAULT_TLS_SECRET_NAME
   fi

   if (( prev_cert_set )); then
      export VAULT_TLS_CERT="$prev_cert"
   else
      unset VAULT_TLS_CERT
   fi

   if (( prev_key_set )); then
      export VAULT_TLS_KEY="$prev_key"
   else
      unset VAULT_TLS_KEY
   fi

   if (( prev_ca_set )); then
      export VAULT_TLS_CA="$prev_ca"
   else
      unset VAULT_TLS_CA
   fi

   if (( traced )); then
      set -x
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
