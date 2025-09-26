#!/usr/bin/env bash
# shellcheck shell=bash
# Helper functions for working with Vault PKI certificates.

# Normalize a hexadecimal serial string into colon-separated hex pairs.
# Accepts raw serials with or without colons and returns the normalized
# representation in uppercase. When the serial has an odd number of hex
# digits, it is left-padded with a zero so that all pairs contain two
# characters.
function _vault_normalize_serial_hex_pairs() {
   local raw="${1:-}"

   raw=${raw//:/}
   raw=${raw//[[:space:]]/}
   raw=$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]')

   if [[ -z "$raw" ]]; then
      return 1
   fi

   if (( ${#raw} % 2 == 1 )); then
      raw="0${raw}"
   fi

   local formatted=""
   local i len=${#raw}
   for (( i = 0; i < len; i += 2 )); do
      if (( i > 0 )); then
         formatted+=':'
      fi
      formatted+="${raw:i:2}"
   done

   printf '%s' "$formatted"
}

# Extract the serial number from a PEM encoded certificate file.
# Outputs the serial as an uppercase hex string formatted as
# colon-separated pairs. Returns non-zero when the serial cannot be
# parsed.
function _vault_pki_extract_certificate_serial() {
   local cert_file="$1"
   if [[ -z "$cert_file" || ! -s "$cert_file" ]]; then
      return 1
   fi

   local serial
   if ! serial=$(openssl x509 -noout -serial -in "$cert_file" 2>/dev/null); then
      return 1
   fi

   serial=${serial#serial=}
   local normalized
   if ! normalized=$(_vault_normalize_serial_hex_pairs "$serial"); then
      return 1
   fi
   printf '%s' "$normalized"
}

# Revoke a certificate in Vault given its serial number. The second argument
# optionally overrides the PKI path (defaults to VAULT_PKI_PATH). The third
# argument can supply a handler function used to perform the API call; it must
# accept the signature: <method> <path> <json-payload> [extra args...].
# Additional arguments are forwarded to the handler.
function _vault_pki_revoke_certificate_serial() {
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
