#!/usr/bin/env bats

setup() {
  export E2E_RUNNER_LOCK="$BATS_TEST_TMPDIR/runner.lock"
  export CI_RUNNER_LOCK_INTERVAL=0.05
  export CI_RUNNER_LOCK_WAIT=1
  export GITHUB_RUN_ID=12345
  export GITHUB_RUN_ATTEMPT=2
  LOCK_SCRIPT="${RUNNER_LOCK_SCRIPT:-${BATS_TEST_DIRNAME}/../../ci/runner_lock.sh}"
}

@test "CI runner lock: acquire records and prints its ownership token" {
  run bash "$LOCK_SCRIPT" acquire
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^owner=ci-12345-2\ pid=[0-9]+\ ts=[0-9]+$ ]]
  [ -d "$E2E_RUNNER_LOCK" ]
  [ "$(cat "$E2E_RUNNER_LOCK/meta")" = "$output" ]
}

@test "CI runner lock: acquire waits for the current holder to release" {
  mkdir -p "$E2E_RUNNER_LOCK"
  printf 'owner=e2e pid=7 ts=8\n' > "$E2E_RUNNER_LOCK/meta"
  ( sleep 0.1; rm -rf "$E2E_RUNNER_LOCK" ) &
  run bash "$LOCK_SCRIPT" acquire
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^owner=ci-12345-2\ pid=[0-9]+\ ts=[0-9]+$ ]]
}

@test "CI runner lock: held lock times out without changing holder metadata" {
  mkdir -p "$E2E_RUNNER_LOCK"
  printf 'owner=e2e pid=7 ts=8\n' > "$E2E_RUNNER_LOCK/meta"
  run bash "$LOCK_SCRIPT" acquire
  [ "$status" -ne 0 ]
  [[ "$output" == *"runner busy: owner=e2e pid=7 ts=8"* ]]
  [ -d "$E2E_RUNNER_LOCK" ]
  [ "$(cat "$E2E_RUNNER_LOCK/meta")" = 'owner=e2e pid=7 ts=8' ]
}

@test "CI runner lock: release removes only a lock with matching metadata" {
  mkdir -p "$E2E_RUNNER_LOCK"
  printf 'owner=ci-12345-2 pid=9 ts=10\n' > "$E2E_RUNNER_LOCK/meta"
  run bash "$LOCK_SCRIPT" release 'owner=ci-12345-2 pid=9 ts=10'
  [ "$status" -eq 0 ]
  [ ! -e "$E2E_RUNNER_LOCK" ]
  mkdir -p "$E2E_RUNNER_LOCK"
  printf 'owner=e2e pid=7 ts=8\n' > "$E2E_RUNNER_LOCK/meta"
  run bash "$LOCK_SCRIPT" release 'owner=ci-12345-2 pid=9 ts=10'
  [ "$status" -eq 0 ]
  [ -d "$E2E_RUNNER_LOCK" ]
}

@test "CI runner lock: concurrent acquires serialize ownership" {
  bash "$LOCK_SCRIPT" acquire > "$BATS_TEST_TMPDIR/one" & p1=$!
  bash "$LOCK_SCRIPT" acquire > "$BATS_TEST_TMPDIR/two" & p2=$!
  if wait "$p1"; then rc1=0; else rc1=$?; fi
  if wait "$p2"; then rc2=0; else rc2=$?; fi
  [ $(( (rc1 == 0) + (rc2 == 0) )) -eq 1 ]
}

@test "CI runner lock: invalid usage exits 2" {
  run bash "$LOCK_SCRIPT" nope
  [ "$status" -eq 2 ]
  run bash "$LOCK_SCRIPT" release
  [ "$status" -eq 2 ]
}

@test "CI workflow: stage2 guards cluster tests with the shared runner lock" {
  run python3 - "${CI_WORKFLOW_PATH:-${BATS_TEST_DIRNAME}/../../../.github/workflows/ci.yml}" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
stage = re.search(r"(?ms)^  stage2:\n(.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)", text)
assert stage, "stage2 job missing"
job = stage.group(1)
assert re.search(r"(?m)^    timeout-minutes: (?:[1-9][0-9]?|1[01][0-9])\s*$", job), "stage2 timeout must be <=119"
acquire = job.index("name: Acquire M2 runner lock")
health = job.index("name: Cluster health check")
tests = job.index("name: Run integration tests")
assert acquire < health < tests, "lock acquisition must precede health and tests"
assert "id: runner_lock" in job[acquire:health]
release = job.index("name: Release M2 runner lock")
release_block = job[release:]
assert "if: ${{ always() && steps.runner_lock.outputs.token != '' }}" in release_block
assert re.search(r"(?m)^\s+TOKEN: \$\{\{ steps\.runner_lock\.outputs\.token \}\}$", release_block)
assert 'scripts/ci/runner_lock.sh release "$TOKEN"' in release_block
assert "GITHUB_OUTPUT" in job[acquire:health] and "token=" in job[acquire:health]
assert "set -euo pipefail" in job[acquire:health]
PY
  [ "$status" -eq 0 ]
}
