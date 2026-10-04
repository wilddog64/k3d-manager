#!/usr/bin/env bats

MAKEFILE="${BATS_TEST_DIRNAME}/../../../Makefile"

setup() {
  RECIPE="$(awk '/^hermes-drain-token:/,/^$/' "${MAKEFILE}")"
  RELAY_DIR="${BATS_TEST_TMPDIR}/relay"
  mkdir -p "${RELAY_DIR}"
  cp "${BATS_TEST_DIRNAME}/../../../workers/slack-relay/wrangler.toml" "${RELAY_DIR}/wrangler.toml"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat >"${BATS_TEST_TMPDIR}/bin/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'argv:' >>"${BATS_TEST_TMPDIR}/security.log"
printf ' <%s>' "$@" >>"${BATS_TEST_TMPDIR}/security.log"
printf '\n' >>"${BATS_TEST_TMPDIR}/security.log"
if [[ "${1:-}" == "-i" ]]; then
  cat >>"${BATS_TEST_TMPDIR}/security.stdin"
  exit 0
fi
if [[ "${1:-}" == "find-generic-password" ]]; then
  case "$*" in
    *k3dm-cloudflare-api-token*) printf 'cf-token\n' ;;
    *k3dm-hermes-approval-drain-token*) [[ -f "${BATS_TEST_TMPDIR}/drain-token" ]] && cat "${BATS_TEST_TMPDIR}/drain-token" || exit 44 ;;
  esac
fi
EOF
  cat >"${BATS_TEST_TMPDIR}/bin/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'argv:' >>"${BATS_TEST_TMPDIR}/npx.log"
printf ' <%s>' "$@" >>"${BATS_TEST_TMPDIR}/npx.log"
printf '\n' >>"${BATS_TEST_TMPDIR}/npx.log"
cat >"${BATS_TEST_TMPDIR}/npx.stdin"
if [[ "$*" == *"kv namespace create APPROVALS_KV"* ]]; then
  printf 'id = "0123456789abcdef0123456789abcdef"\n'
fi
EOF
  cat >"${BATS_TEST_TMPDIR}/bin/openssl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/security" "${BATS_TEST_TMPDIR}/bin/npx" "${BATS_TEST_TMPDIR}/bin/openssl"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

@test "all Slack approval targets are declared phony" {
  run awk '/^\.PHONY:/,/^$/' "${MAKEFILE}"

  [ "${status}" -eq 0 ]
  for target in hermes-approvals-kv hermes-drain-token hermes-approvers hermes-approvals-setup; do
    [[ "${output}" == *"${target}"* ]]
  done
}

@test "hermes-drain-token has the interactive credential gate" {
  [[ "${RECIPE}" == *'[ -t 0 ]'* ]]
  [[ "${RECIPE}" == *"must not run unattended"* ]]
}

@test "Hermes drain credentials are never echoed" {
  # shellcheck disable=SC2016
  case "${RECIPE}" in
    *'echo "$$_tok"'*|*'echo $$_tok'*|*'echo "$$_stored"'*|*'echo $$_stored'*)
      return 1 ;;
  esac
}

@test "Hermes drain tokens never reach security through argv" {
  [[ "${RECIPE}" == *'| security -i'* ]]
  # shellcheck disable=SC2016
  case "${RECIPE}" in
    *'-w "$$_tok"'*|*'-w "$$_stored"'*)
      return 1 ;;
  esac
}

@test "hermes-drain-token reads the Keychain value back" {
  [[ "${RECIPE}" == *'| security -i'* ]]
  [[ "${RECIPE}" == *"reads back empty"* ]]
}

@test "invalid approvers fail before reading credentials" {
  run make -f "${MAKEFILE}" RELAY_DIR="${RELAY_DIR}" hermes-approvers APPROVERS='U1 2'

  [ "${status}" -ne 0 ]
  [ ! -s "${BATS_TEST_TMPDIR}/security.log" ]
  [ ! -s "${BATS_TEST_TMPDIR}/npx.log" ]
}

@test "valid approvers reach wrangler without a trailing newline" {
  run make -f "${MAKEFILE}" RELAY_DIR="${RELAY_DIR}" hermes-approvers APPROVERS='U0123ABCD,W0456EFGH'

  [ "${status}" -eq 0 ]
  [ "$(cat "${BATS_TEST_TMPDIR}/npx.stdin")" = 'U0123ABCD,W0456EFGH' ]
  [ "$(tail -c 1 "${BATS_TEST_TMPDIR}/npx.stdin" | wc -l)" -eq 0 ]
}

@test "hermes-approvals-kv binds the returned namespace id only once" {
  run make -f "${MAKEFILE}" RELAY_DIR="${RELAY_DIR}" hermes-approvals-kv
  [ "${status}" -eq 0 ]
  grep -q '^binding = "APPROVALS_KV"$' "${RELAY_DIR}/wrangler.toml"
  grep -q '^id = "0123456789abcdef0123456789abcdef"$' "${RELAY_DIR}/wrangler.toml"

  run make -f "${MAKEFILE}" RELAY_DIR="${RELAY_DIR}" hermes-approvals-kv
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"nothing to do"* ]]
  [ "$(grep -c '^argv:' "${BATS_TEST_TMPDIR}/npx.log")" -eq 1 ]
}

@test "hermes-approvals-setup rejects missing approvers before any stub" {
  run env -u APPROVERS make -f "${MAKEFILE}" RELAY_DIR="${RELAY_DIR}" hermes-approvals-setup

  [ "${status}" -ne 0 ]
  [ ! -s "${BATS_TEST_TMPDIR}/security.log" ]
  [ ! -s "${BATS_TEST_TMPDIR}/npx.log" ]
  [ ! -s "${BATS_TEST_TMPDIR}/openssl.log" ]
}

@test "hermes-approvals-kv reports a failed Cloudflare token read instead of exiting silently" {
  printf '#!/usr/bin/env bash\nexit 44\n' >"${BATS_TEST_TMPDIR}/bin/security"

  run make -f "${MAKEFILE}" RELAY_DIR="${RELAY_DIR}" hermes-approvals-kv </dev/null

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"k3dm-cloudflare-api-token missing"* ]]
}

@test "hermes-approvals-kv shows wrangler's output when namespace create fails" {
  printf '#!/usr/bin/env bash\necho "A namespace with this title already exists"\nexit 1\n' >"${BATS_TEST_TMPDIR}/bin/npx"

  run make -f "${MAKEFILE}" RELAY_DIR="${RELAY_DIR}" hermes-approvals-kv </dev/null

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"already exists"* ]]
  [[ "${output}" == *"wrangler kv namespace create failed"* ]]
}
