function _lookup_bw_access_token() {
   fifo="$(mktemp -u)"
   mkfifo -m 600 "$fifo"
   if is_mac ; then
      (_security find-generic-password -a esobw -s BW_MACHINE_TOKEN -w > "$fifo") &
   elif is_linux ; then
      (_secret_tool lookup service BW_MACHINE_TOKEN account esobw > "$fifo") &
   fi
   writer=$!

   cat "$fifo"
   wait "$writer"
   trap 'clean_on_success "$fifo"' EXIT INT TERM
}

function get_bw_access_token() {
   _lookup_bw_access_token
}

# Configure a SecretStore for Bitwarden Secrets Manager
# Usage: eso_config_bitwarden <org_id> <project_id> [machine_token] [namespace]
function config_bitwarden_eso() {
  local org_id="${1:?org_id required}"
  local project_id="${2:?project_id required}"
  local token="${3:-$BW_ACCESS_TOKEN}"
  local ns="${4:-external-secrets}"

  if [[ -z "$token" ]]; then
    echo "Bitwarden machine token is required (arg3 or BW_MACHINE_TOKEN env)." >&2
    return 1
  fi

  # Kubernetes Secret with the token
  _kubectl -n "$ns" delete secret bitwarden-access-token >/dev/null 2>&1 || true
  _kubectl -n "$ns" create secret generic bitwarden-access-token \
    --from-literal=token="$token" >/dev/null 2>&1

  # Grab the CA bundle from the tls secret (already base64 encoded)
  local ca_b64
  ca_b64="$(_kubectl -n "$ns" get secret bitwarden-tls-certs \
             -o jsonpath='{.data.tls\.crt}')"

  # Build and apply SecretStore
  cat <<EOF | _kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: bitwarden-secretsmanager
  namespace: ${ns}
spec:
  provider:
    bitwardensecretsmanager:
      # Defaults shown; override if you self-host Bitwarden SM
      apiURL: https://api.bitwarden.com
      identityURL: https://identity.bitwarden.com
      bitwardenServerSDKURL: https://bitwarden-sdk-server.${ns}.svc.cluster.local:9998
      caBundle: ${ca_b64}
      organizationID: ${org_id}
      projectID: ${project_id}
      auth:
        secretRef:
          credentials:
            name: bitwarden-access-token
            key: token
EOF

  echo "Created SecretStore 'bitwarden-secretsmanager' in namespace ${ns}"
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
    name: bitwarden-secretsmanager
    kind: SecretStore
  data:
    - secretKey: ${k8s_key}
      remoteRef:
        key: "${uuid}"
EOF
  echo "ExternalSecret '${k8s_name}' created (namespace ${ns})."
}
