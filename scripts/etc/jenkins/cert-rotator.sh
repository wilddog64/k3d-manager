#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck disable=SC1091
source "${SCRIPT_ROOT}/lib/vault_pki.sh"

log() {
   local level="${1:-INFO}"
   shift || true
   printf '[%(%Y-%m-%dT%H:%M:%SZ)T] [%s] %s\n' -1 "$level" "$*" >&2
}

require_env() {
   local name
   for name in "$@"; do
      if [[ -z "${!name:-}" ]]; then
         log ERROR "Required environment variable '$name' is not set"
         exit 1
      fi
   done
}

require_cmd() {
   local cmd
   for cmd in "$@"; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
         log ERROR "Required command '$cmd' not found in PATH"
         exit 1
      fi
   done
}

join_by() {
   local IFS="$1"
   shift
   echo "$*"
}

load_secret_certificate() {
   local ns="$1" name="$2" tmpdir="$3"
   local secret_json cert_b64 cert_file

   if ! secret_json=$(kubectl -n "$ns" get secret "$name" -o json 2>/dev/null); then
      log WARN "Secret ${ns}/${name} not found; a new certificate will be issued"
      return 1
   fi

   cert_b64=$(printf '%s' "$secret_json" | jq -r '.data["tls.crt"] // empty')
   if [[ -z "$cert_b64" ]]; then
      log WARN "Secret ${ns}/${name} is missing tls.crt; a new certificate will be issued"
      return 1
   fi

   cert_file="$tmpdir/current.crt"
   if ! printf '%s' "$cert_b64" | base64 -d >"$cert_file" 2>/dev/null; then
      log WARN "Failed to decode existing certificate from ${ns}/${name}; rotating"
      return 1
   fi

   printf '%s' "$cert_file"
   return 0
}

seconds_until_expiry() {
   local cert_file="$1" now expiry expiry_epoch
   expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null)
   expiry=${expiry#notAfter=}
   if [[ -z "$expiry" ]]; then
      echo 0
      return 1
   fi
   if ! expiry_epoch=$(date -u -d "$expiry" +%s 2>/dev/null); then
      echo 0
      return 1
   fi
   now=$(date -u +%s)
   echo $(( expiry_epoch - now ))
}

