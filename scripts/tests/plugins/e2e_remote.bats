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
  unset E2E_PUBLISH_FROM
  local pub="$BATS_TEST_TMPDIR/m2.pub"
  echo "ssh-ed25519 AAAAC3NzaC1fakekeymaterial m2-runner" > "$pub"
  run e2e_result_publisher_install "$pub"
  [ "$status" -eq 0 ]
  run cat "$HOME/.ssh/authorized_keys"
  [[ "$output" != *'from='* ]]
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

  export HOME="$BATS_TEST_TMPDIR/pinned-home"
  mkdir -p "$HOME"
  export E2E_PUBLISH_FROM="192.168.39.0/24"
  run e2e_result_publisher_install "$pub"
  [ "$status" -eq 0 ]
  run cat "$HOME/.ssh/authorized_keys"
  [[ "$output" == 'from="192.168.39.0/24",command='* ]]
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

# --- Failure behavior and operations (increment 6) -------------------------

@test "public failure/ops functions are dispatchable (no leading underscore)" {
  for fn in e2e_runner_publish_back e2e_runner_publish_replay \
            e2e_runner_replay e2e_runner_unlock e2e_runner_health; do
    run declare -f "$fn"
    [ "$status" -eq 0 ]
    [[ "$fn" != _* ]]
  done
}

