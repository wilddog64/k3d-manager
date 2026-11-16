#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load codex_dispatch_helpers

@test "codex dispatch: omitted primary stays unknown and invalid handoff reason is rejected" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/codex.argv" STUB_ENV="$BATS_TEST_TMPDIR/codex.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug unknown-primary >/dev/null
  sleep 1
  jq -e 'select(.event=="primary_coordinator" and .slug=="unknown-primary") | .primary_coordinator_identity.vendor == "unknown" and .primary_coordinator_identity.source == "unknown"' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
  run dispatch handoff --slug unknown-primary --acting-coordinator openai/gpt-6-luna --reason account_balance_guess
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid handoff reason"* ]]
}

@test "codex dispatch: primary identity retains runtime-reported provenance" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/codex.argv" STUB_ENV="$BATS_TEST_TMPDIR/codex.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug runtime-primary --primary-coordinator openai/gpt-6-luna --primary-coordinator-source runtime-reported >/dev/null
  sleep 1
  jq -e 'select(.event=="primary_coordinator" and .slug=="runtime-primary") | .primary_coordinator_identity.source == "runtime-reported" and .primary_coordinator_identity.status == "runtime_reported"' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
}

@test "codex dispatch: invalid primary and handoff identity or provenance do not append" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/codex.argv" STUB_ENV="$BATS_TEST_TMPDIR/codex.env"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug invalid-primary --primary-coordinator 'openai/not a model'
  [ "$status" -eq 2 ]
  [ ! -e "$K3DM_WORKTREE_ROOT/ledger.jsonl" ]
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug invalid-source --primary-coordinator openai/gpt-6-luna --primary-coordinator-source guessed
  [ "$status" -eq 2 ]
  [ ! -e "$K3DM_WORKTREE_ROOT/ledger.jsonl" ]

  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug strict >/dev/null
  [ "$status" -eq 0 ]
  for _ in {1..50}; do
    jq -e 'select(.event=="codex_exit" and .slug=="strict")' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null 2>&1 && break
    sleep 0.1
  done
  jq -e 'select(.event=="codex_exit" and .slug=="strict")' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
  before="$(cat "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  run dispatch handoff --slug strict --acting-coordinator 'openai/not a model' --reason manual
  [ "$status" -eq 2 ]
  [ "$(cat "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "$before" ]
  run dispatch handoff --slug strict --acting-coordinator openai/gpt-6-luna --reason manual --provenance guessed
  [ "$status" -eq 2 ]
  [ "$(cat "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "$before" ]
}

@test "codex dispatch: start records spec size snapshot" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/codex.argv" STUB_ENV="$BATS_TEST_TMPDIR/codex.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug spec-size >/dev/null
  sleep 1
  jq -e 'select(.event=="start" and .slug=="spec-size") | .spec_stats.files == 4 and .spec_stats.must == null' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
}

