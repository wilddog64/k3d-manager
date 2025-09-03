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

# Produce a values file path for a mode (dev|ha); echoes the filename
function _vault_values_dev() {
   local f="$(mktemp -t)"; _cleanup_register "$f"
   cat >"$f" <<'YAML'
server:
  dev:
    enabled: true
injector:
  enabled: false
csi:
  enabled: false
YAML
echo "$f"
}

function _vault_values_ha() {
   local f="$(mktemp -t)"; _cleanup_register "$f"
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
echo "$f"
}

function deploy_vault() {
   local mode="${1:-}"
   local ns="${2:-$VAULT_NS_DEFAULT}"
   local release="${3:-$VAULT_RELEASE_DEFAULT}"
   local version="${4:-$VAULT_CHART_VERSION}"  # optional

   if [[ "$mode" != "dev" && "$mode" != "ha" ]]; then
      echo "[vault] usage: deploy_vault <dev|ha> [<ns> [<release> [<chart-version>]]]" >&2
      exit 1
   fi

   deploy_eso

   _vault_ns_ensure "$ns"
   _vault_repo_setup

   if [[ "$mode" != "dev" && "$mode" != "ha" ]]; then
      echo "[vault] unknown mode '$mode'" >&2
      exit 127
   fi

   if ! declare -F "_vault_values_${mode}" >/dev/null 2>&1; then
      echo "[vault] unknown mode '$mode'" >&2
      exit 127
   fi

   values="$(_vault_values_"${mode}")"
   if [[ -z "$values" || ! -f "$values" ]]; then
      _err "[vault] cannot create values for mode '$mode'"
   fi

   args=(upgrade --install "$release" hashicorp/vault -n "$ns" -f "$values" --wait)
   [[ -n "$version" ]] && args+=("--version" "$version")
   _helm "${args[@]}"

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
  if ! _is_vault_deployed "$ns" "$release"; then
      _err "[vault] not deployed in ns=$ns release=$release" >&2
  fi

  if  _run_command --no-exit -- \
     kubectl --no-exit exec -n "$ns" -it vault-0 -- vault status >/dev/null 2>&1; then
      echo "[vault] already initialized"
      return 0
  fi

  # check if vault sealed or not
  if _run_command --no-exit -- \
     kubectl exec -n "$ns" -it vault-0 -- vault status 2>&1 | grep -q 'unseal'; then
      _warn "[vault] already initialized (sealed), skipping init"
      return 0
  fi

  local jsonfile="/tmp/init-vault.json";
  _kubectl wait -n "$ns" --for=condition=Podscheduled pod/vault-0 --timeout=120s
  local vault_state=$(_kubectl --no-exit -n "$ns" get pod vault-0 -o jsonpath='{.status.phase}')
  end_time=$((SECONDS + 120))
  current_time=$SECONDS
  while [[ "$vault_state" != "Running" ]]; do
      echo "[vault] waiting for vault-0 to be Running (current=$vault_state)"
      sleep 2
      vault_state=$(_kubectl --no-exit -n "$ns" get pod vault-0 -o jsonpath='{.status.phase}')
      if (( current_time >= end_time )); then
         _err "[vault] timeout waiting for vault-0 to be Running (current=$vault_state)" >&2to3
      fi
  done
  local vault_init=$(_kubectl --no-exit -n "$ns" exec -i vault-0 -- vault status -format json | jq -r '.initialized')
  if [[ "$vault_init" == "true" ]]; then
     _warn "[vault] already initialized, skipping init"
     return 0
  fi
  _kubectl -n "$ns" exec -it vault-0 -- \
     sh -lc 'vault operator init -key-shares=1 -key-threshold=1 -format=json' \
     > "$jsonfile"

  local root_token=$(jq -r '.root_token' "$jsonfile")
  local unseal_key=$(jq -r '.unseal_keys_b64[0]' "$jsonfile")
  _no_trace _kubectl -n "$ns" create secret generic vault-root \
     --from-literal=root_token="$root_token"
  # unseal all pods
  for pod in $(_kubectl --no-exit -n vault get pod -l 'app.kubernetes.io/name=vault,app.kubernetes.io/instance=vault' -o name); do
     _no_trace _kubectl -n "$ns" exec -i vault-0 -- \
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

  case "$rc" in
     200|429|472|473) _info "return code: $rc"; return 1 ;;
     *)               _info "return code: $rc"; return 0 ;;
  esac
}

function _vault_policy_exists() {
  local ns="${1:-$VAULT_NS_DEFAULT}" name="${2:-eso-reader}"

  local VAULT_TOKEN="$(_no_trace _kubectl --no-exit -n "$ns" \
     get secret vault-root \
     -o jsonpath='{.data.root_token}' | base64 -d)"
  _no_trace printf '%s\n' "$VAULT_TOKEN" | \
     _no_trace _kubectl --no-exit -n "$ns" exec -i vault-0 -- \
     sh -lc "VAULT_TOKEN=$VAULT_TOKEN vault policy list" | grep -q "^${name}\$"
  unset VAULT_TOKEN

  local rc=$?
  case "$rc" in
     0)  (( rc=1 )) ;;  # exists
     1) (( rc=0 )) ;;  # does not exist
  esac
  return "$rc"
}

function _enable_kv2_k8s_auth() {
  local ns="${1:-$VAULT_NS_DEFAULT}"
  local release="${2:-$VAULT_RELEASE_DEFAULT}"
  local eso_sa="${3:-external-secrets}"
  local eso_ns="${4:-external-secrets}"

  if ! _vault_policy_exists "$ns" "eso-reader"; then
     _info "[vault] policy 'eso-reader' already exists, skipping k8s auth setup"
     return 0
  fi

  # ↓ NEW: fetch root token once
  local VAULT_TOKEN="$(_kubectl --no-exit -n "$ns" get secret vault-root \
     -o jsonpath='{.data.root_token}' | base64 -d)"

  # kubernetes auth so no token stored in k8s
  cat <<'SH' | _no_trace _kubectl -n "$ns" exec -i vault-0 -- \
    env VAULT_TOKEN="$VAULT_TOKEN" sh -
set -e
vault secrets enable -path=secret kv-v2 || true
vault auth enable kubernetes || true

vault write auth/kubernetes/config \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
SH

  # create a policy -- eso-reader
  cat <<'HCL' | _no_trace _kubectl -n "$ns" exec -i vault-0 -- \
    env VAULT_TOKEN="$VAULT_TOKEN" \
    vault policy write eso-reader -
     # file: eso-reader.hcl
     # read any keys under eso/*
     path "secret/data/eso/*"      { capabilities = ["read"] }
     path "secret/metadata/eso"    { capabilities = ["list"] }
     path "secret/metadata/eso/*"  { capabilities = ["read","list"] }

HCL

  # map ESO service account to the policy
  _no_trace _kubectl -n "$ns" exec -i vault-0 -- \
    env VAULT_TOKEN="$VAULT_TOKEN" \
    vault write auth/kubernetes/role/eso-reader \
      bound_service_account_names="$eso_sa" \
      bound_service_account_namespaces="$eso_ns" \
      policies=eso-reader \
      ttl=1h
}
