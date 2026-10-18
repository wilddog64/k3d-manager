#!/usr/bin/env bats

setup() {
  TEST_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export TEST_ROOT
  ALLOWLIST="${TEST_ROOT}/scripts/tests/fixtures/grep-q-pipe-allowlist.txt"
  export ALLOWLIST
}

@test "grep-q guard: no non-allowlisted pipeline retains -q" {
  cd "${TEST_ROOT}"
  run bash -c 'grep -rnE '\''\| *grep +-[A-Za-z]*q'\'' scripts bin --exclude-dir=tests --exclude-dir=foundation --exclude-dir=node_modules | grep -v -F -f "$ALLOWLIST"'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "grep-q guard: matching producer is read to EOF under pipefail" {
  run bash -c '
    set -o pipefail
    producer() {
      printf "%s\\n" match
      sleep 0.3
      printf "%s\\n" trailing
    }
    for iteration in 1 2 3 4 5; do
      producer | grep -x match >/dev/null
    done
  '
  [ "$status" -eq 0 ]
}
