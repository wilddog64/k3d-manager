#!/usr/bin/env bats

MAKEFILE="${BATS_TEST_DIRNAME}/../../../Makefile"
REPO_ROOT="${BATS_TEST_DIRNAME}/../../.."

setup() {
  WORK="${BATS_TEST_TMPDIR}/work"
  STUB="${BATS_TEST_TMPDIR}/stub"
  GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
  mkdir -p "${WORK}/.github/workflows" "${STUB}"
  cp "${MAKEFILE}" "${WORK}/Makefile"
  cp "${REPO_ROOT}"/.github/workflows/*.yml "${WORK}/.github/workflows/"
  cp "${REPO_ROOT}"/.github/workflows/*.yaml "${WORK}/.github/workflows/" 2>/dev/null || true
  : > "${GH_LOG}"
  cat > "${STUB}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ARGS:' >> "${GH_LOG}"
printf ' <%s>' "$@" >> "${GH_LOG}"
printf '\n' >> "${GH_LOG}"
if [[ "${1:-}" == secret && "${2:-}" == list ]]; then
  cat <<'LIST'
AAA_TYPO_SECRET	2026-09-25T00:00:00Z
CLOUDFLARE_API_TOKEN	2026-09-30T00:00:00Z
COPILOT_TOKEN	2026-09-29T00:00:00Z
K3DM_WEBHOOK_TOKEN	2026-09-28T00:00:00Z
SLACK_SIGNING_SECRET	2026-09-27T00:00:00Z
SLACK_SIGING_SECRET	2026-09-26T00:00:00Z
LIST
  exit 0
fi
if [[ "${1:-}" == secret && "${2:-}" == set ]]; then
  if [[ "${GH_STUB_READ_STDIN:-0}" == 1 ]]; then
    printf 'STDIN:%s\n' "$(cat)" >> "${GH_LOG}"
  fi
  exit 0
fi
exit 2
EOF
  cat > "${STUB}/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *" -s k3dm-webhook-token "*) printf '%s' "${SECURITY_WEBHOOK_VALUE-webhook-secret}" ;;
  *" -s k3dm-slack-signing-secret "*) printf '%s' "${SECURITY_SIGNING_VALUE-signing-secret}" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "${STUB}/gh" "${STUB}/security"
}

_run_make() {
  run env PATH="${STUB}:${PATH}" GH_LOG="${GH_LOG}" make --no-print-directory -C "${WORK}" "$@"
}

@test "no NAME lists all workflow secrets and flags an unused repo secret" {
  _run_make gh-secret
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"CLOUDFLARE_API_TOKEN"* ]]
  [[ "${output}" == *"COPILOT_TOKEN"* ]]
  [[ "${output}" == *"K3DM_WEBHOOK_TOKEN"* ]]
  [[ "${output}" == *"SLACK_SIGNING_SECRET"* ]]
  [[ "${output}" == *"SLACK_SIGING_SECRET unused (typo?)"* ]]
  [[ "${output}" == *"AAA_TYPO_SECRET unused (typo?)"* ]]
  [[ "${output}" == *"SLACK_SIGNING_SECRET 2026-09-27T00:00:00Z"* ]]
}

@test "a secret name outside the allowlist is rejected without secret set" {
  _run_make gh-secret NAME=SLACK_SIGING_SECRET
  [ "${status}" -ne 0 ]
  run grep -F 'ARGS: <secret> <set>' "${GH_LOG}"
  [ "${status}" -ne 0 ]
}

@test "an allowed secret is set interactively without a body argument" {
  _run_make gh-secret NAME=SLACK_SIGNING_SECRET
  [ "${status}" -eq 0 ]
  grep -Fq 'ARGS: <secret> <set> <SLACK_SIGNING_SECRET> <--repo> <wilddog64/k3d-manager>' "${GH_LOG}"
  run grep -Eq -- '--body|-b' "${GH_LOG}"
  [ "${status}" -ne 0 ]
}

@test "the allowlist includes new names added to a temporary workflow copy" {
  cat > "${WORK}/.github/workflows/temporary.yml" <<'EOF'

name: test
jobs:
  test:
    env:
      TOKEN: ${{ secrets.FOO_BAR }}
EOF
  _run_make gh-secret NAME=FOO_BAR
  [ "${status}" -eq 0 ]
  grep -Fq 'ARGS: <secret> <set> <FOO_BAR>' "${GH_LOG}"
}

@test "relay sync sends both Keychain values on stdin and never in argv" {
  run env PATH="${STUB}:${PATH}" GH_LOG="${GH_LOG}" GH_STUB_READ_STDIN=1 make --no-print-directory -C "${WORK}" gh-secret-sync-relay
  [ "${status}" -eq 0 ]
  grep -Fq 'ARGS: <secret> <set> <K3DM_WEBHOOK_TOKEN> <--repo> <wilddog64/k3d-manager>' "${GH_LOG}"
  grep -Fq 'ARGS: <secret> <set> <SLACK_SIGNING_SECRET> <--repo> <wilddog64/k3d-manager>' "${GH_LOG}"
  grep -Fq 'STDIN:webhook-secret' "${GH_LOG}"
  grep -Fq 'STDIN:signing-secret' "${GH_LOG}"
  run grep -E 'ARGS:.*webhook-secret' "${GH_LOG}"
  [ "${status}" -ne 0 ]
  run grep -E 'ARGS:.*signing-secret' "${GH_LOG}"
  [ "${status}" -ne 0 ]
}

@test "an empty Keychain item prevents every GitHub secret set" {
  run env PATH="${STUB}:${PATH}" GH_LOG="${GH_LOG}" SECURITY_SIGNING_VALUE= make --no-print-directory -C "${WORK}" gh-secret-sync-relay
  [ "${status}" -ne 0 ]
  run grep -F 'ARGS: <secret> <set>' "${GH_LOG}"
  [ "${status}" -ne 0 ]
}
