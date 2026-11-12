#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load codex_dispatch_helpers

@test "codex dispatch: resume continues the same session" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  run dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason continue_prompt
  [ "$status" -eq 0 ]; sleep 1
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/prompt-2.md" ]
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/codex-2.log" ]
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/last-message-2.md" ]
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]
  [[ "$(<"$BATS_TEST_TMPDIR/a.argv")" == *"exec resume"* ]]
  [[ "$(<"$BATS_TEST_TMPDIR/a.argv")" == *"01a122dd-71c3-7763-87f0-3de505f10168"* ]]
  run dispatch status one; [[ "$output" == *"resumes: 1"* ]]
  [ "$(jq -r -s 'map(select(.slug=="one" and .event=="start"))[0].worker_identity.vendor' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = openai ]
  [ "$(jq -r -s 'map(select(.slug=="one" and .event=="resume"))[0] | (.run|tostring)+":"+.worker_identity.vendor+":"+.worker_identity.status' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "2:openai:unknown" ]
  [ "$(jq -r -s '[.[]|select(.slug=="one" and .event=="start")]|length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
  export STUB_SLEEP=5
  dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason continue_prompt
  run dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason continue_prompt
  [ "$status" -eq 2 ]; [[ "$output" == *"Codex is still running"* ]]
  sleep 6
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/codex-3.log" ]
}

@test "codex dispatch: resume accepts a dead worker whose PID identity is stale" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  sleep 1
  rm "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit"
  sed -i.bak 's/^process_start=.*/process_start=not-the-worker/' "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/start"
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  run dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason continue_prompt
  [ "$status" -eq 0 ]
  sleep 1
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit")" = 0 ]
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/codex-2.log" ]
}

@test "codex dispatch: resume passes the state root and runs in the worktree" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason continue_prompt >/dev/null; sleep 1
  resume_argv="$(tail -n 1 "$BATS_TEST_TMPDIR/a.argv")"
  [[ "$resume_argv" == *"writable_roots=[\"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/state\"]"* ]]
  [[ "$resume_argv" != *"network_access=true"* ]]
  [ "$(cd "$(tail -n 1 "$BATS_TEST_TMPDIR/a.argv.cwd")" && pwd -P)" = "$(cd "$K3DM_WORKTREE_ROOT/v9.9.9/one" && pwd -P)" ]
}

@test "codex dispatch: resume passes stored and overridden models and records provenance" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/model.argv" STUB_ENV="$BATS_TEST_TMPDIR/model.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug model --model gpt-6-luna >/dev/null; sleep 1
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  dispatch resume --slug model --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason correction >/dev/null; sleep 1
  [[ "$(tail -n 1 "$STUB_ARGV")" == *"exec resume -m gpt-6-luna"* ]]
  jq -e 'select(.event=="resume" and .slug=="model") | .worker_identity.model=="gpt-6-luna" and .worker_identity.source=="inherited"' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
  dispatch resume --slug model --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason correction --model gpt-6.1-terra >/dev/null; sleep 1
  [[ "$(tail -n 1 "$STUB_ARGV")" == *"exec resume -m gpt-6.1-terra"* ]]
  [ "$(cat "$K3DM_WORKTREE_ROOT/v9.9.9/model.run/model")" = gpt-6.1-terra ]
  jq -e 'select(.event=="resume" and .slug=="model" and .run==3) | .worker_identity.model=="gpt-6.1-terra" and .worker_identity.source=="explicit"' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
  dispatch resume --slug model --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason correction >/dev/null; sleep 1
  [[ "$(tail -n 1 "$STUB_ARGV")" == *"exec resume -m gpt-6.1-terra"* ]]
}

@test "codex dispatch: model-less resume omits model and records unreported" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/no-model.argv" STUB_ENV="$BATS_TEST_TMPDIR/no-model.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug no-model >/dev/null; sleep 1
  rm "$K3DM_WORKTREE_ROOT/v9.9.9/no-model.run/model"
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  dispatch resume --slug no-model --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason correction >/dev/null; sleep 1
  [[ "$(tail -n 1 "$STUB_ARGV")" == *"exec resume -c"* ]]
  [[ "$(tail -n 1 "$STUB_ARGV")" != *" -m "* ]]
  jq -e 'select(.event=="resume" and .slug=="no-model") | .worker_identity.model=="unknown" and .worker_identity.source=="unreported"' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
}

@test "codex dispatch: network resume passes the stored model" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/network-model.argv" STUB_ENV="$BATS_TEST_TMPDIR/network-model.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug network-model --model gpt-6-luna --network >/dev/null; sleep 1
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  dispatch resume --slug network-model --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason correction >/dev/null; sleep 1
  [[ "$(tail -n 1 "$STUB_ARGV")" == *"exec resume -m gpt-6-luna"* ]]
  [[ "$(tail -n 1 "$STUB_ARGV")" == *"network_access=true"* ]]
}

@test "codex dispatch: resume refuses a landed task and a log without a session id" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  sed -i.bak '/^session id: /d' "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/codex.log"
  run dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason continue_prompt
  [ "$status" -eq 2 ]; [[ "$output" == *"no valid session id"* ]]
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]
  run dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/empty.md" --reason continue_prompt
  [ "$status" -eq 2 ]
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug two >/dev/null; sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/two" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/two" commit -m edit >/dev/null
  dispatch land --slug two --no-test >/dev/null
  run dispatch resume --slug two --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason continue_prompt
  [ "$status" -eq 2 ]
}

@test "codex dispatch: a refused networked resume leaves the task finished" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one --network >/dev/null; sleep 1
  STUB_SLEEP=5 dispatch start --spec docs/plans/v9.9.9-demo.md --slug two --network >/dev/null
  run dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason continue_prompt
  [ "$status" -eq 2 ]; [[ "$output" == *"network task two is still running"* ]]
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/prompt-2.md" ]
  sleep 6
}

@test "codex dispatch: resume records the latest token total" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  export STUB_TOKENS=20000
  dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason continue_prompt >/dev/null; sleep 1
  [ "$(jq -r -s 'map(select(.event == "resume"))[0].n' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = 2 ]
  [ "$(jq -r -s 'map(select(.event == "codex_exit"))[-1].tokens' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = 20000 ]
}

@test "codex dispatch: resume requires a reason and records both events" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug reason >/dev/null
  sleep 1
  printf 'continue\n' >"$BATS_TEST_TMPDIR/p.md"
  cp "$K3DM_WORKTREE_ROOT/ledger.jsonl" "$BATS_TEST_TMPDIR/before"
  cp "$STUB_ARGV" "$BATS_TEST_TMPDIR/argv-before"
  run dispatch resume --slug reason --prompt-file "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]
  run dispatch resume --slug reason --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason invalid
  [ "$status" -eq 2 ]
  cmp "$BATS_TEST_TMPDIR/before" "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  cmp "$BATS_TEST_TMPDIR/argv-before" "$STUB_ARGV"
  dispatch resume --slug reason --prompt-file "$BATS_TEST_TMPDIR/p.md" --reason correction >/dev/null
  [ "$(jq -s '[.[] | select(.event == "resume" and .reason == "correction")] | length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
  [ "$(jq -s '[.[] | select(.event == "intervention" and .reason == "correction")] | length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
}

