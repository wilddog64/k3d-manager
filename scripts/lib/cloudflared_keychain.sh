#!/usr/bin/env bash
# Helpers for the cloudflared Keychain backup format.

function _cloudflared_base64_decode() {
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    base64 --decode
  else
    base64 -D
  fi
}

function _cloudflared_keychain_read() {
  local service="$1"
  local raw decoded_file

  raw="$(security find-generic-password -a cloudflared -s "${service}" -w 2>/dev/null || true)"
  [[ -n "${raw}" ]] || return 1

  decoded_file="$(mktemp "${TMPDIR:-/tmp}/cloudflared-keychain-decode.XXXXXX")"
  if printf '%s' "${raw}" | _cloudflared_base64_decode > "${decoded_file}" 2>/dev/null \
    && { [[ "$(head -c 1 "${decoded_file}")" == '{' ]] \
      || [[ "$(head -c 10 "${decoded_file}")" == '-----BEGIN' ]]; }; then
    cat "${decoded_file}"
    rm -f "${decoded_file}"
    return 0
  fi

  if [[ "${raw}" =~ ^[0-9a-fA-F]+$ ]] && (( ${#raw} % 2 == 0 )); then
    if printf '%s' "${raw}" | xxd -r -p > "${decoded_file}" 2>/dev/null \
      && { [[ "$(head -c 1 "${decoded_file}")" == '{' ]] \
        || [[ "$(head -c 10 "${decoded_file}")" == '-----BEGIN' ]]; }; then
      cat "${decoded_file}"
      rm -f "${decoded_file}"
      return 0
    fi
  fi

  rm -f "${decoded_file}"
  printf '%s' "${raw}"
}

function _cloudflared_keychain_write_file() {
  local service="$1"
  local source_file="$2"
  local encoded check_file

  encoded="$(base64 < "${source_file}" | tr -d '\n')"
  printf 'add-generic-password -U -a cloudflared -s %s -w %s\n' \
    "${service}" "${encoded}" | security -i

  check_file="$(mktemp "${TMPDIR:-/tmp}/cloudflared-keychain-check.XXXXXX")"
  if ! _cloudflared_keychain_read "${service}" > "${check_file}" \
    || ! cmp -s "${source_file}" "${check_file}"; then
    rm -f "${check_file}"
    return 1
  fi
  rm -f "${check_file}"
}

function _cloudflared_restore_keychain_file() {
  local service="$1"
  local target_file="$2"
  local restored_file

  restored_file="$(mktemp "${TMPDIR:-/tmp}/cloudflared-keychain-restore.XXXXXX")"
  if ! _cloudflared_keychain_read "${service}" > "${restored_file}"; then
    rm -f "${restored_file}"
    return 1
  fi
  if ! install -m 600 "${restored_file}" "${target_file}"; then
    rm -f "${restored_file}"
    return 1
  fi
  rm -f "${restored_file}"
}
