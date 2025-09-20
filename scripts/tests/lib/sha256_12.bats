#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
}

@test "_sha256_12 trims digest from argument" {
  run _sha256_12 "hello"
  [ "$status" -eq 0 ]
  [ "$output" = "2cf24dba5fb0" ]
}

@test "_sha256_12 reads from stdin when no argument" {
  run bash -c 'source "$1"; printf %s "hello" | _sha256_12' bash "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "2cf24dba5fb0" ]
}
