#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load codex_dispatch_helpers

@test "codex dispatch: agy runs in its worktree with default model and ledger identity" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv" STUB_ARGV="$BATS_TEST_TMPDIR/codex.argv" STUB_ENV="$BATS_TEST_TMPDIR/codex.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug agy --agent agy >/dev/null
  sleep 1
  [[ "$(<"$BATS_TEST_TMPDIR/agy.argv")" == *"--model gemini-4-argon-medium"* ]]
  [[ "$(<"$BATS_TEST_TMPDIR/agy.argv")" == *"--sandbox"* ]]
  grep -q '^K3DM_DISPATCH_SLUG=agy$' "$BATS_TEST_TMPDIR/agy.argv.env"
  [ "$(cd "$(<"$BATS_TEST_TMPDIR/agy.argv.cwd")" && pwd -P)" = "$(cd "$K3DM_WORKTREE_ROOT/v9.9.9/agy" && pwd -P)" ]
  [ "$(jq -r 'select(.event=="start")|.agent+":"+.model_source+":"+.model' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "agy:default:gemini-4-argon-medium" ]
  [ "$(jq -r 'select(.event=="start")|.worker_identity.vendor+":"+.worker_identity.model+":"+.worker_identity.status+":"+.coordinator_identity.status' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "google:gemini-4-argon-medium:selected:unknown" ]
  [ "$(jq -r 'select(.event=="agent_exit")|(.run|tostring)+":"+.session' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "1:agy-conversation-1" ]
  grep -q '"event":"agent_usage"' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  [ ! -e "$BATS_TEST_TMPDIR/codex.argv" ]
}

@test "codex dispatch: uncommitted agy work can be reviewed and landed" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv" AGY_EDIT=1
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug agy-land --agent agy >/dev/null
  sleep 1
  run dispatch status agy-land
  [[ "$output" == *"state: exited successfully"* ]]
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/agy-land/a.txt")" = "agy working-tree edit" ]
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/agy-land" add a.txt
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/agy-land" commit -m reviewed-agy-edit >/dev/null
  run dispatch land --slug agy-land --no-test
  [ "$status" -eq 0 ]; [[ "$output" == *"landed: agy-land"* ]]
}

@test "codex dispatch: unknown agy model fails before worktree creation" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug unknown --agent agy --model nope
  [ "$status" -eq 2 ]; [[ "$output" == *"unknown agy model: nope"* ]]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/unknown" ]
}

@test "codex dispatch: agy model matching uses only exact model IDs" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug display-name --agent agy --model 'Gemini 4 Argon (Medium)'
  [ "$status" -eq 2 ]; [[ "$output" == *"unknown agy model: Gemini 4 Argon (Medium)"* ]]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/display-name" ]
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug model-prefix --agent agy --model gemini-4-argon
  [ "$status" -eq 2 ]; [[ "$output" == *"unknown agy model: gemini-4-argon"* ]]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/model-prefix" ]
}

@test "codex dispatch: explicit agy and Codex models are recorded and passed" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug agy-model --agent agy --model gemini-test >/dev/null
  sleep 1
  [[ "$(<"$BATS_TEST_TMPDIR/agy.argv")" == *"--model gemini-test"* ]]
  [ "$(jq -r 'select(.event=="start" and .slug=="agy-model")|.model_source' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = explicit ]
  export STUB_ARGV="$BATS_TEST_TMPDIR/codex-model.argv" STUB_ENV="$BATS_TEST_TMPDIR/codex-model.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug codex-model --model gpt-test >/dev/null
  sleep 1
  [[ "$(<"$BATS_TEST_TMPDIR/codex-model.argv")" == "exec -m gpt-test --sandbox workspace-write -C $K3DM_WORKTREE_ROOT/v9.9.9/codex-model --add-dir $K3DM_WORKTREE_ROOT/v9.9.9/codex-model.run/state -o $K3DM_WORKTREE_ROOT/v9.9.9/codex-model.run/last-message.md -" ]]
  [ "$(jq -r 'select(.event=="start" and .slug=="codex-model")|.model_source' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = explicit ]
}

@test "codex dispatch: missing agy usage is recorded as null without token counts" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv" AGY_NO_USAGE=1
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug agy-no-usage --agent agy >/dev/null
  sleep 1
  [ "$(jq -r 'select(.event=="agent_exit")|.usage' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = null ]
  [ "$(jq -s '[.[]|select(.event=="agent_usage")]|length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 0 ]
  [ "$(jq -s '[.[]|select(has("tokens"))]|length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 0 ]
}

@test "codex dispatch: agy commit is a scope violation and cannot land" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv" AGY_COMMIT=1
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug committed --agent agy >/dev/null
  sleep 1
  grep -q '"event":"scope_violation"' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch status committed
  [[ "$output" == *"VIOLATION: agent committed"* ]]
  run dispatch land --slug committed --no-test
  [ "$status" -eq 2 ]; [[ "$output" == *"VIOLATION: agent committed"* ]]
}

@test "codex dispatch: agy resume requires and uses its stored conversation" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug resume --agent agy >/dev/null
  sleep 1
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  rm "$K3DM_WORKTREE_ROOT/v9.9.9/resume.run/session"
  run dispatch resume --slug resume --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason continue_prompt
  [ "$status" -eq 2 ]; [[ "$output" == *"agy run returned no conversation id; start a new task"* ]]
  printf 'agy-conversation-1\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/resume.run/session"
  dispatch resume --slug resume --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason continue_prompt >/dev/null
  sleep 1
  grep -q -- '--conversation agy-conversation-1' "$BATS_TEST_TMPDIR/agy.argv"
  run ! grep -q -- '--continue' "$BATS_TEST_TMPDIR/agy.argv"
}

@test "codex dispatch: network is refused for agy" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --agent agy --network
  [ "$status" -eq 2 ]; [[ "$output" == *"--network is not supported with --agent agy"* ]]
}

