#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load codex_dispatch_helpers

@test "codex dispatch: open lists only unfinished tasks without writes" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  # Event shapes copied from the M4 ledger, 2026-11-01.
  cat >"$K3DM_WORKTREE_ROOT/ledger.jsonl" <<'LEDGER'
{"ts":1,"event":"start","version":"v9.9.9","slug":"pending","repo":"k3d-manager"}
{"ts":2,"event":"codex_exit","version":"v9.9.9","slug":"pending","repo":"k3d-manager"}
{"ts":1,"event":"start","version":"v9.9.9","slug":"done","repo":"k3d-manager"}
{"ts":2,"event":"land","version":"v9.9.9","slug":"done","repo":"k3d-manager"}
{"ts":1,"event":"start","version":"v8.0.0","slug":"other","repo":"k3d-manager"}
LEDGER
  cp "$K3DM_WORKTREE_ROOT/ledger.jsonl" "$BATS_TEST_TMPDIR/before"
  run dispatch open --version v9.9.9
  [ "$status" -eq 1 ]; [[ "$output" == *"v9.9.9 pending "*" codex_exit"* ]]
  [[ "$output" != *done* && "$output" != *other* ]]
  run dispatch open --version v7.0.0
  [ "$status" -eq 0 ]; [ -z "$output" ]
  cmp "$BATS_TEST_TMPDIR/before" "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  [ "$(find "$K3DM_WORKTREE_ROOT" -mindepth 1 | wc -l | tr -d ' ')" -eq 1 ]
}

@test "codex dispatch: land ignores target instruction changes after task dispatch" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR/"* ]]
  export STUB_ARGV="$BATS_TEST_TMPDIR/rebased.argv" STUB_ENV="$BATS_TEST_TMPDIR/rebased.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug rebased >/dev/null
  sleep 1
  local task="$K3DM_WORKTREE_ROOT/v9.9.9/rebased"
  printf 'task change\n' >"$task/a.txt"
  git -C "$task" add a.txt
  git -C "$task" commit -m task >/dev/null
  printf 'release instruction\n' >"$FIXTURE/CLAUDE.md"
  git -C "$FIXTURE" add CLAUDE.md
  git -C "$FIXTURE" commit -m release-instruction >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  git -C "$task" fetch -q origin
  git -C "$task" rebase -q origin/k3d-manager-v9.9.9
  run dispatch land --slug rebased --no-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"landed: rebased"* ]]
  [ -z "$(jq -c 'select(.event=="land" and .slug=="rebased")|.instruction_files|.[]' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" ]
  [ "$(<"$FIXTURE/CLAUDE.md")" = 'release instruction' ]
}

@test "codex dispatch: rebased task instruction edits are still refused and shown" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR/"* ]]
  export STUB_ARGV="$BATS_TEST_TMPDIR/rebased-own.argv" STUB_ENV="$BATS_TEST_TMPDIR/rebased-own.env"
  printf 'task slot\nmiddle one\nmiddle two\nmiddle three\nmiddle four\nmiddle five\nmiddle six\nmiddle seven\nrelease slot\n' >"$FIXTURE/CLAUDE.md"
  git -C "$FIXTURE" add CLAUDE.md
  git -C "$FIXTURE" commit -m instruction-base >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug rebased-own >/dev/null
  sleep 1
  local task="$K3DM_WORKTREE_ROOT/v9.9.9/rebased-own"
  printf 'task instruction line\nmiddle one\nmiddle two\nmiddle three\nmiddle four\nmiddle five\nmiddle six\nmiddle seven\nrelease slot\n' >"$task/CLAUDE.md"
  git -C "$task" add CLAUDE.md a.txt
  git -C "$task" commit -m task-instruction >/dev/null
  printf 'task slot\nmiddle one\nmiddle two\nmiddle three\nmiddle four\nmiddle five\nmiddle six\nmiddle seven\nrelease instruction\n' >"$FIXTURE/CLAUDE.md"
  git -C "$FIXTURE" add CLAUDE.md
  git -C "$FIXTURE" commit -m release-instruction >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  git -C "$task" fetch -q origin
  git -C "$task" rebase -q origin/k3d-manager-v9.9.9
  run dispatch land --slug rebased-own --no-test --allow-out-of-scope
  [ "$status" -eq 2 ]
  [[ "$output" == *"instruction files require --allow-instruction-files"* ]]
  [[ "$output" == *"+task instruction line"* ]]
  [[ "$output" != *"+release instruction"* ]]
}

