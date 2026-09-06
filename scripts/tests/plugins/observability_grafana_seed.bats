#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/observability.sh"
}

@test "_observability_seed_grafana_if_absent skips a present credential" {
  local calls="$BATS_TEST_TMPDIR/calls"
  _vault_exec() { return 0; }
  _vault_exec_stream() { printf 'write\n' >> "$calls"; }

  run _observability_seed_grafana_if_absent
  [ "$status" -eq 0 ]
  [ ! -e "$calls" ]
}

@test "_observability_seed_grafana_if_absent writes an absent credential once" {
  local calls="$BATS_TEST_TMPDIR/calls"
  _vault_exec() { return 1; }
  _vault_exec_stream() { printf 'write\n' >> "$calls"; }

  run _observability_seed_grafana_if_absent
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$calls")" -eq 1 ]
}

@test "observability_seed_grafana is a declared function" {
  declare -f observability_seed_grafana
}

@test "observability_seed_grafana logs in and delegates to the private seed" {
  local calls="$BATS_TEST_TMPDIR/calls"
  _vault_login() { printf 'login %s %s\n' "$1" "$2" >> "$calls"; }
  _observability_seed_grafana_if_absent() { printf 'seed %s %s\n' "$1" "$2" >> "$calls"; }

  run observability_seed_grafana secrets vault
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$calls")" = "login secrets vault" ]
  [ "$(sed -n '2p' "$calls")" = "seed secrets vault" ]
}
