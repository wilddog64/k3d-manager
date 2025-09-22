#!/usr/bin/env bash
# shellcheck shell=bash
# Helper functions for working with Vault PKI certificates.

# Extract the serial number from a PEM encoded certificate file.
# Outputs the serial as an uppercase hex string without the leading
# "serial=" prefix. Returns non-zero when the serial cannot be parsed.
function extract_certificate_serial() {
   local cert_file="$1"
   if [[ -z "$cert_file" || ! -s "$cert_file" ]]; then
      return 1
   fi

   local serial
   if ! serial=$(openssl x509 -noout -serial -in "$cert_file" 2>/dev/null); then
      return 1
   fi

   serial=${serial#serial=}
   serial=${serial^^}
   printf '%s' "$serial"
}

# Revoke a certificate in Vault given its serial number. The second argument
# optionally overrides the PKI path (defaults to VAULT_PKI_PATH). The third
# argument can supply a handler function used to perform the API call; it must
# accept the signature: <method> <path> <json-payload> [extra args...].
# Additional arguments are forwarded to the handler.
function revoke_certificate_serial() {
   local serial="$1"
   local path="${2:-${VAULT_PKI_PATH:-pki}}"
   local handler="${3:-vault_api_request}"

   if [[ -z "$serial" ]]; then
      return 0
   fi

   local payload revoke_path
   payload=$(jq -n --arg serial "$serial" '{serial_number: $serial}') || return 1
   revoke_path="${path%/}/revoke"

   if [[ $# -gt 3 ]]; then
      "$handler" POST "$revoke_path" "$payload" "${@:4}"
   else
      "$handler" POST "$revoke_path" "$payload"
   fi
}
