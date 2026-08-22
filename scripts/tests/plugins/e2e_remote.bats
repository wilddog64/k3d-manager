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
  for fn in e2e_runner_bootstrap e2e_runner_preflight e2e_runner_status \
            e2e_runner_dispatch e2e_result_publish e2e_result_publisher_install; do
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

# --- Restricted result publication (increment 5) ---------------------------

_valid_payload() {
  local hex="1111111111111111111111111111111111111111111111111111111111111111"
  cat <<JSON
{"run_id":"20260822T010101Z-abc123","tier":"vcluster","runner":"m2",
 "service":"product-catalog","project":"api+flows",
 "candidate_digest":"ghcr.io/wilddog64/product-catalog@sha256:${hex}",
 "passed":42,"total":42,"failed":0,"duration_seconds":12.5,
 "timestamp":"2026-08-22T01:01:01+00:00","commit":"deadbeef",
 "exit_code":0,"phase":"complete","result":"pass"}
JSON
}

@test "publish_build accepts a valid m2 payload and emits a deterministic name" {
  local inf="$BATS_TEST_TMPDIR/in.json" outf="$BATS_TEST_TMPDIR/cm.json"
  _valid_payload > "$inf"
  run _e2e_publish_build "$inf" "$outf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"runner=m2"* ]]
  [[ "$output" == *"result=pass"* ]]
  [[ "$output" == *"service=product-catalog"* ]]
  # deterministic: same run_id -> same resource name
  local n1 n2
  n1="$(sed -n 's/name=\([^ ]*\).*/\1/p' <<<"$output")"
  run _e2e_publish_build "$inf" "$outf"
  n2="$(sed -n 's/name=\([^ ]*\).*/\1/p' <<<"$output")"
  [ "$n1" = "$n2" ]
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["kind"]=="ConfigMap"; assert d["metadata"]["namespace"]=="platform-ops"; assert d["metadata"]["labels"]["k3dm.k3d.io/e2e-runner"]=="m2"; print("ok")' "$outf"
  [ "$status" -eq 0 ]
}

@test "publish_build accepts a real null-heavy summary (no digest, unparsed results)" {
  local inf="$BATS_TEST_TMPDIR/in.json" outf="$BATS_TEST_TMPDIR/cm.json"
  # Mirrors _e2e_write_summary output when no DIGEST is set and Playwright
  # stats were not parsed: candidate_digest / passed / total / failed /
  # duration_seconds are all JSON null.
  cat > "$inf" <<'JSON'
{"run_id":"20260822T020202Z-def456","tier":"vcluster","runner":"m2",
 "service":"product-catalog","project":"api+flows","candidate_digest":null,
 "passed":null,"total":null,"failed":null,"duration_seconds":null,
 "timestamp":"2026-08-22T02:02:02+00:00","commit":"cafef00d",
 "exit_code":1,"phase":"job","result":"fail"}
JSON
  run _e2e_publish_build "$inf" "$outf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=fail"* ]]
  run python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
e=json.loads(d["data"]["event.json"])
assert e["candidate_digest"]=="", e["candidate_digest"]
assert e["duration_seconds"]=="", e["duration_seconds"]
assert e["total"]=="", e["total"]
assert e["passed"]=="false", e["passed"]
print("ok")' "$outf"
  [ "$status" -eq 0 ]
}

@test "publish_build rejects the local-m4 runner (local publishes itself)" {
  local inf="$BATS_TEST_TMPDIR/in.json" outf="$BATS_TEST_TMPDIR/cm.json"
  _valid_payload | sed 's/"runner":"m2"/"runner":"local-m4"/' > "$inf"
  run _e2e_publish_build "$inf" "$outf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not permitted"* ]]
}

@test "publish_build rejects unexpected keys (namespace/kubeconfig/labels injection)" {
  local inf="$BATS_TEST_TMPDIR/in.json" outf="$BATS_TEST_TMPDIR/cm.json"
  local hex="1111111111111111111111111111111111111111111111111111111111111111"
  local base
  base='"run_id":"r1","tier":"vcluster","runner":"m2","service":"product-catalog","project":"p","candidate_digest":"","duration_seconds":1,"timestamp":"2026-08-22T01:01:01Z","exit_code":0,"phase":"complete","result":"pass"'
  for bad in '"namespace":"kube-system"' '"kubeconfig":"/etc/x"' '"labels":{"a":"b"}'; do
    printf '{%s,%s}\n' "$base" "$bad" > "$inf"
    run _e2e_publish_build "$inf" "$outf"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unexpected keys"* ]]
  done
}

@test "publish_build rejects missing required fields" {
  local inf="$BATS_TEST_TMPDIR/in.json" outf="$BATS_TEST_TMPDIR/cm.json"
  _valid_payload | sed 's/"run_id":"[^"]*",//' > "$inf"
  run _e2e_publish_build "$inf" "$outf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing required"* ]]
}

