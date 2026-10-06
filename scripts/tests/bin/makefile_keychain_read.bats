#!/usr/bin/env bats

MAKEFILE="${BATS_TEST_DIRNAME}/../../../Makefile"

setup() {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat >"${BATS_TEST_TMPDIR}/bin/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "show-keychain-info" ]]; then
  if [[ "${KEYCHAIN_LOCKED:-0}" == 1 ]]; then
    echo 'security: SecKeychainCopySettings: User interaction is not allowed.' >&2
    exit 36
  fi
  exit 0
fi
if [[ "${1:-}" == "find-generic-password" ]]; then
  case "$*" in
    *k3dm-slack-signing-secret*)
      [[ "${SLACK_SECRET_MISSING:-0}" == 1 ]] && exit 44
      printf 'x\n' ;;
    *)
      [[ "${KEYCHAIN_LOCKED:-0}" == 1 ]] && exit 36
      printf 'x\n' ;;
  esac
fi
EOF
  cat >"${BATS_TEST_TMPDIR}/bin/npx" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${BATS_TEST_TMPDIR}/npx.calls"
exit 0
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/security" "${BATS_TEST_TMPDIR}/bin/npx"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

@test "missing signing secret names only the missing item" {
  run env SLACK_SECRET_MISSING=1 make -f "${MAKEFILE}" deploy-worker

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"k3dm-slack-signing-secret missing from Keychain — run bin/k3dm-worker-setup"* ]]
  [[ "${output}" != *"k3dm-cloudflare-api-token"* ]]
  [ ! -s "${BATS_TEST_TMPDIR}/npx.calls" ]
}

@test "locked keychain reports an unreadable item" {
  run env KEYCHAIN_LOCKED=1 make -f "${MAKEFILE}" deploy-worker

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"k3dm-cloudflare-api-token unreadable"* ]]
  [[ "${output}" == *"security unlock-keychain"* ]]
  [[ "${output}" != *"missing from Keychain"* ]]
}

@test "missing item never leaks a value" {
  run env SLACK_SECRET_MISSING=1 make -f "${MAKEFILE}" deploy-worker

  [ "${status}" -ne 0 ]
  run grep -Fx 'x' <<<"${output}"
  [ "${status}" -ne 0 ]
}

@test "all credential targets use the shared Keychain reader" {
  for target in deploy-worker hermes-approvals-kv hermes-drain-token hermes-approvers; do
    run awk -v target="${target}" '
      $0 == target ":" { in_target=1; next }
      in_target && /^$/ { exit }
      in_target { print }
    ' "${MAKEFILE}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"_kc_read k3dm-cloudflare-api-token"* ]]
  done

  run grep -F -- 'find-generic-password -s k3dm-cloudflare-api-token' "${MAKEFILE}"
  [ "${status}" -ne 0 ]
}
