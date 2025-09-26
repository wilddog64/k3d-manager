#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
}

@test "_cleanup_on_success removes every provided path" {
  local tmp_dir tmp_file extra
  tmp_dir=$(mktemp -d -t cleanup-dir.XXXXXX)
  tmp_file=$(mktemp -t cleanup-file.XXXXXX)
  extra=""

  [[ -d "$tmp_dir" ]]
  [[ -f "$tmp_file" ]]

  _cleanup_on_success "$tmp_dir" "$tmp_file" "$extra"

  [[ ! -e "$tmp_dir" ]]
  [[ ! -e "$tmp_file" ]]
}
