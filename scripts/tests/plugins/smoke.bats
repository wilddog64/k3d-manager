#!/usr/bin/env bats

setup() {
  export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  export SCRIPT_DIR="$REPO_ROOT"
  export K3DM_TEST_BIN="$BATS_TEST_TMPDIR/bin"
  export SMOKE_BIN_DIR="$K3DM_TEST_BIN"
  export CALLS_LOG="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$K3DM_TEST_BIN"
  : > "$CALLS_LOG"
  cat > "$K3DM_TEST_BIN/smoke-test-webhook" <<'EOF'
#!/usr/bin/env bash
echo webhook >> "$CALLS_LOG"
exit "${WEBHOOK_RC:-0}"
EOF
  cat > "$K3DM_TEST_BIN/smoke-test-cluster-health" <<'EOF'
#!/usr/bin/env bash
echo cluster >> "$CALLS_LOG"
exit "${CLUSTER_RC:-0}"
EOF
  chmod +x "$K3DM_TEST_BIN"/*
  export PATH="$K3DM_TEST_BIN:$PATH"
  _kubectl() {
    return "${KUBECTL_RC:-0}"
  }
  _run_command() {
    shift
    "$@"
  }
  export -f _kubectl _run_command
  source "$REPO_ROOT/plugins/smoke.sh"
}

@test "smoke: all checks pass" {
  run smoke_run
  [ "$status" -eq 0 ]
  [ "$(grep -cE 'PASS' <<<"$output")" -eq 2 ]
  [ "$(grep -cE '^smoke: 2 passed, 0 failed, 0 skipped$' <<<"$output")" -eq 1 ]
}

@test "smoke: failing offline check fails" {
  WEBHOOK_RC=1 run smoke_run offline
  [ "$status" -ne 0 ]
  [[ "$output" == *"webhook         offline   FAIL"* ]]
  [[ "$output" == *"smoke: 0 passed, 1 failed, 0 skipped"* ]]
}

@test "smoke: unreachable context skips cluster" {
  KUBECTL_RC=1 run smoke_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"cluster-health  cluster   SKIP"* ]]
  [[ "$output" == *"unreachable"* ]]
}

@test "smoke: reachable failing cluster fails" {
  CLUSTER_RC=1 run smoke_run cluster
  [ "$status" -ne 0 ]
  [[ "$output" == *"cluster-health  cluster   FAIL"* ]]
}

@test "smoke: offline filter never invokes cluster" {
  run smoke_run offline
  [ "$status" -eq 0 ]
  run grep -F cluster "$CALLS_LOG"
  [ "$status" -ne 0 ]
}

@test "smoke: invalid filter prints usage" {
  run smoke_run bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: smoke_run"* ]]
}

@test "smoke: later checks run after a failure" {
  WEBHOOK_RC=1 run bash -c 'source "$SCRIPT_DIR/plugins/smoke.sh"; smoke_run'
  [ "$status" -ne 0 ]
  [[ "$output" == *"webhook         offline   FAIL"* ]]
  [[ "$output" == *"cluster-health  cluster   PASS"* ]]
}
