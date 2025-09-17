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

function _deploy_vault_ha() {
   local ns="${1:-$VAULT_NS_DEFAULT}"
   local release="${2:-$VAULT_RELEASE_DEFAULT}"
   local f="$(mktemp -t)"

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

   args=(upgrade --install "$release" hashicorp/vault -n "$ns" -f "$f")
   [[ -n "$version" ]] && args+=("--version" "$version")
   _helm "${args[@]}"
   trap '_cleanup_on_success "$f"' EXIT TERM
}

function deploy_vault() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      echo "Usage: deploy_vault <dev|ha> [namespace=${VAULT_NS_DEFAULT}] [release=${VAULT_RELEASE_DEFAULT}] [chart-version=${VAULT_CHART_VERSION}]"
      return 0
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

  local jsonfile="$(mktemp -t)";
  trap '_cleanup_on_success "$jsonfile"' EXIT TERM
  _kubectl wait -n "$ns" --for=condition=Podscheduled pod/"$leader" --timeout=120s
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

  local root_token=$(jq -r '.root_token' "$jsonfile")
  local unseal_key=$(jq -r '.unseal_keys_b64[0]' "$jsonfile")
  _no_trace _kubectl -n "$ns" create secret generic vault-root \
     --from-literal=root_token="$root_token"
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
  local host="${release}.${ns}.svc"
  local name="vault-health-$RANDOM$RANDOM"
  local rc=$(_kubectl --no-exit -n "$ns" run "$name" --rm -i --restart=Never \
    --image=curlimages/curl:8.10.1 --command -- sh -c \
    "curl -o /dev/null -s -w '%{http_code}' '${scheme}://${host}:${port}/v1/sys/health'")

  # kubectl may emit interactive prompts and deletion messages before or after
  # the command output; grab the trailing status token for evaluation.
  rc=${rc//$'\r'/}

  local status
  status=$(printf '%s\n' "$rc" | awk 'NF { last=$NF } END { print last }')

  if [[ ! "$status" =~ ^[0-9]{3}$ ]]; then
    status=$(printf '%s\n' "$rc" | grep -Eo '[0-9]{3}' | tail -n1)
  fi

  if [[ -z "$status" ]]; then
    local status_line="${rc##*$'\n'}"
    status="$status_line"
  fi

  case "$status" in
     200|429|472|473)
        _info "return code: $status"
        return 0
        ;;
     *)
        _info "return code: $status"
        return 1
        ;;
  esac
}

function _vault_exec() {
   local ns="${1:-$VAULT_NS_DEFAULT}" cmd="${2:-sh}" release="${3:-$VAULT_RELEASE_DEFAULT}"
   local pod="${release}-0"

  # this long pipe to check policy exist seems to be complicated but is to
  # prevent vault login output to leak to user and hide sensitive info from being
  # shown in the xtrace when that is turned on
   _kubectl --no-exit -n "$ns" get secret vault-root -o jsonpath='{.data.root_token}' | \
      base64 -d | \
     _kubectl --no-exit -n "$ns" exec -i "$pod" -- \
     sh -lc "vault login - >/dev/null 2>&1 ; $cmd"
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

  if _vault_exec "$ns" "vault policy list" "$release" | grep -q "^${name}\$"; then
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
