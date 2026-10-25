#!/usr/bin/env bats
# shellcheck disable=SC1090,SC1091,SC2089,SC2090,SC2329

setup() {
  bats_require_minimum_version 1.5.0
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
  PLUGINS_DIR="${SCRIPT_DIR}/plugins"
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/core.sh"
  # VAULT_PLUGIN permits running this suite against a temporary pre-fix copy.
  # shellcheck disable=SC1090
  source "${VAULT_PLUGIN:-${PLUGINS_DIR}/vault.sh}"

  CALL_LOG="${BATS_TEST_TMPDIR}/vault-calls.log"
  : >"$CALL_LOG"
  VAULT_STATUS_JSON='{"initialized":true,"sealed":true}'
  REPLAY_RC=42
  ROOT_SECRET_PRESENT=1
  export CALL_LOG VAULT_STATUS_JSON REPLAY_RC ROOT_SECRET_PRESENT

  _dry_run_active() { return 1; }
  _is_vault_deployed() { return 0; }
  _vault_exec() { printf '%s\n' "$VAULT_STATUS_JSON"; }
  _vault_cache_unseal_from_secret() { echo cache >>"$CALL_LOG"; return 0; }
  _vault_replay_cached_unseal() { return "$REPLAY_RC"; }
  _vault_login() { echo login >>"$CALL_LOG"; }
  _kubectl() {
    echo "kubectl $*" >>"$CALL_LOG"
    [[ "$*" == *"get secret vault-root"* ]] && return "$((1 - ROOT_SECRET_PRESENT))"
    return 0
  }
  _vault_reinit_from_reset() { echo reinit >>"$CALL_LOG"; }
  _vault_purge_unseal_cache() { echo purge >>"$CALL_LOG"; }
  _vault_reset_data_path() { echo reset >>"$CALL_LOG"; }
  _warn() { printf '%s\n' "$*" >&2; }
  _info() { :; }
  export -f _dry_run_active _is_vault_deployed _vault_exec
  export -f _vault_cache_unseal_from_secret _vault_replay_cached_unseal _vault_login
  export -f _kubectl _vault_reinit_from_reset _vault_purge_unseal_cache _vault_reset_data_path
  export -f _warn _info
}

@test "sealed initialized Vault with rejected cache refuses destructive reinit" {
  REPLAY_RC=42
  run _vault_bootstrap_ha secrets vault
  [ "$status" -ne 0 ]
  [[ "$output" == *"hub_data_unseal_dr"* ]]
  [[ "$output" == *"Nothing was changed"* ]]
  run ! grep -Eq '^(reinit|purge|reset)$' "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "sealed initialized Vault with missing cache refuses destructive reinit" {
  REPLAY_RC=43
  run _vault_bootstrap_ha secrets vault
  [ "$status" -ne 0 ]
  [[ "$output" == *"hub_data_unseal_dr"* ]]
  run ! grep -Eq '^(reinit|purge|reset)$' "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "unsealed initialized Vault without root Secret refuses reset" {
  VAULT_STATUS_JSON='{"initialized":true,"sealed":false}'
  ROOT_SECRET_PRESENT=0
  run _vault_bootstrap_ha secrets vault
  [ "$status" -ne 0 ]
  [[ "$output" == *"generate-root"* ]]
  [[ "$output" == *"nothing was changed"* ]]
  run ! grep -Eq '^(reinit|purge|reset)$' "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "exact opt-in permits rejected cache reinitialization" {
  REPLAY_RC=42
  K3DM_VAULT_ALLOW_REINIT=1 run _vault_bootstrap_ha secrets vault
  [ "$status" -eq 0 ]
  grep -qx reinit "$CALL_LOG"
}

@test "non-exact opt-in does not permit reinitialization" {
  REPLAY_RC=42
  K3DM_VAULT_ALLOW_REINIT=true run _vault_bootstrap_ha secrets vault
  [ "$status" -ne 0 ]
  run ! grep -qx reinit "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "reset failure preserves unseal cache and Secrets" {
  # Restore the production implementation after setup's call recorder stub.
  source "${VAULT_PLUGIN:-${PLUGINS_DIR}/vault.sh}"
  _vault_reset_data_path() { echo reset >>"$CALL_LOG"; return 1; }
  _vault_purge_unseal_cache() { echo purge >>"$CALL_LOG"; }
  _vault_restart_pod() { echo restart >>"$CALL_LOG"; }
  _vault_operator_init() { echo init >>"$CALL_LOG"; }
  export -f _vault_reset_data_path _vault_purge_unseal_cache _vault_restart_pod _vault_operator_init
  run _vault_reinit_from_reset secrets vault
  [ "$status" -ne 0 ]
  grep -qx reset "$CALL_LOG"
  run ! grep -Eq '^(purge|restart|init)$' "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "unreachable host data path fails without moving or creating anything" {
  # Restore the production implementation after setup's call recorder stub.
  source "${VAULT_PLUGIN:-${PLUGINS_DIR}/vault.sh}"
  local missing_path="${BATS_TEST_TMPDIR}/missing-vault_data-not-present"
  _vault_resolve_data_path() { printf '%s\n' "$missing_path"; }
  _run_command() { echo "$*" >>"$CALL_LOG"; }
  export -f _vault_resolve_data_path _run_command
  run _vault_reset_data_path secrets vault
  [ "$status" -ne 0 ]
  [[ "$output" == *"not reachable from this host"* ]]
  run ! grep -Eq '(^| )(mv|mkdir)( |$)' "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "successful cached unseal still logs in" {
  REPLAY_RC=0
  run _vault_bootstrap_ha secrets vault
  [ "$status" -eq 0 ]
  grep -qx login "$CALL_LOG"
}
