function _lookup_bw_access_token() {
   fifo="$(mktemp -u)"
   trap 'clean_on_success "$fifo"' EXIT INT TERM RETURN
   mkfifo -m 600 "$fifo"
   if is_mac ; then
      (_security find-generic-password -a esobw -s BW_MACHINE_TOKEN -w > "$fifo") &
   elif is_linux ; then
      (_secret_tool lookup service BW_MACHINE_TOKEN account esobw > "$fifo") &
   fi
   writer=$!

   cat "$fifo"
   wait "$writer"
   return $?
}

function get_bw_access_token() {
   _lookup_bw_access_token
}

# Configure a SecretStore for Bitwarden Secrets Manager
# Usage: eso_config_bitwarden <org_id> <project_id>
function config_bws_eso() {
  local org_id="$1"
  local project_id="$2"

  local bws_vars="${SCRIPT_DIR}/etc/bitwarden/bws-vars.sh"
  if [[ ! -f "${bws_vars}" ]]; then
      echo "Bitwarden vars file ${bws_vars} not found!" >&2
      exit -1
  fi
  source "${bws_vars}"
  export ORG_ID="${org_id:-${ORG_ID:?set ORG_ID or pass org_id}}"
  export PROJECT_ID="${project_id:-${PROJECT_ID:?set PROJECT_ID or pass project_id}}"

  local ns="${4:-external-secrets}"

  # Kubernetes Secret with the token
  bws_exist=$(_run_command --quiet --probe "${HOME}/.kube/config" -- \
      _kubectl -n "$ns" \
         get secret bws-access-token >/dev/null 2>&1
      )
  if [[ ! "${bws_exist}" ]]; then
     _run_command --quiet --probe "${HOME}/.kube/config" -- _kubectl -n "${ns}" \
        create secret generic bws-access-token \
        --from-file=token=<(get_bw_access_token) >/dev/null 2>&1
  fi

  # Grab the CA bundle from the tls secret (already base64 encoded)
  local ca_b64=$(_run_command --quiet --probe "${HOME}/.kube/config" -- \
     _kubectl -n "$ns" get secret bitwarden-tls-certs \
             -o jsonpath='{.data.tls\.crt}')

  local yamlfile=$(mktemp -t)
  local bws_tmpl="${SCRIPT_DIR}/etc/bitwarden/bws-eso.yaml.tmpl"
  trap 'cleanup_on_success "${yamlfile}"' EXIT INT TERM RETURN

  if [[ ! -f "${bws_tmpl}" ]]; then
      echo "Template file ${bws_tmpl} not found!" >&2
      exit -1
  fi
  envsubst < "$bws_tmpl" > "$yamlfile"

  # Build and apply SecretStore
  _run_command --quiet --probe "${HOME}/.kube/config" -- \
     _kubectl apply -n "${ns}" -f "${yamlfile}"

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
