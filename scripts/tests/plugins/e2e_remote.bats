#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/e2e_remote.sh"
}

# A healthy probe blob the pure evaluator should accept.
_healthy_blob() {
  printf '%s\n' \
    'docker_ok=1' 'lock=0' 'cpu_idle2=72.8' 'cpu_idle3=58.6' \
    'mem_free=45' 'disk_gb=153'
}

@test "public runner functions are dispatchable (no leading underscore)" {
  for fn in e2e_runner_bootstrap e2e_runner_preflight e2e_runner_status; do
    run declare -f "$fn"
    [ "$status" -eq 0 ]
    [[ "$fn" != _* ]]
  done
}

@test "e2e_remote.sh sources cleanly under set -euo pipefail" {
  run bash -c '
    set -euo pipefail
    _err(){ return 1; }; _info(){ :; }; _warn(){ :; }; _run_command(){ :; }
    source scripts/plugins/e2e_remote.sh
    declare -f e2e_runner_preflight >/dev/null
  '
  [ "$status" -eq 0 ]
}

@test "eval_gates accepts a healthy runner" {
  run _e2e_remote_eval_gates "$(_healthy_blob)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=available"* ]]
}

@test "eval_gates reports docker_down when Docker is unresponsive" {
  blob="$(printf '%s\n' docker_ok=0 lock=0 cpu_idle2=90 cpu_idle3=90 mem_free=90 disk_gb=900)"
  run _e2e_remote_eval_gates "$blob"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status=docker_down"* ]]
}

@test "eval_gates reports busy when the runner lock is held" {
  blob="$(printf '%s\n' docker_ok=1 lock=1 cpu_idle2=90 cpu_idle3=90 mem_free=90 disk_gb=900)"
  run _e2e_remote_eval_gates "$blob"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status=busy"* ]]
}

@test "eval_gates fails on low CPU idle in either sample" {
  blob="$(printf '%s\n' docker_ok=1 lock=0 cpu_idle2=80 cpu_idle3=20 mem_free=90 disk_gb=900)"
  run _e2e_remote_eval_gates "$blob"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status=capacity_cpu"* ]]
}

@test "eval_gates fails on low memory" {
  blob="$(printf '%s\n' docker_ok=1 lock=0 cpu_idle2=90 cpu_idle3=90 mem_free=10 disk_gb=900)"
  run _e2e_remote_eval_gates "$blob"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status=capacity_mem"* ]]
}

@test "eval_gates fails on low disk" {
  blob="$(printf '%s\n' docker_ok=1 lock=0 cpu_idle2=90 cpu_idle3=90 mem_free=90 disk_gb=10)"
  run _e2e_remote_eval_gates "$blob"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status=capacity_disk"* ]]
}

@test "eval_gates treats missing metrics as a capacity stop, not available" {
  blob="$(printf '%s\n' docker_ok=1 lock=0 mem_free=90 disk_gb=900)"
  run _e2e_remote_eval_gates "$blob"
  [ "$status" -ne 0 ]
  [[ "$output" != *"status=available"* ]]
}

@test "num_lt compares decimals" {
  run _e2e_num_lt 34.9 35
  [ "$status" -eq 0 ]
  run _e2e_num_lt 35.1 35
  [ "$status" -ne 0 ]
}

@test "SSH options never weaken host verification and keep BatchMode" {
  run _e2e_remote_ssh_opts
  [[ "$output" == *"BatchMode=yes"* ]]
  [[ "$output" != *"StrictHostKeyChecking=no"* ]]
  [[ "$output" != *"UserKnownHostsFile"* ]]
}

@test "remote SSH command injects the homebrew+local PATH so tools resolve" {
  run cat scripts/plugins/e2e_remote.sh
  [[ "$output" == *"/opt/homebrew/bin:/usr/local/bin"* ]]
  [[ "$output" == *'export PATH='* ]]
}

@test "preflight reports unreachable when the probe yields nothing" {
  _e2e_remote_probe() { return 1; }
  run e2e_runner_preflight
  [ "$status" -ne 0 ]
  [[ "$output" == *"status=unreachable"* ]]
}

@test "preflight surfaces the pure gate verdict from a live probe" {
  _e2e_remote_probe() { _healthy_blob; }
  run e2e_runner_preflight
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=available"* ]]
}

@test "cluster reconcile refuses to operate on the hub cluster name" {
  E2E_M2_RUNNER_CLUSTER="k3d-cluster"
  _e2e_remote_ssh() { return 1; }
  run _e2e_remote_reconcile_cluster
  [ "$status" -ne 0 ]
  [[ "$output" == *"hub cluster"* ]]
}

