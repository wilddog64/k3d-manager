#!/usr/bin/env bats

MAKEFILE="${BATS_TEST_DIRNAME}/../../../Makefile"

setup() {
  RECIPE="$(awk '/^argocd-hermes-token:/,/^$/' "${MAKEFILE}")"
}

@test "argocd-hermes-token is declared phony" {
  run awk '/^\.PHONY:/,/^$/' "${MAKEFILE}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"argocd-hermes-token"* ]]
}

@test "the target refuses to run without a terminal" {
  [[ "${RECIPE}" == *'[ -t 0 ]'* ]]
  [[ "${RECIPE}" == *"must not run unattended"* ]]
}

@test "the minted token is never echoed" {
  case "${RECIPE}" in
    *'echo "$$_tok"'*|*'echo $$_tok'*|*'echo "$$_stored"'*|*'echo $$_stored'*)
      printf 'The recipe echoes the token value.\n' >&2
      printf 'An ArgoCD API token must never reach terminal output or a log.\n' >&2
      return 1 ;;
  esac
}

@test "secrets reach python through the environment, never argv" {
  [[ "${RECIPE}" == *'ARGOCD_ADMIN_PW="$$_pw" python3'* ]]
  [[ "${RECIPE}" == *'ARGOCD_TOKEN="$$_stored" python3'* ]]

  [[ "${RECIPE}" == *'os.environ["ARGOCD_ADMIN_PW"]'* ]]
  [[ "${RECIPE}" != *'"password":"$$_pw"'* ]]
}

@test "admin password sources prefer env, then Vault, then the initial secret" {
  local env_line vault_line initial_line
  env_line="$(printf '%s\n' "${RECIPE}" | grep -nF '_pw="$${ARGOCD_ADMIN_PASSWORD:-}"' | cut -d: -f1)"
  vault_line="$(printf '%s\n' "${RECIPE}" | grep -nF 'v1/secret/data/argocd/admin' | cut -d: -f1)"
  initial_line="$(printf '%s\n' "${RECIPE}" | grep -nF 'argocd-initial-admin-secret' | tail -1 | cut -d: -f1)"
  [ -n "${env_line}" ] && [ -n "${vault_line}" ] && [ -n "${initial_line}" ]
  [ "${env_line}" -lt "${vault_line}" ]
  [ "${vault_line}" -lt "${initial_line}" ]
  [[ "${RECIPE}" == *"vault-root"* ]]
}

@test "Vault token and password are not printed or interpolated into command arguments" {
  case "${RECIPE}" in
    *'echo "$$_vault_tok"'*|*'echo $$_vault_tok'*|*'echo "$$_pw"'*|*'echo $$_pw'*)
      printf 'A Vault token or admin password is echoed.\n' >&2
      return 1 ;;
  esac
  [[ "${RECIPE}" == *'"$$_vault_tok" >"$$_vault_hdr"'* ]]
  [[ "${RECIPE}" == *'ARGOCD_ADMIN_PW="$$_pw" python3'* ]]
}

@test "the stored value is read back before the target reports success" {
  [[ "${RECIPE}" == *'_stored=$$(security find-generic-password'* ]]
  [[ "${RECIPE}" == *"reads back empty"* ]]
}

@test "the Keychain item is updated in place, preserving its ACL" {
  [[ "${RECIPE}" == *'security add-generic-password -U -a k3dm -s k3dm-hermes-argocd-token'* ]]

  case "${RECIPE}" in
    *'security delete-generic-password'*)
      printf 'The recipe deletes the Keychain item instead of updating it.\n' >&2
      printf 'A recreated item gets a default ACL, so a non-interactive launchd read\n' >&2
      printf 'can prompt for authorization and Hermes then fails silently.\n' >&2
      return 1 ;;
  esac
}

@test "TLS verification is never disabled" {
  case "${RECIPE}" in
    *--insecure*|*_create_unverified_context*|*CERT_NONE*|*"check_hostname = False"*)
      printf 'The recipe disables TLS verification against a public endpoint.\n' >&2
      return 1 ;;
  esac

  [[ "${RECIPE}" == *"https://%s/api/v1/session"* ]]
}

@test "the token is proven against the endpoint before the target succeeds" {
  [[ "${RECIPE}" == *"/api/v1/applications"* ]]
  [[ "${RECIPE}" == *"applications visible to hermes"* ]]
}

@test "both API calls set an explicit User-Agent" {
  case "${RECIPE}" in
    *'User-Agent'*) ;;
    *)
      printf 'The recipe sends no User-Agent header.\n' >&2
      printf 'urllib defaults to "Python-urllib/<ver>", which Cloudflare rejects with\n' >&2
      printf 'HTTP 403 "error code: 1010" before the request reaches ArgoCD — a failure\n' >&2
      printf 'that reads as an authz problem and sends the operator after the wrong cause.\n' >&2
      return 1 ;;
  esac

  _ua_count="$(printf '%s' "${RECIPE}" | command grep -c 'User-Agent' || true)"
  [ "${_ua_count}" -ge 2 ]
}

@test "expiresIn is sent as a JSON integer, not a string" {
  case "${RECIPE}" in
    *'"expiresIn":"'*)
      printf 'expiresIn is quoted, making it a JSON string.\n' >&2
      printf 'The ArgoCD swagger types it as integer/int64, so a quoted value fails to\n' >&2
      printf 'unmarshal and the API returns HTTP 400 before any ArgoCD logic runs.\n' >&2
      return 1 ;;
  esac

  [[ "${RECIPE}" == *'"expiresIn":0'* ]]
}
