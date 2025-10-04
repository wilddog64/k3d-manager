function _install_bws() {
   if _command_exist bws ; then
      echo "bws already installed"
      return
   fi
   _ensure_cargo
   _run_command -- cargo install --locked bws
}

function _bws() {
   _install_bws
   _run_command -- bws "$@"
}

# Returns the Bitwarden machine token to stdout.
# Exits if lookup fails or token is empty. No noise on stdout.
function _lookup_bw_access_token() {
  local token="$(_bw_lookup_secret esobw BW_MACHINE_TOKEN)"

  [[ -n $token ]] || { echo "empty Bitwarden token" >&2; exit 1; }
  printf '%s' "$token"
}

function _bw_lookup_secret(){
   local account="$1"
   local service="$2"

   local token
   if _is_mac ; then
      token=$(_security find-generic-password -a "$account" -s "$service" -w)
   elif _is_linux ; then
      token=$(_secret_tool lookup service "$service" account "$account")
   fi

   if [[ -n $token ]]; then
      printf '%s' "$token"
   else
      echo "empty token for $account / $service" >&2
      exit 1
   fi
}

# Create or update the kubernetes Secret: bws-access-token in ${ns}
function ensure_bws_secret() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: ensure_bws_secret [namespace=external-secrets]"
    return 0
  fi
  local ns="${1:-external-secrets}"
  local token

  # Create/update the secret atomically via apply
  _kubectl -n "$ns" create secret generic bws-access-token \
     --from-literal=token="$(_lookup_bw_access_token)" \
     --dry-run=client -o yaml \
    | _kubectl -n "$ns" apply -f -
}

function _get_bw_access_token() {
   _lookup_bw_access_token
}

# Configure a SecretStore for Bitwarden Secrets Manager
# Usage: eso_config_bitwarden <org_id> <project_id>
function config_bws_eso() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: config_bws_eso <org_id> <project_id> [namespace=external-secrets]"
    return 0
  fi
  local org_id="$1"
  local project_id="$2"
  local ns="${3:-external-secrets}"

  local bws_vars="${SCRIPT_DIR}/etc/bitwarden/bws-vars.sh"
  if [[ ! -f "${bws_vars}" ]]; then
      echo "Bitwarden vars file ${bws_vars} not found!" >&2
      exit -1
  fi
  # shellcheck source=/dev/null
  source "${bws_vars}"
  export ORG_ID="${org_id:-${ORG_ID:?set ORG_ID or pass org_id}}"
  export PROJECT_ID="${project_id:-${PROJECT_ID:?set PROJECT_ID or pass project_id}}"

  # Ensure the token Secret exists (idempotent)
  ensure_bws_secret "$ns"

  # Grab the CA bundle from the tls secret (already base64-encoded)
  local ca_b64="$(_kubectl -n "$ns" get secret bitwarden-tls-certs -o jsonpath='{.data.tls\\.crt}')"

  # Render SecretStore from template and apply
  local yamlfile="$(mktemp -t bws-eso-XXXXXX.yaml)"  # mktemp -t creates a file *and* returns a path; plain mktemp is fine here
  local bws_tmpl="${SCRIPT_DIR}/etc/bitwarden/bws-eso.yaml.tmpl"
  trap '$(_cleanup_trap_command "$yamlfile")' EXIT INT TERM  # avoid RETURN to prevent multiple triggers

  if [[ ! -f "${bws_tmpl}" ]]; then
      echo "Template file ${bws_tmpl} not found!" >&2
      exit 127
  fi
  _ensure_envsubst
  envsubst < "$bws_tmpl" > "$yamlfile"

  # Build and apply SecretStore
  _kubectl apply -n "$ns" -f "$yamlfile"

  verify_bws_token

  echo "Created SecretStore 'bws-secretsmanager' in namespace ${ns}"
}

# Example: materialize a Kubernetes Secret from Bitwarden by UUID or by name
# Usage: eso_example_by_uuid <uuid> [namespace] [k8s_secret_name] [k8s_secret_key]
function eso_example_by_uuid() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: eso_example_by_uuid <uuid> [namespace] [k8s_secret_name] [k8s_secret_key]"
    return 0
  fi
  local uuid="${1:?bitwarden secret UUID required}"
  local ns="${2:-external-secrets}"
  local k8s_name="${3:-demo-bw}"
  local k8s_key="${4:-value}"

  cat <<EOF | _kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: ${k8s_name}
  namespace: ${ns}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bws-secretsmanager
    kind: SecretStore
  data:
    - secretKey: ${k8s_key}
      remoteRef:
        key: "${uuid}"
EOF
  echo "ExternalSecret '${k8s_name}' created (namespace ${ns})."
}

function verify_bws_token() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      echo "Usage: verify_bws_token [namespace=external-secrets]"
      return 0
   fi
   local ns="${1:-external-secrets}"

   local bws_token_sha=$(_get_bw_access_token | _sha256_12 )
   local k3d_bws_sha=$(_kubectl -n "$ns" get secret bws-access-token \
      -o jsonpath='{.data.token}' | base64 --decode | _sha256_12)
   if ! _is_same_token "$bws_token_sha" "$k3d_bws_sha"; then
      echo "Bitwarden token in k3d does NOT match local token!" >&2
      exit -1
   else
      echo "Bitwarden token in k3d matches local token."
   fi
}
