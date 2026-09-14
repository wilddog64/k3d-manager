#!/usr/bin/env bats

@test "no bare '! cmd' assertions in BATS suites (set -e ignores them)" {
  local tests_root="${BATS_TEST_DIRNAME}/.."
  run grep -rnE '^[[:space:]]*! ' "${tests_root}" --include='*.bats'
  [ "$status" -ne 0 ]
}
