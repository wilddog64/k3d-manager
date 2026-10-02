#!/usr/bin/env bats

REPO_ROOT="${BATS_TEST_DIRNAME}/../../.."

setup() {
  WORK="${BATS_TEST_TMPDIR}/work"
  STUB="${BATS_TEST_TMPDIR}/stub"
  STORE="${BATS_TEST_TMPDIR}/keychain"
  mkdir -p "${WORK}/scripts/lib" "${STUB}" "${STORE}" "${BATS_TEST_TMPDIR}/home/.cloudflared"
  cp "${REPO_ROOT}/Makefile" "${WORK}/Makefile"
  cp "${REPO_ROOT}/scripts/lib/cloudflared_keychain.sh" "${WORK}/scripts/lib/"
  printf '{"AccountTag":"SENTINEL_CREDS_9f3"}\n' > "${BATS_TEST_TMPDIR}/home/.cloudflared/bb7ece59-8680-4310-9437-232f862e2773.json"
  printf '%s\n%s\n' '-----BEGIN CERTIFICATE-----' 'SENTINEL_CERT_9f3' '-----END CERTIFICATE-----' > "${BATS_TEST_TMPDIR}/home/.cloudflared/cert.pem"
  : > "${BATS_TEST_TMPDIR}/argv.log"
  : > "${BATS_TEST_TMPDIR}/stdin.log"
  cat > "${STUB}/kubectl" <<'EOF'
#!/usr/bin/env bash
printf 'kubectl argv: %s\n' "$*" >> "${ARGV_LOG}"
printf 'ZmFrZS12YXVsdC10b2tlbg=='
EOF
  cat > "${STUB}/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'security argv: %s\n' "$*" >> "${ARGV_LOG:-/dev/null}"
if [[ "${1:-}" == "-i" ]]; then
  IFS= read -r command
  printf 'security stdin: %s\n' "${command}" >> "${STDIN_LOG:-/dev/null}"
  service="${command#*-s }"
  service="${service%% -w *}"
  value="${command##* -w }"
  printf '%s' "${value}" > "${STORE}/${service}"
  exit 0
fi
service="${5:-}"
cat "${STORE}/${service}"
EOF
  cat > "${STUB}/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl argv: %s\n' "$*" >> "${ARGV_LOG}"
cat > "${CURL_STDIN}"
EOF
  chmod +x "${STUB}"/*
  export ARGV_LOG="${BATS_TEST_TMPDIR}/argv.log"
  export STDIN_LOG="${BATS_TEST_TMPDIR}/stdin.log"
  export CURL_STDIN="${BATS_TEST_TMPDIR}/curl.stdin"
  export STORE
}

_make_backup() {
  run env HOME="${BATS_TEST_TMPDIR}/home" PATH="${STUB}:${PATH}" \
    ARGV_LOG="${ARGV_LOG}" STDIN_LOG="${STDIN_LOG}" CURL_STDIN="${CURL_STDIN}" STORE="${STORE}" \
    make --no-print-directory -C "${WORK}" cloudflared-backup
}

@test "backup keeps sentinels out of argv and sends Keychain commands and Vault JSON via stdin" {
  _make_backup
  [ "${status}" -eq 0 ]
  run grep -Fq 'SENTINEL_CREDS_9f3' "${ARGV_LOG}"
  [ "${status}" -ne 0 ]
  run grep -Fq 'SENTINEL_CERT_9f3' "${ARGV_LOG}"
  [ "${status}" -ne 0 ]
  run grep -Fq 'fake-vault-token' "${ARGV_LOG}"
  [ "${status}" -ne 0 ]
  grep -Fq 'security stdin: add-generic-password' "${STDIN_LOG}"
  grep -Fq 'SENTINEL_CREDS_9f3' "${CURL_STDIN}"
  grep -Fq 'SENTINEL_CERT_9f3' "${CURL_STDIN}"
}

@test "decoder returns a base64 item as the original bytes" {
  printf '%s' '{"AccountTag":"SENTINEL_CREDS_9f3"}' | base64 | tr -d '\n' > "${STORE}/base64"
  run env PATH="${STUB}:${PATH}" STORE="${STORE}" bash -c \
    "source '${REPO_ROOT}/scripts/lib/cloudflared_keychain.sh'; _cloudflared_keychain_read base64"
  [ "${status}" -eq 0 ]
  [ "${output}" = '{"AccountTag":"SENTINEL_CREDS_9f3"}' ]
}

@test "decoder restores a legacy hex-encoded multiline PEM" {
  printf '%s\n%s\n' '-----BEGIN CERTIFICATE-----' 'SENTINEL_CERT_9f3' '-----END CERTIFICATE-----' > "${BATS_TEST_TMPDIR}/expected.pem"
  xxd -p "${BATS_TEST_TMPDIR}/expected.pem" | tr -d '\n' > "${STORE}/hex"
  run env PATH="${STUB}:${PATH}" STORE="${STORE}" bash -c \
    "source '${REPO_ROOT}/scripts/lib/cloudflared_keychain.sh'; _cloudflared_keychain_read hex > '${BATS_TEST_TMPDIR}/decoded.pem'"
  [ "${status}" -eq 0 ]
  cmp "${BATS_TEST_TMPDIR}/expected.pem" "${BATS_TEST_TMPDIR}/decoded.pem"
}

@test "decoder leaves a legacy single-line JSON item unchanged" {
  printf '%s' '{"legacy":true}' > "${STORE}/raw"
  run env PATH="${STUB}:${PATH}" STORE="${STORE}" bash -c \
    "source '${REPO_ROOT}/scripts/lib/cloudflared_keychain.sh'; _cloudflared_keychain_read raw"
  [ "${status}" -eq 0 ]
  [ "${output}" = '{"legacy":true}' ]
}

@test "missing Keychain item returns rc 1 and no output" {
  run env PATH="${STUB}:${PATH}" STORE="${STORE}" bash -c \
    "source '${REPO_ROOT}/scripts/lib/cloudflared_keychain.sh'; _cloudflared_keychain_read missing"
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}

@test "restore decodes PEM and creates a mode-600 file" {
  printf '%s\n%s\n' '-----BEGIN CERTIFICATE-----' 'SENTINEL_CERT_9f3' '-----END CERTIFICATE-----' > "${BATS_TEST_TMPDIR}/expected.pem"
  xxd -p "${BATS_TEST_TMPDIR}/expected.pem" | tr -d '\n' > "${STORE}/restore-cert"
  run env PATH="${STUB}:${PATH}" STORE="${STORE}" bash -c \
    "source '${REPO_ROOT}/scripts/lib/cloudflared_keychain.sh'; _cloudflared_restore_keychain_file restore-cert '${BATS_TEST_TMPDIR}/restored.pem'"
  [ "${status}" -eq 0 ]
  cmp "${BATS_TEST_TMPDIR}/expected.pem" "${BATS_TEST_TMPDIR}/restored.pem"
  mode="$(stat -c '%a' "${BATS_TEST_TMPDIR}/restored.pem" 2>/dev/null || stat -f '%Lp' "${BATS_TEST_TMPDIR}/restored.pem")"
  [ "${mode}" = 600 ]
  run grep -Fq 'SENTINEL_CERT_9f3' "${ARGV_LOG}"
  [ "${status}" -ne 0 ]
}
