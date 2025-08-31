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
      echo "[vault] cannot create values for mode '$mode'" >&2
      return 1
   fi

   args=(upgrade --install "$release" hashicorp/vault -n "$ns" -f "$values" --wait)
   [[ -n "$version" ]] && args+=("--version" "$version")
   _helm "${args[@]}"

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

# Initialize and unseal once (1 share / threshold 1); store keys in Secret/vault-root
function _vault_init_unseal() {
   ns="${1:-$VAULT_NS_DEFAULT}"
   release="${2:-$VAULT_RELEASE_DEFAULT}"

   pod="$(
       _kubectl -n "$ns" get pod \
       -l "app.kubernetes.io/name=vault,app.kubernetes.io/instance=$release,component=server" \
       -o jsonpath='{.items[0].metadata.name}'
   )"

      if [[ -z "$pod" ]]; then
         echo "[vault] no vault server pod found in ns=$ns release=$release" >&2
         return 1
      fi

      initd="$(
          _kubectl --no-exit -n "$ns" exec "$pod" -- sh -lc 'vault status -format=json \
            | jq -r .initialized' 2>/dev/null
      )"
      if [[ "$initd" == "true" ]]; then
         echo "[vault] already initialized."
         return 0
      fi

      tmp="$(mktemp -t)"
      _cleanup_register "$tmp"
      _kubectl --no-exit -n "$ns" exec "$pod" -- sh -lc 'vault operator init -key-shares=1 -key-threshold=1 -format=json' >"$tmp" || { echo "[vault] init failed" >&2; rm -f "$tmp"; return 1; }

      unseal_key="$(jq -r '.unseal_keys_b64[0]' "$tmp")"
      root_token="$(jq -r '.root_token' "$tmp")"

      if [[ -z "$unseal_key" || -z "$root_token" ]]; then
         echo "[vault] parse init output failed" >&2
         return 1
      fi

      _kubectl -n "$ns" exec "$pod" -- sh -lc "vault operator unseal '$unseal_key'"

      # Save for lab convenience
      _kubectl --no-exit -n "$ns" create secret generic vault-root \
      --from-literal=root_token="$root_token" \
      --from-literal=unseal_key="$unseal_key" \
      --dry-run=client -o yaml | \
      _kubectl apply -f -
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