@test "cluster reconcile targets the dedicated runner context, never the hub" {
  run grep -F -- 'k3d-${E2E_M2_RUNNER_CLUSTER}' scripts/plugins/e2e_remote.sh
  [ "$status" -eq 0 ]
  run grep -F -- 'k3d cluster create ${E2E_M2_RUNNER_CLUSTER}' scripts/plugins/e2e_remote.sh
  [ "$status" -eq 0 ]
}

@test "bootstrap returns unreachable without mutating when SSH is down" {
  _e2e_remote_ssh() { return 1; }
  run e2e_runner_bootstrap
  [ "$status" -ne 0 ]
  [[ "$output" == *"status=unreachable"* ]]
}

# --- Remote dispatch (increment 4) -----------------------------------------

@test "valid_digest accepts empty, bare, and repo-qualified sha256 digests" {
  local hex="0000000000000000000000000000000000000000000000000000000000000000"
  run _e2e_valid_digest ""; [ "$status" -eq 0 ]
  run _e2e_valid_digest "sha256:${hex}"; [ "$status" -eq 0 ]
  run _e2e_valid_digest "ghcr.io/wilddog64/product-catalog@sha256:${hex}"; [ "$status" -eq 0 ]
}

@test "valid_digest rejects malformed or injection-y digests" {
  run _e2e_valid_digest "sha256:short"; [ "$status" -ne 0 ]
  run _e2e_valid_digest "latest"; [ "$status" -ne 0 ]
  run _e2e_valid_digest "sha256:0000; rm -rf /"; [ "$status" -ne 0 ]
  run _e2e_valid_digest 'sha256:$(whoami)'; [ "$status" -ne 0 ]
}

@test "runner_allowed enforces the allowlist" {
  run _e2e_runner_allowed "m2"; [ "$status" -eq 0 ]
  run _e2e_runner_allowed "local-m4"; [ "$status" -ne 0 ]
  run _e2e_runner_allowed "; ssh evil"; [ "$status" -ne 0 ]
}

@test "dispatch rejects a runner outside the allowlist" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
  run e2e_runner_dispatch "local-m4"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not in allowlist"* ]]
}

@test "dispatch rejects an invalid digest" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
  run e2e_runner_dispatch "m2" "not-a-digest"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid DIGEST"* ]]
}

@test "dispatch refuses to run and never falls back locally when preflight fails" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
  e2e_runner_preflight() { printf 'status=busy\n'; return 1; }
  ssh() { echo "SSH SHOULD NOT RUN" >&2; return 0; }
  run e2e_runner_dispatch "m2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status=busy"* ]]
  [[ "$output" == *"no local fallback"* ]]
  [[ "$output" != *"SSH SHOULD NOT RUN"* ]]
}

@test "dispatch builds the correct remote command and records a transcript" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
  local hex="0000000000000000000000000000000000000000000000000000000000000000"
  e2e_runner_preflight() { printf 'status=available\n'; return 0; }
  SSH_LOG="$BATS_TEST_TMPDIR/ssh.log"
  ssh() { printf '%s\n' "$*" > "$SSH_LOG"; echo "remote stdout"; return 0; }
  run e2e_runner_dispatch "m2" "sha256:${hex}"
  [ "$status" -eq 0 ]
  run cat "$SSH_LOG"
  [[ "$output" == *"e2e_verify_vcluster sha256:${hex}"* ]]
  [[ "$output" == *"E2E_RUNNER=m2"* ]]
  [[ "$output" == *"KUBECONFIG="* ]]
  [[ "$output" == *"e2e-runner.yaml"* ]]
  run bash -c 'ls "$1"/dispatch/m2-*.log' "" "$E2E_REPORT_DIR"
  [ "$status" -eq 0 ]
}

@test "dispatch returns the remote exit code unchanged" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
  e2e_runner_preflight() { printf 'status=available\n'; return 0; }
  ssh() { echo "remote failed"; return 7; }
  run e2e_runner_dispatch "m2"
  [ "$status" -eq 7 ]
}

@test "make e2e-remote requires RUNNER and wires to the dispatcher" {
  run grep -F -- 'e2e_runner_dispatch $(RUNNER) $(DIGEST)' Makefile
  [ "$status" -eq 0 ]
  run grep -F -- 'usage: make e2e-remote RUNNER=m2' Makefile
  [ "$status" -eq 0 ]
}
