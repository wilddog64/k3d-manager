# Returns the Bitwarden machine token to stdout.
# Exits if lookup fails or token is empty. No noise on stdout.
function _lookup_bw_access_token() {
  local token

  if is_mac; then
    token="$(_security find-generic-password -a esobw -s BW_MACHINE_TOKEN -w 2>/dev/null)" || exit 1
  elif is_linux; then
    _ensure_secret_tool >/dev/null 2>&1
    token="$(secret-tool lookup service BW_MACHINE_TOKEN account esobw 2>/dev/null)" || true
  else
    echo "unsupported OS" >&2
    exit 1
  fi

  [[ -n $token ]] || { echo "empty Bitwarden token" >&2; exit 1; }
  printf '%s' "$token"
}

# Create or update the kubernetes Secret: bws-access-token in ${ns}
function ensure_bws_secret() {
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
  local ca_b64="$(_kubectl -n "$ns" get secret bitwarden-tls-certs -o jsonpath='{.data.tls\.crt}')"

  # Render SecretStore from template and apply
  local yamlfile="$(mktemp)"  # mktemp -t creates a file *and* returns a path; plain mktemp is fine here
  local bws_tmpl="${SCRIPT_DIR}/etc/bitwarden/bws-eso.yaml.tmpl"
  trap 'cleanup_on_success "'"$yamlfile"'"' EXIT INT TERM  # avoid RETURN to prevent multiple triggers

  if [[ ! -f "${bws_tmpl}" ]]; then
      echo "Template file ${bws_tmpl} not found!" >&2
      exit -1
  fi
  envsubst < "$bws_tmpl" > "$yamlfile"

  # Build and apply SecretStore
  _kubectl apply -n "$ns" -f "$yamlfile"

  verify_bws_token

  echo "Created SecretStore 'bws-secretsmanager' in namespace ${ns}"
}

# Example: materialize a Kubernetes Secret from Bitwarden by UUID or by name
# Usage: eso_example_by_uuid <uuid> [namespace] [k8s_secret_name] [k8s_secret_key]
function eso_example_by_uuid() {
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
   local ns="${1:-external-secrets}"

   local bws_token_sha=$(_get_bw_access_token | _sha256_12 )
   local k3d_bws_sha=$(_kubectl -n "$ns" get secret bws-access-token \
      -o jsonpath='{.data.token}' | base64 --decode | _sha256_12)
   if _compare_token "$bws_token_sha" "$k3d_bws_token"; then
      echo "✅ Bitwarden token in k3d matches local token."
   else
      echo "❌ Bitwarden token in k3d does NOT match local token!" >&2
      exit -1
   fi
}
