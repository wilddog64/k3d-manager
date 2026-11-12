#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load codex_dispatch_helpers

@test "codex dispatch: abandon without yes changes nothing" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; run dispatch abandon --slug one
  [ "$status" -eq 2 ]; [ -d "$K3DM_WORKTREE_ROOT/v9.9.9/one" ]
  git -C "$FIXTURE" show-ref --verify --quiet refs/heads/task/v9.9.9/one
}

@test "codex dispatch: abandon refuses when task has no start in ledger (N1)" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR"* ]]
  mkdir -p "$K3DM_WORKTREE_ROOT/v9.9.9/nostart"
  git -C "$FIXTURE" branch task/v9.9.9/nostart
  git -C "$FIXTURE" worktree add "$K3DM_WORKTREE_ROOT/v9.9.9/nostart" task/v9.9.9/nostart >/dev/null
  printf '{"ts":1,"event":"start","version":"v9.9.9","slug":"other","repo":"k3d-manager"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  local before
  before="$(cat "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  run dispatch abandon --slug nostart --yes
  [ "$status" -ne 0 ]
  [ "$(cat "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "$before" ]
}

@test "codex dispatch: abandon refuses when task is already landed or abandoned (N2)" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR"* ]]
  mkdir -p "$K3DM_WORKTREE_ROOT/v9.9.9/already-landed"
  git -C "$FIXTURE" branch task/v9.9.9/already-landed
  git -C "$FIXTURE" worktree add "$K3DM_WORKTREE_ROOT/v9.9.9/already-landed" task/v9.9.9/already-landed >/dev/null
  printf '{"ts":1,"event":"start","version":"v9.9.9","slug":"already-landed","repo":"k3d-manager"}\n{"ts":2,"event":"land","version":"v9.9.9","slug":"already-landed","repo":"k3d-manager"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  local before
  before="$(cat "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  run dispatch abandon --slug already-landed --yes
  [ "$status" -ne 0 ]
  [ "$(cat "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "$before" ]
}

@test "codex dispatch: abandon --version of an older release preserves current release worktree and branch (N3)" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR"* ]]
  mkdir -p "$K3DM_WORKTREE_ROOT/v9.9.8/old-task"
  git -C "$FIXTURE" branch task/v9.9.8/old-task
  git -C "$FIXTURE" worktree add "$K3DM_WORKTREE_ROOT/v9.9.8/old-task" task/v9.9.8/old-task >/dev/null
  mkdir -p "$K3DM_WORKTREE_ROOT/v9.9.9/curr-task"
  git -C "$FIXTURE" branch task/v9.9.9/curr-task
  git -C "$FIXTURE" worktree add "$K3DM_WORKTREE_ROOT/v9.9.9/curr-task" task/v9.9.9/curr-task >/dev/null
  printf '{"ts":1,"event":"start","version":"v9.9.8","slug":"old-task","repo":"k3d-manager"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  printf '{"ts":2,"event":"start","version":"v9.9.9","slug":"curr-task","repo":"k3d-manager"}\n' >>"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch abandon --version v9.9.8 --slug old-task --yes
  [ "$status" -eq 0 ]
  [ -d "$K3DM_WORKTREE_ROOT/v9.9.9/curr-task" ]
  git -C "$FIXTURE" show-ref --verify --quiet refs/heads/task/v9.9.9/curr-task
}

@test "codex dispatch: abandon without yes changes nothing in ledger, worktree, or branch (N4)" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR"* ]]
  mkdir -p "$K3DM_WORKTREE_ROOT/v9.9.8/old-task"
  git -C "$FIXTURE" branch task/v9.9.8/old-task
  git -C "$FIXTURE" worktree add "$K3DM_WORKTREE_ROOT/v9.9.8/old-task" task/v9.9.8/old-task >/dev/null
  printf '{"ts":1,"event":"start","version":"v9.9.8","slug":"old-task","repo":"k3d-manager"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  local before_ledger
  before_ledger="$(cat "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  run dispatch abandon --version v9.9.8 --slug old-task
  [ "$status" -eq 2 ]
  [[ "$output" == *"would remove: $K3DM_WORKTREE_ROOT/v9.9.8/old-task"* ]]
  [[ "$output" == *"would delete branch: task/v9.9.8/old-task"* ]]
  [ "$(cat "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "$before_ledger" ]
  [ -d "$K3DM_WORKTREE_ROOT/v9.9.8/old-task" ]
  git -C "$FIXTURE" show-ref --verify --quiet refs/heads/task/v9.9.8/old-task
}

@test "codex dispatch: abandon --version from different release branch writes abandon event and clears open (M1)" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR"* ]]
  mkdir -p "$K3DM_WORKTREE_ROOT/v1.2.3/older-task"
  git -C "$FIXTURE" branch task/v1.2.3/older-task
  git -C "$FIXTURE" worktree add "$K3DM_WORKTREE_ROOT/v1.2.3/older-task" task/v1.2.3/older-task >/dev/null
  printf '{"ts":1,"event":"start","version":"v1.2.3","slug":"older-task","repo":"k3d-manager"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch open
  [ "$status" -eq 1 ]
  [[ "$output" == *"v1.2.3 older-task"* ]]
  run dispatch abandon --version v1.2.3 --slug older-task --yes
  [ "$status" -eq 0 ]
  [ ! -e "$K3DM_WORKTREE_ROOT/v1.2.3/older-task" ]
  run ! git -C "$FIXTURE" show-ref --verify --quiet refs/heads/task/v1.2.3/older-task
  run jq -c 'select(.event == "abandon" and .version == "v1.2.3" and .slug == "older-task")' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  run dispatch open
  [[ "$output" != *"older-task"* ]]
}

@test "codex dispatch: abandon of task whose worktree and branch are gone exits 0 and writes event (M2)" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR"* ]]
  printf '{"ts":1,"event":"start","version":"v1.2.3","slug":"gone-task","repo":"k3d-manager"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch abandon --version v1.2.3 --slug gone-task --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing worktree:"* ]]
  [[ "$output" == *"missing branch:"* ]]
  [[ "$output" == *"abandoned: gone-task"* ]]
  run jq -c 'select(.event == "abandon" and .version == "v1.2.3" and .slug == "gone-task")' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "codex dispatch: abandon --reason TEXT records TEXT in the abandon event (M3)" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR"* ]]
  printf '{"ts":1,"event":"start","version":"v1.2.3","slug":"reason-task","repo":"k3d-manager"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch abandon --version v1.2.3 --slug reason-task --reason "superseded by v2" --yes
  [ "$status" -eq 0 ]
  reason="$(jq -r 'select(.event == "abandon" and .version == "v1.2.3" and .slug == "reason-task") | .reason' "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  [ "$reason" = "superseded by v2" ]
}

@test "codex dispatch: abandon without --version closes current release task and removes worktree and branch (M4)" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR"* ]]
  mkdir -p "$K3DM_WORKTREE_ROOT/v9.9.9/current-task"
  git -C "$FIXTURE" branch task/v9.9.9/current-task
  git -C "$FIXTURE" worktree add "$K3DM_WORKTREE_ROOT/v9.9.9/current-task" task/v9.9.9/current-task >/dev/null
  printf '{"ts":1,"event":"start","version":"v9.9.9","slug":"current-task","repo":"k3d-manager"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch abandon --slug current-task --yes
  [ "$status" -eq 0 ]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/current-task" ]
  run ! git -C "$FIXTURE" show-ref --verify --quiet refs/heads/task/v9.9.9/current-task
  run jq -c 'select(.event == "abandon" and .version == "v9.9.9" and .slug == "current-task")' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

