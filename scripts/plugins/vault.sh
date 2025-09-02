#!/usr/bin/env bash
# k3d-manager :: HashiCorp Vault helpers (ESO-friendly)
# Style: uses command / _kubectl / _helm, no set -e, minimal locals.

# Defaults (override via env or args to the top-levels)
VAULT_NS_DEFAULT="${VAULT_NS_DEFAULT:-vault}"
VAULT_RELEASE_DEFAULT="${VAULT_RELEASE_DEFAULT:-vault}"
VAULT_CHART_VERSION="${VAULT_CHART_VERSION:-0.30.1}"
VAULT_SC="${VAULT_SC:-local-path}"   # k3d/k3s default

# --- primitives ----------------------------------------------------

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

# function _vault_server_pods() {
#   local ns="${1:?}" release="${2:?}"
#   _kubectl -n "$ns" get pod -l "app.kubernetes.io/name=vault,app.kubernetes.io/instance=${release},app.kubernetes.io/component=server" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
# }

function _vault_status_code() {
  local ns="${1:?}" pod="${2:?}"
  _kubectl --no-exit -n "$ns" exec "$pod" -c vault -- sh -lc 'VAULT_ADDR=http://127.0.0.1:8200 vault status >/dev/null 2>&1; echo $?'
}

# function _with_deadline() { date -u +%s; }
#
# function _vault_init_if_needed() {
#   local ns="${1:?}" release="${2:?}"
#   local sel="app.kubernetes.io/name=vault,app.kubernetes.io/instance=${release},component=server"
#   local pod deadline=$(( $(_with_deadline) + 300 ))
#   while (( $(_with_deadline) < deadline )); do
#     pod="$(
#       _kubectl --no-exit -n "$ns" get pod -l "$sel" \
#         -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | awk '{print $1}'
#     )"
#     [[ -n "$pod" ]] && { echo "$pod"; return 0; }
#     sleep 2
#   done
#   _err "[vault] timeout waiting for server pod (ns=$ns release=$release)" >&2
# }

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
  _kubectl -n "$ns" exec -it vault-0 -- \
     sh -lc 'VAULT_ADDR=http://127.0.0.1:8200 vault operator init -key-shares=1 -key-threshold=1 -format=json' \
     > "$jsonfile"

  local root_token=$(jq -r '.root_token' "$jsonfile")
  local unseal_key=$(jq -r '.unseal_keys_b64[0]' "$jsonfile")
  _kubectl -n "$ns" create secret generic vault-root \
     --from-literal=root_token="$root_token" \
     --from-literal=unseal_key="$unseal_key"
  # unseal all pods
  for pod in $(_kubectl --no-exit -n vault get pod -l 'app.kubernetes.io/name=vault,app.kubernetes.io/instance=vault' -o name); do
     _kubectl -n "$ns" exec -i vault-0 -- \
        sh -lc "vault operator unseal $unseal_key" >/dev/null 2>&1
     _info "[vault] unsealed $pod"
  done
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

# --- top-level orchestration (small + explicit) -------------------

function _vault_deploy_dev() {
   ns="${1:-$VAULT_NS_DEFAULT}"
   release="${2:-$VAULT_RELEASE_DEFAULT}"
   version="${3:-$VAULT_CHART_VERSION}"

   vault_install dev "$ns" "$release" "$version" || return $?
   _vault_wait_ready "$ns" "$release"
   echo "[vault] dev ready in ns=$ns release=$release"
   _vault_portforward_help "$ns" "$release"
}

function _vault_deploy_ha() {
   ns="${1:-$VAULT_NS_DEFAULT}"
   release="${2:-$VAULT_RELEASE_DEFAULT}"
   version="${3:-$VAULT_CHART_VERSION}"

   vault_install ha "$ns" "$release" "$version" || return $?
   _vault_wait_ready "$ns" "$release"
   _vault_init_unseal "$ns" "$release"
   echo "[vault] ha ready in ns=$ns release=$release (initialized + unsealed)"
   _vault_portforward_help "$ns" "$release"
}


function _vault_health_ok() {
  local mode="${1:?}" code="${2:?}"
  case "$mode" in
    dev) [[ "$code" == "200" ]];;
    ha)  [[ "$code" =~ ^(200|429|472|473)$ ]];;
    *)   return 1;;
  esac
}

function _vault_health_code_incluster() {
  local ns="${1:?}" release="${2:?}" scheme="${3:-http}" port="${4:-8200}"
  local host="${release}-server.${ns}.svc"
  local name="vault-health-$RANDOM$RANDOM"
  _kubectl -n "$ns" run "$name" --rm -i --restart=Never \
    --image=curlimages/curl:8.10.1 --command -- sh -c \
    "curl -s -o /dev/null -w '%{http_code}' '${scheme}://${host}:${port}/v1/sys/health' || true"
}

function _vault_verify() {
  local mode="${1:?usage: vault_verify <dev|ha> [ns] [release] [scheme] [port]}"
  local ns="${2:-$VAULT_NS_DEFAULT}"
  local release="${3:-$VAULT_RELEASE_DEFAULT}"
  local scheme="${4:-http}"
  local port="${5:-8200}"

  [[ "$mode" == "dev" || "$mode" == "ha" ]] || { echo "[vault] mode must be dev|ha" >&2; return 2; }

  local code
  code="$(_vault_health_code_incluster "$ns" "$release" "$scheme" "$port")" || { echo "[vault] health probe pod failed" >&2; return 1; }

  if _vault_health_ok "$mode" "$code"; then
    echo "[vault] OK (mode=$mode, health=$code)"
  else
    echo "[vault] health check failed: HTTP $code (mode=$mode)" >&2
    return 1
  fi
}