extract_common_name() {
   local cert_file="$1" cn
   cn=$(openssl x509 -noout -subject -nameopt RFC2253 -in "$cert_file" 2>/dev/null)
   cn=${cn#subject=CN=}
   printf '%s' "$cn"
}

extract_dns_sans() {
   local cert_file="$1"
   local -a sans=()
   local line entry
   while IFS= read -r line; do
      line=${line// /}
      IFS=',' read -ra entries <<<"$line"
      for entry in "${entries[@]}"; do
         if [[ "$entry" == DNS:* ]]; then
            sans+=("${entry#DNS:}")
         fi
      done
   done < <(openssl x509 -noout -ext subjectAltName -in "$cert_file" 2>/dev/null | tail -n +2)

   if (( ${#sans[@]} )); then
      join_by ',' "${sans[@]}"
   fi
}

vault_api_request() {
   local method="$1" path="$2" data="${3:-}"
   local url token_header namespace_header

   url="${VAULT_ADDR%/}/v1/${path#/}"

   local -a args=("--silent" "--show-error" "--fail" "--request" "$method")

   if [[ -n "${VAULT_NAMESPACE:-}" ]]; then
      namespace_header="X-Vault-Namespace: ${VAULT_NAMESPACE}"
      args+=("--header" "$namespace_header")
   fi

   if [[ "${VAULT_SKIP_VERIFY:-}" == "1" ]]; then
      args+=(-k)
   elif [[ -n "${VAULT_CACERT:-}" ]]; then
      args+=("--cacert" "$VAULT_CACERT")
   fi

   if [[ -n "$data" ]]; then
      args+=("--header" "Content-Type: application/json" "--data" "$data")
   fi

   if [[ -n "${VAULT_TOKEN:-}" ]]; then
      token_header="X-Vault-Token: ${VAULT_TOKEN}"
      args+=("--header" "$token_header")
   fi

   curl "${args[@]}" "$url"
}

vault_login() {
   local auth_path="${VAULT_K8S_AUTH_PATH:-auth/kubernetes/login}"
   if [[ "$auth_path" != */login ]]; then
      auth_path="${auth_path%/}/login"
   fi

   local token_path="${SERVICE_ACCOUNT_TOKEN_FILE:-/var/run/secrets/kubernetes.io/serviceaccount/token}"
   if [[ ! -r "$token_path" ]]; then
      log ERROR "Service account token not readable at $token_path"
      exit 1
   fi

   local jwt
   jwt=$(<"$token_path")

   local payload
   payload=$(jq -n --arg role "$JENKINS_CERT_ROTATOR_VAULT_ROLE" --arg jwt "$jwt" '{role: $role, jwt: $jwt}')

   local response
   if ! response=$(vault_api_request POST "$auth_path" "$payload"); then
      log ERROR "Vault login request failed"
      exit 1
   fi

   VAULT_TOKEN=$(printf '%s' "$response" | jq -r '.auth.client_token // empty')
   if [[ -z "$VAULT_TOKEN" ]]; then
      log ERROR "Vault login did not return a client token"
      exit 1
   fi
}

mint_certificate() {
   local cn="$1" alt_names="$2"
   local payload_expr='{common_name: $cn}'
   local -a payload_args=(--arg cn "$cn")

   if [[ -n "$alt_names" ]]; then
      payload_expr+=', alt_names: $alt'
      payload_args+=(--arg alt "$alt_names")
   fi

   if [[ -n "${VAULT_PKI_ROLE_TTL:-}" ]]; then
      payload_expr+=', ttl: $ttl'
      payload_args+=(--arg ttl "$VAULT_PKI_ROLE_TTL")
   fi

   local payload
   payload=$(jq -n "${payload_args[@]}" "$payload_expr")

   local issue_path="${VAULT_PKI_PATH:-pki}"
   issue_path="${issue_path%/}/issue/${VAULT_PKI_ROLE}"

   local response
   if ! response=$(vault_api_request POST "$issue_path" "$payload"); then
      log ERROR "Failed to issue certificate from Vault role ${VAULT_PKI_ROLE}"
      exit 1
   fi

   printf '%s' "$response"
}

apply_secret() {
   local ns="$1" name="$2" cert="$3" key="$4" ca_bundle="$5"
   local tmpfile
   tmpfile=$(mktemp)
   cat >"$tmpfile" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${name}
  namespace: ${ns}
  annotations:
    k3d.dev/managed-by: jenkins-cert-rotator
    k3d.dev/managed-at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
type: kubernetes.io/tls
stringData:
  tls.crt: |
$(printf '%s\n' "$cert" | sed 's/^/    /')
  tls.key: |
$(printf '%s\n' "$key" | sed 's/^/    /')
  ca.crt: |
$(printf '%s\n' "$ca_bundle" | sed 's/^/    /')
EOF
   kubectl apply -f "$tmpfile"
   rm -f "$tmpfile"
}

main() {
   require_env VAULT_ADDR VAULT_PKI_ROLE VAULT_PKI_SECRET_NS VAULT_PKI_SECRET_NAME JENKINS_CERT_ROTATOR_VAULT_ROLE
   require_cmd kubectl curl jq openssl base64 date

   local renew_before="${JENKINS_CERT_ROTATOR_RENEW_BEFORE:-432000}"
   if ! [[ "$renew_before" =~ ^[0-9]+$ ]]; then
      log ERROR "JENKINS_CERT_ROTATOR_RENEW_BEFORE must be numeric seconds"
      exit 1
   fi

   local tmpdir
   tmpdir=$(mktemp -d)
   trap 'if [[ -n "${tmpdir:-}" ]]; then rm -rf "$tmpdir"; fi' EXIT

   local secret_ns="$VAULT_PKI_SECRET_NS"
   local secret_name="$VAULT_PKI_SECRET_NAME"
   local cert_file="" should_issue=0

   local previous_serial=""
   if cert_file=$(load_secret_certificate "$secret_ns" "$secret_name" "$tmpdir"); then
      local remaining
      remaining=$(seconds_until_expiry "$cert_file") || should_issue=1
      if (( should_issue == 0 )); then
         if (( remaining > renew_before )); then
            log INFO "Certificate for ${secret_ns}/${secret_name} is valid for another ${remaining}s; skipping rotation"
            return 0
         else
            log INFO "Certificate for ${secret_ns}/${secret_name} expires in ${remaining}s (threshold ${renew_before}s); rotating"
         fi
      else
         log WARN "Unable to determine remaining lifetime; rotating"
      fi
      if ! previous_serial=$(extract_certificate_serial "$cert_file"); then
         previous_serial=""
      fi
   else
      should_issue=1
   fi

   if [[ -z "$cert_file" ]]; then
      cert_file="$tmpdir/current.crt"
      if [[ -n "${VAULT_PKI_LEAF_HOST:-}" ]]; then
         printf '' >"$cert_file"
      fi
   fi

   local common_name=""
   if [[ -s "$cert_file" ]]; then
      common_name=$(extract_common_name "$cert_file")
   fi
   if [[ -z "$common_name" && -n "${VAULT_PKI_LEAF_HOST:-}" ]]; then
      common_name="$VAULT_PKI_LEAF_HOST"
   fi
   if [[ -z "$common_name" ]]; then
      log ERROR "Unable to determine common name for certificate request"
      exit 1
   fi

   local alt_names=""
   if [[ -s "$cert_file" ]]; then
      alt_names=$(extract_dns_sans "$cert_file")
   fi
   if [[ -z "$alt_names" && -n "${JENKINS_CERT_ROTATOR_ALT_NAMES:-}" ]]; then
      alt_names="$JENKINS_CERT_ROTATOR_ALT_NAMES"
   fi
   if [[ -z "$alt_names" ]]; then
      alt_names="$common_name"
   fi

   vault_login

   local response
   response=$(mint_certificate "$common_name" "$alt_names")

   local cert key ca_bundle
   cert=$(printf '%s' "$response" | jq -r '.data.certificate // empty')
   key=$(printf '%s' "$response" | jq -r '.data.private_key // empty')
   ca_bundle=$(printf '%s' "$response" | jq -r 'if (.data.ca_chain // empty) | length > 0 then (.data.ca_chain | join("\n")) else (.data.issuing_ca // "") end')

   if [[ -z "$cert" || -z "$key" ]]; then
      log ERROR "Vault response missing certificate or key"
      exit 1
   fi

   if [[ -z "$ca_bundle" ]]; then
      log WARN "Vault response missing CA bundle; proceeding without ca.crt"
      ca_bundle="$cert"
   fi

   apply_secret "$secret_ns" "$secret_name" "$cert" "$key" "$ca_bundle"
   if [[ -n "$previous_serial" ]]; then
      if ! revoke_certificate_serial "$previous_serial" "${VAULT_PKI_PATH:-pki}"; then
         log WARN "Failed to revoke previous certificate serial $previous_serial"
      fi
   fi
   log INFO "Updated TLS secret ${secret_ns}/${secret_name}"
}

main "$@"