@test "lock token carries only owner/pid/ts and no shell metacharacters" {
  run _e2e_lock_token
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^owner=[^[:space:]\;\|\&\$\`]+\ pid=[0-9]+\ ts=[0-9]+$ ]]
}

@test "the runner lock is a directory (atomic mkdir), probed with -e" {
  local f="scripts/plugins/e2e_remote.sh"
  run grep -E 'mkdir .*\$\{E2E_M2_LOCK\}' "$f"; [ "$status" -eq 0 ]
  run grep -F -- 'if [ -e "${E2E_M2_LOCK}" ]; then echo lock=1' "$f"; [ "$status" -eq 0 ]
  # the old plain-file probe must be gone
  run grep -F -- 'if [ -f "${E2E_M2_LOCK}" ]; then echo lock=1' "$f"; [ "$status" -ne 0 ]
}

@test "lock acquire records the owner token via mkdir + meta" {
  SSHLOG="$BATS_TEST_TMPDIR/ssh.log"; : > "$SSHLOG"
  _e2e_remote_ssh() { echo "$*" >> "$SSHLOG"; return 0; }
  run _e2e_remote_lock_acquire "owner=m4 pid=1 ts=1"
  [ "$status" -eq 0 ]
  run cat "$SSHLOG"
  [[ "$output" == *"mkdir"* ]]
  [[ "$output" == *'${E2E_M2_LOCK}'* ]] || [[ "$output" == *"/meta"* ]]
  [[ "$output" == *"owner=m4 pid=1 ts=1"* ]]
}

@test "lock release only removes when the owner meta matches (never blind rm)" {
  SSHLOG="$BATS_TEST_TMPDIR/ssh.log"; : > "$SSHLOG"
  _e2e_remote_ssh() { echo "$*" >> "$SSHLOG"; return 0; }
  run _e2e_remote_lock_release "owner=m4 pid=1 ts=1"
  [ "$status" -eq 0 ]
  run cat "$SSHLOG"
  [[ "$output" == *"grep -qxF"* ]]
  [[ "$output" == *"owner=m4 pid=1 ts=1"* ]]
  [[ "$output" == *"rm -rf"* ]]
}

@test "dispatch refuses and never falls back locally when the lock is held" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
  e2e_runner_preflight() { printf 'status=available\n'; return 0; }
  _e2e_remote_lock_acquire() { return 1; }
  ssh() { echo "SSH SHOULD NOT RUN" >&2; return 0; }
  run e2e_runner_dispatch "m2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"busy"* ]]
  [[ "$output" == *"no local fallback"* ]]
  [[ "$output" != *"SSH SHOULD NOT RUN"* ]]
}

@test "dispatch chains publish-back after the E2E and preserves the exit code" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
  e2e_runner_preflight() { printf 'status=available\n'; return 0; }
  _e2e_remote_lock_acquire() { return 0; }
  _e2e_remote_lock_release() { return 0; }
  SSH_LOG="$BATS_TEST_TMPDIR/ssh.log"
  ssh() { printf '%s\n' "$*" > "$SSH_LOG"; return 0; }
  run e2e_runner_dispatch "m2"
  [ "$status" -eq 0 ]
  run cat "$SSH_LOG"
  [[ "$output" == *"e2e_verify_vcluster"* ]]
  [[ "$output" == *"e2e_runner_publish_back"* ]]
}

@test "newest_summary returns the latest run json and skips retention markers" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"; mkdir -p "$E2E_REPORT_DIR"
  : > "$E2E_REPORT_DIR/a.json";        touch -t 202601010000 "$E2E_REPORT_DIR/a.json"
  : > "$E2E_REPORT_DIR/b.json";        touch -t 202601020000 "$E2E_REPORT_DIR/b.json"
  : > "$E2E_REPORT_DIR/c.publication_pending.json"; touch -t 202601030000 "$E2E_REPORT_DIR/c.publication_pending.json"
  : > "$E2E_REPORT_DIR/d.published.json";           touch -t 202601040000 "$E2E_REPORT_DIR/d.published.json"
  run _e2e_newest_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"/b.json" ]]
}

@test "synth_summary writes a schema-valid failed summary carrying the exit code" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"; mkdir -p "$E2E_REPORT_DIR"
  run _e2e_synth_summary 3
  [ "$status" -eq 0 ]
  local f="$output"
  [ -s "$f" ]
  run python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
assert d["tier"]=="vcluster", d["tier"]
assert d["result"]=="fail", d["result"]
assert d["exit_code"]==3, d["exit_code"]
for k in ("run_id","runner","service","candidate_digest","passed","total","failed","duration_seconds","timestamp","commit","phase"):
    assert k in d, k
print("ok")' "$f"
  [ "$status" -eq 0 ]
}

@test "synth_summary clamps an out-of-range exit code" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"; mkdir -p "$E2E_REPORT_DIR"
  run _e2e_synth_summary 999
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["exit_code"]==1, d["exit_code"]; print("ok")' "$output"
  [ "$status" -eq 0 ]
}

@test "publish_back_push fails when no M4 target is configured" {
  E2E_PUBLISH_BACK_HOST=""
  echo '{}' > "$BATS_TEST_TMPDIR/r.json"
  run _e2e_publish_back_push "$BATS_TEST_TMPDIR/r.json"
  [ "$status" -ne 0 ]
}

@test "publish_back_push uses the dedicated key and streams the file over stdin" {
  E2E_PUBLISH_BACK_HOST="m4host"
  E2E_PUBLISH_BACK_KEY="/keys/e2e-m4-publisher"
  SSH_LOG="$BATS_TEST_TMPDIR/ssh.log"; STDIN_LOG="$BATS_TEST_TMPDIR/stdin.log"
  ssh() { printf '%s\n' "$*" > "$SSH_LOG"; cat > "$STDIN_LOG"; return 0; }
  printf 'PAYLOAD-BODY' > "$BATS_TEST_TMPDIR/r.json"
  run _e2e_publish_back_push "$BATS_TEST_TMPDIR/r.json"
  [ "$status" -eq 0 ]
  run cat "$SSH_LOG"
  [[ "$output" == *"-i /keys/e2e-m4-publisher"* ]]
  [[ "$output" == *"-o AddressFamily=inet"* ]]
  [[ "$output" == *"m4host"* ]]
  run cat "$STDIN_LOG"
  [ "$output" = "PAYLOAD-BODY" ]
}

@test "publish_back synthesizes a summary when the run left none, and returns 0" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"; mkdir -p "$E2E_REPORT_DIR"
  PUSH_LOG="$BATS_TEST_TMPDIR/push.log"
  _e2e_publish_back_push() { echo "$1" > "$PUSH_LOG"; return 0; }
  run e2e_runner_publish_back 2
  [ "$status" -eq 0 ]
  run cat "$PUSH_LOG"
  [[ "$output" == *"/synth-"* ]]
}

@test "publish_back retains a publication_pending marker when M4 is unavailable" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"; mkdir -p "$E2E_REPORT_DIR"
  printf '{"run_id":"x"}' > "$E2E_REPORT_DIR/run.json"
  _e2e_publish_back_push() { return 1; }
  run e2e_runner_publish_back 0
  [ "$status" -eq 0 ]
  run bash -c 'ls "$1"/*.publication_pending.json' "" "$E2E_REPORT_DIR"
  [ "$status" -eq 0 ]
}

@test "publish_replay pushes retained results and renames them published, idempotently" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"; mkdir -p "$E2E_REPORT_DIR"
  printf '{}' > "$E2E_REPORT_DIR/one.publication_pending.json"
  printf '{}' > "$E2E_REPORT_DIR/two.publication_pending.json"
  _e2e_publish_back_push() { return 0; }
  run e2e_runner_publish_replay
  [ "$status" -eq 0 ]
  run bash -c 'ls "$1"/*.publication_pending.json 2>/dev/null' "" "$E2E_REPORT_DIR"
  [ "$status" -ne 0 ]
  run bash -c 'ls "$1"/*.published.json' "" "$E2E_REPORT_DIR"
  [ "$status" -eq 0 ]
}

@test "publish_replay reports still-pending (non-zero) when a push fails" {
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"; mkdir -p "$E2E_REPORT_DIR"
  printf '{}' > "$E2E_REPORT_DIR/one.publication_pending.json"
  _e2e_publish_back_push() { return 1; }
  run e2e_runner_publish_replay
  [ "$status" -ne 0 ]
  [[ "$output" == *"still_pending=1"* ]]
}

@test "M4 replay enforces the allowlist and the reachability guard" {
  run e2e_runner_replay "local-m4"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not in allowlist"* ]]

  _e2e_remote_ssh() { return 1; }
  run e2e_runner_replay "m2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unreachable"* ]]
}

@test "M4 replay drives the remote publish_replay when the runner is reachable" {
  SSHLOG="$BATS_TEST_TMPDIR/ssh.log"; : > "$SSHLOG"
  _e2e_remote_ssh() { echo "$*" >> "$SSHLOG"; return 0; }
  run e2e_runner_replay "m2"
  [ "$status" -eq 0 ]
  run cat "$SSHLOG"
  [[ "$output" == *"e2e_runner_publish_replay"* ]]
}

@test "unlock reports nothing to clear when no lock is present" {
  _e2e_remote_ssh() { echo "age=-1"; return 0; }
  run e2e_runner_unlock "m2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to clear"* ]]
}

@test "unlock refuses while an E2E run is still active" {
  _e2e_remote_ssh() { printf 'age=99999\nrunning=1\n'; return 0; }
  run e2e_runner_unlock "m2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"still active"* ]]
}

@test "unlock refuses a fresh (not-yet-stale) lock" {
  export E2E_M2_LOCK_MAX_AGE=7200
  _e2e_remote_ssh() { printf 'age=10\nrunning=0\n'; return 0; }
  run e2e_runner_unlock "m2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not yet stale"* ]]
}

@test "unlock clears a stale lock past the max age with no live run" {
  export E2E_M2_LOCK_MAX_AGE=7200
  _e2e_remote_ssh() { printf 'age=8000\nrunning=0\n'; return 0; }
  run e2e_runner_unlock "m2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleared stale lock"* ]]
}

@test "unlock enforces the allowlist" {
  run e2e_runner_unlock "local-m4"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not in allowlist"* ]]
}

@test "health reports a hub outage as critical, distinct from runner state" {
  KUBECTL_EXIT_CODES=(1)
  e2e_runner_status() { printf 'status=available\n'; }
  run e2e_runner_health
  [ "$status" -ne 0 ]
  [[ "$output" == *"hub=unreachable"* ]]
  [[ "$output" == *"severity=critical"* ]]
}

@test "health is ok when the hub is up and the runner is available" {
  e2e_runner_status() { printf 'status=available\n'; }
  run e2e_runner_health
  [ "$status" -eq 0 ]
  [[ "$output" == *"hub=ok"* ]]
  [[ "$output" == *"runner_status=available"* ]]
  [[ "$output" == *"severity=ok"* ]]
}

@test "an unavailable runner is a warning, but critical when a run was requested" {
  e2e_runner_status() { printf 'status=busy\n'; }
  run e2e_runner_health
  [ "$status" -eq 0 ]
  [[ "$output" == *"severity=warning"* ]]

  E2E_RUN_REQUESTED=1 run e2e_runner_health
  [ "$status" -ne 0 ]
  [[ "$output" == *"severity=critical"* ]]
}

@test "the failure path never auto-restarts OrbStack, deletes a cluster, or blind-clears the lock" {
  local f="scripts/plugins/e2e_remote.sh"
  # we never delete a k3d cluster anywhere in this module
  run grep -nE 'k3d cluster (delete|rm)' "$f"; [ "$status" -ne 0 ]
  # the only rm of the runner lock lives behind the ownership/age guards
  run bash -c "grep -nE 'rm -rf .*E2E_M2_LOCK' '$f' | wc -l | tr -d ' '"
  [ "$output" -le 2 ]
}

@test "make targets wire the failure/ops entry points" {
  run grep -F -- 'e2e_runner_health $(RUNNER)' Makefile
  [ "$status" -eq 0 ]
  run grep -F -- 'e2e_runner_replay $(RUNNER)' Makefile
  [ "$status" -eq 0 ]
  run grep -F -- 'e2e_runner_unlock $(RUNNER)' Makefile
  [ "$status" -eq 0 ]
}
