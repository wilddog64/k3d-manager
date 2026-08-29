#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
  source "${BATS_TEST_DIRNAME}/../plugins/observability.sh"
}

@test "layer normalizer: 1 stays 1" {
  run _observability_normalize_layer 1
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "layer normalizer: 2 stays 2" {
  run _observability_normalize_layer 2
  [ "${status}" -eq 0 ]
  [ "${output}" = "2" ]
}

@test "layer normalizer: empty defaults to 2" {
  run _observability_normalize_layer ""
  [ "${status}" -eq 0 ]
  [ "${output}" = "2" ]
}

@test "layer normalizer: 9 defaults to 2" {
  run _observability_normalize_layer 9
  [ "${status}" -eq 0 ]
  [ "${output}" = "2" ]
}

@test "layer normalizer: foo defaults to 2" {
  run _observability_normalize_layer foo
  [ "${status}" -eq 0 ]
  [ "${output}" = "2" ]
}