@test "codex dispatch: rebased land still refuses uncommitted protected files" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  export STUB_ARGV="$BATS_TEST_TMPDIR/rebased-dirty.argv" STUB_ENV="$BATS_TEST_TMPDIR/rebased-dirty.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug rebased-dirty >/dev/null
  sleep 1
  local task="$K3DM_WORKTREE_ROOT/v9.9.9/rebased-dirty"
  printf 'task change\n' >"$task/a.txt"
  git -C "$task" add a.txt
  git -C "$task" commit -m task >/dev/null
  printf 'release instruction\n' >"$FIXTURE/CLAUDE.md"
  git -C "$FIXTURE" add CLAUDE.md
  git -C "$FIXTURE" commit -m release-instruction >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  git -C "$task" fetch -q origin
  git -C "$task" rebase -q origin/k3d-manager-v9.9.9
  printf 'uncommitted instruction\n' >"$task/AGENTS.md"
  run dispatch land --slug rebased-dirty --no-test --allow-out-of-scope
  [ "$status" -eq 2 ]
  [[ "$output" == *"instruction files require --allow-instruction-files"* ]]
  [[ "$output" == *"+uncommitted instruction"* ]]
}

@test "codex dispatch: non-ancestor recorded base keeps instruction range" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  export STUB_ARGV="$BATS_TEST_TMPDIR/rewritten-base.argv" STUB_ENV="$BATS_TEST_TMPDIR/rewritten-base.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug rewritten-base >/dev/null
  sleep 1
  local task="$K3DM_WORKTREE_ROOT/v9.9.9/rewritten-base"
  printf 'task change\n' >"$task/a.txt"
  git -C "$task" add a.txt
  git -C "$task" commit -m task >/dev/null
  printf 'release instruction\n' >"$FIXTURE/CLAUDE.md"
  git -C "$FIXTURE" add CLAUDE.md
  git -C "$FIXTURE" commit -m release-instruction >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  git -C "$task" fetch -q origin
  git -C "$task" rebase -q origin/k3d-manager-v9.9.9
  # A rewritten, unrelated recorded base must fail the ancestor check and remain the range start.
  local rewritten_base
  rewritten_base="$(git -C "$task" commit-tree HEAD^{tree} -m unrelated-base)"
  printf '%s\n' "$rewritten_base" >"$K3DM_WORKTREE_ROOT/v9.9.9/rewritten-base.run/base"
  local helper_dir="$BATS_TEST_TMPDIR/helper-source"
  mkdir -p "$helper_dir/bin"
  ln -s "$BATS_TEST_DIRNAME/../../../scripts" "$helper_dir/scripts"
  sed '$d' "$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch" >"$helper_dir/bin/dispatcher"
  export TASK="$task" HELPER="$helper_dir/bin/dispatcher" RECORDED_BASE="$rewritten_base"
  run bash -c 'source "$HELPER"; _dispatch_instruction_range_start "$TASK" k3d-manager-v9.9.9 "$RECORDED_BASE"'
  [ "$status" -eq 0 ]
  [ "$output" = "$rewritten_base" ]
}

@test "codex dispatch: without rebase instruction changes retain the override" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  printf '# Test spec\n\n**Intent approved:** operator, 2026-11-22\n\n## Files\n\n| File |\n|---|\n| `a.txt` |\n| `CLAUDE.md` |\n' >"$FIXTURE/docs/plans/v9.9.9-demo.md"
  git -C "$FIXTURE" add docs/plans/v9.9.9-demo.md
  git -C "$FIXTURE" commit -m instruction-in-scope >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  export STUB_ARGV="$BATS_TEST_TMPDIR/no-rebase.argv" STUB_ENV="$BATS_TEST_TMPDIR/no-rebase.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug no-rebase >/dev/null
  sleep 1
  local task="$K3DM_WORKTREE_ROOT/v9.9.9/no-rebase"
  printf 'task instruction line\n' >"$task/CLAUDE.md"
  git -C "$task" add CLAUDE.md a.txt
  git -C "$task" commit -m task-instruction >/dev/null
  run dispatch land --slug no-rebase --no-test
  [ "$status" -eq 2 ]
  [[ "$output" == *"instruction files require --allow-instruction-files"* ]]
  [[ "$output" == *"+task instruction line"* ]]
  run dispatch land --slug no-rebase --no-test --allow-instruction-files
  [ "$status" -eq 0 ]
}

