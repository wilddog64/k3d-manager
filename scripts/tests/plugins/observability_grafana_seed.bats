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