@test "publish_build rejects a malformed digest and a bad exit code" {
  local inf="$BATS_TEST_TMPDIR/in.json" outf="$BATS_TEST_TMPDIR/cm.json"
  _valid_payload | sed 's#ghcr.io/wilddog64/product-catalog@sha256:[0-9a-f]*#sha256:nope#' > "$inf"
  run _e2e_publish_build "$inf" "$outf"
  [ "$status" -ne 0 ]
  _valid_payload | sed 's/"exit_code":0/"exit_code":999/' > "$inf"
  run _e2e_publish_build "$inf" "$outf"
  [ "$status" -ne 0 ]
}

@test "publish_build rejects an invalid result value" {
  local inf="$BATS_TEST_TMPDIR/in.json" outf="$BATS_TEST_TMPDIR/cm.json"
  _valid_payload | sed 's/"result":"pass"/"result":"maybe"/' > "$inf"
  run _e2e_publish_build "$inf" "$outf"
  [ "$status" -ne 0 ]
}

@test "publish_build rejects non-JSON payloads" {
  local inf="$BATS_TEST_TMPDIR/in.json" outf="$BATS_TEST_TMPDIR/cm.json"
  printf 'not json at all' > "$inf"
  run _e2e_publish_build "$inf" "$outf"
  [ "$status" -ne 0 ]
}

@test "e2e_result_publish applies to the hub context and audits the outcome" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
  export E2E_PUBLISH_AUDIT_LOG="$BATS_TEST_TMPDIR/audit.log"
  run e2e_result_publish <<<"$(_valid_payload)"
  [ "$status" -eq 0 ]
  run cat "$KUBECTL_LOG"
  [[ "$output" == *"--context k3d-k3d-cluster"* ]]
  [[ "$output" == *"-n platform-ops apply -f"* ]]
  run cat "$E2E_PUBLISH_AUDIT_LOG"
  [[ "$output" == *"outcome=applied"* ]]
  [[ "$output" == *"runner=m2"* ]]
  [[ "$output" != *"sha256:"* ]]
}

@test "e2e_result_publish rejects an empty stdin payload" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
  export E2E_PUBLISH_AUDIT_LOG="$BATS_TEST_TMPDIR/audit.log"
  run e2e_result_publish <<<""
  [ "$status" -ne 0 ]
  run cat "$E2E_PUBLISH_AUDIT_LOG"
  [[ "$output" == *"outcome=rejected"* ]]
}

@test "e2e_result_publish rejects a bad payload and does not apply" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
  export E2E_PUBLISH_AUDIT_LOG="$BATS_TEST_TMPDIR/audit.log"
  run e2e_result_publish <<<'{"runner":"m2"}'
  [ "$status" -ne 0 ]
  run cat "$KUBECTL_LOG"
  [[ "$output" != *"apply -f"* ]]
  run cat "$E2E_PUBLISH_AUDIT_LOG"
  [[ "$output" == *"outcome=rejected"* ]]
}

@test "publisher install builds a restricted forced-command authorized_keys entry" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  local pub="$BATS_TEST_TMPDIR/m2.pub"
  echo "ssh-ed25519 AAAAC3NzaC1fakekeymaterial m2-runner" > "$pub"
  run e2e_result_publisher_install "$pub"
  [ "$status" -eq 0 ]
  run cat "$HOME/.ssh/authorized_keys"
  [[ "$output" == *'command="'* ]]
  [[ "$output" == *"e2e_result_publish"* ]]
  [[ "$output" == *"restrict"* ]]
  [[ "$output" == *"no-pty"* ]]
  [[ "$output" == *"e2e-m2-publisher"* ]]
  # idempotent: a second install does not duplicate the entry
  run e2e_result_publisher_install "$pub"
  [ "$status" -eq 0 ]
  run grep -c "e2e-m2-publisher" "$HOME/.ssh/authorized_keys"
  [ "$output" -eq 1 ]
}

@test "publisher install refuses a non-key file" {
  export HOME="$BATS_TEST_TMPDIR/home2"
  mkdir -p "$HOME"
  echo "this is not a key" > "$BATS_TEST_TMPDIR/notkey"
  run e2e_result_publisher_install "$BATS_TEST_TMPDIR/notkey"
  [ "$status" -ne 0 ]
}

@test "remote path never exfiltrates M4 kubeconfig, Vault, or Cloudflare secrets" {
  local f="scripts/plugins/e2e_remote.sh"
  run grep -nE '\b(scp|rsync)\b' "$f"; [ "$status" -ne 0 ]
  run grep -niE 'VAULT_TOKEN|cloudflare|CF_API' "$f"; [ "$status" -ne 0 ]
  # ignore comment lines — the file documents that we do NOT weaken host checks
  run bash -c "grep -vE '^[[:space:]]*#' '$f' | grep -nE 'StrictHostKeyChecking=no|UserKnownHostsFile'"
  [ "$status" -ne 0 ]
  # the M4 publish kubeconfig must only ever be used M4-side, never pushed to M2
  run grep -nE '_e2e_remote_ssh.*E2E_PUBLISH_KUBECONFIG' "$f"; [ "$status" -ne 0 ]
}