@test "codex dispatch: default Codex command is unchanged and start identity is explicit" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/default.argv" STUB_ENV="$BATS_TEST_TMPDIR/default.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug codex >/dev/null
  sleep 1
  [ "$(jq -r 'select(.event=="start")|.agent+":"+(.model|tostring)+":"+.model_source' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "codex:null:inherited" ]
  [ "$(jq -s '[.[]|select(.event=="identity")]|length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 0 ]
  [[ "$(<"$BATS_TEST_TMPDIR/default.argv")" == "exec --sandbox workspace-write -C $K3DM_WORKTREE_ROOT/v9.9.9/codex --add-dir $K3DM_WORKTREE_ROOT/v9.9.9/codex.run/state -o $K3DM_WORKTREE_ROOT/v9.9.9/codex.run/last-message.md -" ]]
}

@test "codex dispatch: runtime model is recorded for each attempt without copying other log text" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/runtime.argv" STUB_ENV="$BATS_TEST_TMPDIR/runtime.env"
  export STUB_MODEL_LINE='model: gpt-test-1' STUB_LOG_MARKER='private-stub-marker'
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug runtime >/dev/null
  sleep 1
  [ "$(jq -r 'select(.event=="identity")|.worker_identity.model+":"+.worker_identity.source+":"+.worker_identity.status' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "gpt-test-1:runtime:reported" ]
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/runtime-prompt.md"
  export STUB_MODEL_LINE='model: gpt-test-2'
  dispatch resume --slug runtime --prompt-file "$BATS_TEST_TMPDIR/runtime-prompt.md" --reason continue_prompt --coordinator anthropic/claude-test >/dev/null
  sleep 1
  [ "$(jq -r -s '[.[]|select(.event=="identity")|.worker_identity.model]|join(",")' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "gpt-test-1,gpt-test-2" ]
  [ "$(jq -r 'select(.event=="resume" and .slug=="runtime")|.coordinator_identity.vendor+":"+.coordinator_identity.model+":"+.coordinator_identity.source' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "anthropic:claude-test:declared" ]
  run ! grep -q 'private-stub-marker' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run ! grep -q 'private-stub-marker' "$K3DM_WORKTREE_ROOT/metrics.log"
}

@test "codex dispatch: invalid runtime model and coordinator are rejected safely" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/invalid.argv" STUB_ENV="$BATS_TEST_TMPDIR/invalid.env"
  export STUB_MODEL_LINE='model: bad value!'
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug invalid-model >/dev/null
  sleep 1
  [ "$(jq -s '[.[]|select(.event=="identity" and .slug=="invalid-model")]|length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 0 ]
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug bad-coordinator --coordinator 'bad/x y'
  [ "$status" -eq 2 ] && [[ "$output" == *'invalid coordinator'* ]]
  [ "$(jq -s '[.[]|select(.event=="start" and .slug=="bad-coordinator")]|length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 0 ]
}

@test "codex dispatch: declared coordinator is recorded on start" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/coordinator.argv" STUB_ENV="$BATS_TEST_TMPDIR/coordinator.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug coordinator --coordinator anthropic/claude-test >/dev/null
  [ "$(jq -r 'select(.event=="start" and .slug=="coordinator")|.coordinator_identity.vendor+":"+.coordinator_identity.model+":"+.coordinator_identity.source' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "anthropic:claude-test:declared" ]
}

@test "codex dispatch: start refuses a non-release branch" {
  git -C "$FIXTURE" checkout -b feature >/dev/null
  run dispatch start --spec docs/plans/v9.9.9-demo.md
  [ "$status" -eq 2 ]; [[ "$output" == *"not a release branch"* ]]
}

@test "codex dispatch: start refuses changed spec and ahead HEAD" {
  printf 'changed\n' >>"$FIXTURE/docs/plans/v9.9.9-demo.md"
  run dispatch start --spec docs/plans/v9.9.9-demo.md
  [ "$status" -eq 2 ]; [[ "$output" == *"spec is changed"* ]]
  git -C "$FIXTURE" checkout -- docs/plans/v9.9.9-demo.md; printf 'ahead\n' >"$FIXTURE/ahead.txt"
  git -C "$FIXTURE" add ahead.txt; git -C "$FIXTURE" commit -m ahead >/dev/null
  run dispatch start --spec docs/plans/v9.9.9-demo.md
  [ "$status" -eq 2 ]; [[ "$output" == *"HEAD is not pushed"* ]]
}

@test "codex dispatch: start isolates operator checkout" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/one.argv" STUB_ENV="$BATS_TEST_TMPDIR/one.env"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug one
  [ "$status" -eq 0 ]; sleep 1
  [ "$(<"$FIXTURE/a.txt")" = original ]; [ "$(git -C "$FIXTURE" status --porcelain)" = "" ]
  [ -d "$K3DM_WORKTREE_ROOT/v9.9.9/one" ]
}

@test "codex dispatch: records the release base at start" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/base")" = "$(git -C "$FIXTURE" rev-parse origin/k3d-manager-v9.9.9)" ]
}

@test "codex dispatch: start records session token usage from CODEX_HOME" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  mkdir -p "$CODEX_HOME/sessions/2026/10/23"
  cat >"$CODEX_HOME/sessions/2026/10/23/rollout-test-01a122dd-71c3-7763-87f0-3de505f10168.jsonl" <<'EOF'
{"type":"session_meta","payload":{"id":"01a122dd-71c3-7763-87f0-3de505f10168","timestamp":"2026-10-23T10:00:00Z"}}
{"type":"turn_context","payload":{"model":"gpt-5.6-luna"}}
{"type":"event_msg","payload":{"info":{"total_token_usage":{"input_tokens":611180,"cached_input_tokens":561408,"output_tokens":5912,"reasoning_output_tokens":10}}}}
EOF
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  usage="$(jq -s 'map(select(.event == "codex_usage")) | .[0]' "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  [ "$(jq -r '.session' <<<"$usage")" = 01a122dd-71c3-7763-87f0-3de505f10168 ]
  [ "$(jq -r '.model' <<<"$usage")" = gpt-5.6-luna ]
  [ "$(jq -r '.input' <<<"$usage")" = 611180 ]
  [ "$(jq -r '.cached_input' <<<"$usage")" = 561408 ]
  [ "$(jq -r '.output' <<<"$usage")" = 5912 ]
}

@test "codex dispatch: missing session usage warns but start succeeds" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug one
  [ "$status" -eq 0 ]; sleep 1
  grep -q 'WARNING: expected one session file' "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/supervisor.log"
  [ "$(jq -s 'map(select(.event == "codex_usage")) | length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 0 ]
}

@test "codex dispatch start accepts a long parent slug and refuses one over 120 characters" {
  local long over
  [ "$K3DM_WORKTREE_ROOT" != "$HOME/.local/share/k3d-manager/worktrees" ]
  sed '/deliberately corrupt/d' "$BATS_TEST_DIRNAME/../fixtures/dispatch-gates/synthetic.jsonl" >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  export STUB_ARGV="$BATS_TEST_TMPDIR/long-parent.argv" STUB_ENV="$BATS_TEST_TMPDIR/long-parent.env"
  long="$(printf 'p%.0s' {1..120})"
  over="${long}p"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug over-parent --parent "$over" --role review
  [ "$status" -eq 2 ]
  [ "$(jq -s '[.[]|select(.slug=="over-parent" and .event=="start")]|length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 0 ]
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug long-parent --parent "$long" --role review >/dev/null
  [ "$(jq -r -s '[.[]|select(.slug=="long-parent" and .event=="start")][-1] | .parent' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "$long" ]
}
