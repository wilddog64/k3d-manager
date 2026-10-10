#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
  PLUGINS_DIR="${SCRIPT_DIR}/plugins"
  source "${SCRIPT_DIR}/lib/core.sh"
  source "${BATS_TEST_DIRNAME}/../../plugins/vault.sh"
  export VAULT_NS_DEFAULT=secrets VAULT_RELEASE_DEFAULT=vault
  export STORE_LOG="$BATS_TEST_TMPDIR/store.log" CLEAR_LOG="$BATS_TEST_TMPDIR/clear.log"
  : > "$STORE_LOG"; : > "$CLEAR_LOG"
  declare -gA FAKE_SECRET=()
  _vault_collect_unseal_shards_from_secret() { printf '%s\n' SHARD-SENTINEL-1 SHARD-SENTINEL-2; }
  _secret_load_data() { printf '%s' "${FAKE_SECRET["$1|$2"]:-}"; [[ -n "${FAKE_SECRET["$1|$2"]:-}" ]]; }
  _secret_store_data() { FAKE_SECRET["$1|$2"]="$3"; printf '%s|%s\n' "$1" "$2" >> "$STORE_LOG"; printf '%s' "$3" > "$BATS_TEST_TMPDIR/value-$(printf '%s' "$2" | tr /: __)"; }
  _secret_clear_data() { printf '%s|%s\n' "$1" "$2" >> "$CLEAR_LOG"; }
  _warn() { printf '%s\n' "$*" >&2; }
  _info() { :; }
}

@test "vault DR shards: save stores two shards under secrets/vault without exposing values" {
  vault_dr_shards_save
  [ "$(cat "$BATS_TEST_TMPDIR/value-secrets_vault_count")" = 2 ]
  [ "$(cat "$BATS_TEST_TMPDIR/value-secrets_vault_shard1")" = SHARD-SENTINEL-1 ]
  [ "$(cat "$BATS_TEST_TMPDIR/value-secrets_vault_shard2")" = SHARD-SENTINEL-2 ]
}

@test "vault DR shards: export and import round-trip through stdin" {
  FAKE_SECRET['k3dm-vault-unseal-dr|secrets/vault:count']=2
  FAKE_SECRET['k3dm-vault-unseal-dr|secrets/vault:shard1']=SHARD-SENTINEL-1
  FAKE_SECRET['k3dm-vault-unseal-dr|secrets/vault:shard2']=SHARD-SENTINEL-2
  vault_dr_shards_export | vault_dr_shards_import secrets/vault
  [ "$(grep -c 'secrets/vault:shard' "$STORE_LOG" || true)" -ge 2 ]
}

@test "vault DR shards: export refuses a terminal" {
  export VAULT_DR_SHARDS_TEST_TTY=1
  run vault_dr_shards_export
  [ "$status" -eq 2 ]
  [[ "$output$stderr" != *SHARD-SENTINEL* ]]
}

@test "vault DR shards: drill init does not save durable shards" {
  vault_dr_shards_save() { printf called >> "$BATS_TEST_TMPDIR/save-called"; }
  printf '%s\n' '{"root_token":"root","key_shares":2,"key_threshold":1,"unseal_keys_b64":[]}' > "$BATS_TEST_TMPDIR/init.json"
  _kubectl() { [[ "$*" == *'get pod '* ]] && printf ''; }
  _no_trace() { :; }
  _vault_cache_unseal_keys() { :; }
  _is_vault_health() { return 0; }
  export DR_DRILL_MODE=1
  run _vault_process_init_artifacts secrets vault "$BATS_TEST_TMPDIR/init.json"
  [ ! -e "$BATS_TEST_TMPDIR/save-called" ]
  unset DR_DRILL_MODE
  _vault_process_init_artifacts secrets vault "$BATS_TEST_TMPDIR/init.json" || true
  [ -e "$BATS_TEST_TMPDIR/save-called" ]
}

@test "vault DR shards: normal cache clear does not clear durable service" {
  _vault_clear_cached_shards k3dm-manager-vault-unseal secrets/vault vault-unseal 2
  grep -q 'k3dm-manager-vault-unseal|secrets/vault:count' "$CLEAR_LOG"
  [ "$(grep -c 'k3dm-vault-unseal-dr' "$CLEAR_LOG" || true)" -eq 0 ]
}
