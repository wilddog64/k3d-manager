#!/usr/bin/env bats

setup() {
  TEST_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export TEST_ROOT
  ALLOWLIST="${TEST_ROOT}/scripts/tests/fixtures/grep-q-pipe-allowlist.txt"
  export ALLOWLIST
}

_scan_grep_q_pipes() {
  grep -rnE '\| *grep +-[A-Za-z]*q' "$@" --exclude-dir=tests --exclude-dir=foundation --exclude-dir=node_modules | grep -v -F -f "$ALLOWLIST"
}

@test "grep-q guard: no non-allowlisted pipeline retains -q" {
  cd "${TEST_ROOT}"
  run _scan_grep_q_pipes scripts bin
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "grep-q guard: matching producer is read to EOF under pipefail" {
  run bash -c '
    set -o pipefail
    producer() {
      for ((i=0; i<20000; i++)); do printf "k3dm_release_forecast %s\\n" "$i"; done
    }
    producer | grep -x "k3dm_release_forecast 0" >/dev/null
  '
  [ "$status" -eq 0 ]
}

@test "grep-q guard: rejects a forbidden non-allowlisted fixture pipeline" {
  local fixture="$BATS_TEST_TMPDIR/fixture.sh"
  printf '%s\n' 'curl -fsS "$URL/metrics" | grep -q forecast' > "$fixture"
  run _scan_grep_q_pipes "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fixture.sh:1:"* ]]
}

@test "grep-q guard: standalone grep-q is not a forbidden pipeline" {
  printf '%s\n' 'grep -q forecast metrics.txt' > "$BATS_TEST_TMPDIR/fixture.sh"
  run _scan_grep_q_pipes "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "grep-q guard: draining pipeline is not forbidden" {
  printf '%s\n' 'curl -fsS "$URL/metrics" | grep forecast >/dev/null' > "$BATS_TEST_TMPDIR/fixture.sh"
  run _scan_grep_q_pipes "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}
