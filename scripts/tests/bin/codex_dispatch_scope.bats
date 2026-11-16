#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load codex_dispatch_helpers

@test "codex dispatch: status marks memory-bank changes out of scope" {
  export STUB_EDITS=memory-bank/x.md
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  run dispatch status
  [ "$status" -eq 0 ]; [[ "$output" == *"out-of-scope: memory-bank/x.md"* ]]
}

@test "codex dispatch: land refuses running, out-of-scope, and dirty tasks" {
  export STUB_SLEEP=5 STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  run dispatch land --slug one --no-test; [ "$status" -eq 2 ]
  sleep 6
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  printf 'out\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/one/memory-bank/x.md"
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add memory-bank/x.md; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m out >/dev/null
  run dispatch land --slug one --no-test; [ "$status" -eq 2 ]
  printf 'dirty\n' >>"$K3DM_WORKTREE_ROOT/v9.9.9/one/a.txt"
  run dispatch land --slug one --no-test; [ "$status" -eq 2 ]
}

@test "codex dispatch: prune removes landed current and earlier release tasks and branch-only leftovers" {
  mkdir -p "$K3DM_WORKTREE_ROOT/v9.9.8"
  git -C "$FIXTURE" branch task/v9.9.9/current
  git -C "$FIXTURE" worktree add "$K3DM_WORKTREE_ROOT/v9.9.9/current" task/v9.9.9/current >/dev/null
  git -C "$FIXTURE" checkout -b k3d-manager-v9.9.8 >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.8
  git -C "$FIXTURE" checkout k3d-manager-v9.9.9 >/dev/null
  git -C "$FIXTURE" fetch -q origin k3d-manager-v9.9.8:refs/remotes/origin/k3d-manager-v9.9.8
  git -C "$FIXTURE" branch task/v9.9.8/older origin/k3d-manager-v9.9.8
  git -C "$FIXTURE" worktree add "$K3DM_WORKTREE_ROOT/v9.9.8/older" task/v9.9.8/older >/dev/null
  git -C "$FIXTURE" branch task/v9.9.9/orphan
  run dispatch prune
  [ "$status" -eq 0 ]; [[ "$output" == *"would prune: v9.9.9/current"* ]]; [[ "$output" == *"would prune: v9.9.8/older"* ]]; [[ "$output" == *"would prune: v9.9.9/orphan"* ]]
  [ -d "$K3DM_WORKTREE_ROOT/v9.9.9/current" ]; [ -d "$K3DM_WORKTREE_ROOT/v9.9.8/older" ]
  git -C "$FIXTURE" show-ref --verify --quiet refs/heads/task/v9.9.9/orphan
  run dispatch prune --yes
  [ "$status" -eq 0 ]; [[ "$output" == *"pruned: 3 kept: 0"* ]]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/current" ]; [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.8/older" ]
  run ! git -C "$FIXTURE" show-ref --verify --quiet refs/heads/task/v9.9.9/current
  run ! git -C "$FIXTURE" show-ref --verify --quiet refs/heads/task/v9.9.8/older
  run ! git -C "$FIXTURE" show-ref --verify --quiet refs/heads/task/v9.9.9/orphan
}

@test "codex dispatch: prune keeps unsafe tasks and preserves run research data" {
  git -C "$FIXTURE" branch task/v9.9.9/dirty
  git -C "$FIXTURE" worktree add "$K3DM_WORKTREE_ROOT/v9.9.9/dirty" task/v9.9.9/dirty >/dev/null
  printf 'dirty\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/dirty/a.txt"
  git -C "$FIXTURE" checkout -b task/v9.9.9/ahead
  printf 'ahead\n' >"$FIXTURE/ahead.txt"; git -C "$FIXTURE" add ahead.txt; git -C "$FIXTURE" commit -m ahead >/dev/null
  git -C "$FIXTURE" checkout k3d-manager-v9.9.9 >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  git -C "$FIXTURE" branch task/v9.9.9/running
  mkdir -p "$K3DM_WORKTREE_ROOT/v9.9.9/ahead.run" "$K3DM_WORKTREE_ROOT/v9.9.9/running.run"
  printf 'not-json\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  printf 'metrics\n' >"$K3DM_WORKTREE_ROOT/metrics.log"
  printf 'research\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/ahead.run/codex.log"
  printf '%s\n' "$$" >"$K3DM_WORKTREE_ROOT/v9.9.9/running.run/pid"
  before="$(find "$K3DM_WORKTREE_ROOT" -name '*.run' -type f -print | sort | xargs shasum)"
  run dispatch prune
  [ "$status" -eq 0 ]; [[ "$output" == *"keep: v9.9.9/ahead (unapplied commits)"* ]]; [[ "$output" == *"keep: v9.9.9/dirty (uncommitted changes)"* ]]; [[ "$output" == *"keep: v9.9.9/running (worker running)"* ]]
  [[ "$output" == *"pruned: 0 kept: 3"* ]]
  run dispatch prune --yes
  [ "$status" -eq 0 ]; [[ "$output" == *"pruned: 0 kept: 3"* ]]
  [ -d "$K3DM_WORKTREE_ROOT/v9.9.9/dirty" ]; git -C "$FIXTURE" show-ref --verify --quiet refs/heads/task/v9.9.9/ahead
  [ "$before" = "$(find "$K3DM_WORKTREE_ROOT" -name '*.run' -type f -print | sort | xargs shasum)" ]
  [ "$(<"$K3DM_WORKTREE_ROOT/ledger.jsonl")" = not-json ]; [ "$(<"$K3DM_WORKTREE_ROOT/metrics.log")" = metrics ]
}

@test "codex dispatch: prune rejects unknown options" {
  run dispatch prune --force
  [ "$status" -eq 2 ]; [[ "$output" == *"unknown prune option"* ]]
}

@test "codex dispatch: scope uses the recorded spec, not a root markdown file" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  run dispatch start --spec docs/plans/v9.9.9-demo.md; [ "$status" -eq 0 ]; sleep 1
  [ -d "$K3DM_WORKTREE_ROOT/v9.9.9/demo" ]
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/demo.run/spec")" = docs/plans/v9.9.9-demo.md ]
  run dispatch status demo
  [ "$status" -eq 0 ]; [[ "$output" == *"scope: in-scope"* ]]
}

@test "codex dispatch: memory-bank is out of scope even when the spec lists it" {
  printf '| `memory-bank/x.md` |\n' >>"$FIXTURE/docs/plans/v9.9.9-demo.md"
  git -C "$FIXTURE" commit -qam "list memory-bank"; git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  export STUB_EDITS=memory-bank/x.md STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  run dispatch status one
  [[ "$output" == *"out-of-scope: memory-bank/x.md"* ]]
}

@test "codex dispatch: edited spec cannot widen scope" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  printf '| `b.txt` |\n' >>"$K3DM_WORKTREE_ROOT/v9.9.9/one/docs/plans/v9.9.9-demo.md"
  printf 'edited\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/one/b.txt"
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt b.txt docs/plans/v9.9.9-demo.md
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m widen >/dev/null
  run dispatch status one
  [[ "$output" == *"out-of-scope: b.txt"* ]]
  [[ "$output" == *"out-of-scope: docs/plans/v9.9.9-demo.md"* ]]
  run dispatch land --slug one --no-test
  [ "$status" -eq 2 ]
}

@test "codex dispatch: scope ignores commits pushed after dispatch" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  printf 'release change\n' >"$FIXTURE/release.txt"
  git -C "$FIXTURE" add release.txt; git -C "$FIXTURE" commit -m release-change >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  git -C "$FIXTURE" fetch -q origin k3d-manager-v9.9.9:refs/remotes/origin/k3d-manager-v9.9.9
  run dispatch status one
  [[ "$output" != *"release.txt"* ]]
}

@test "codex dispatch: ledger records scope refusal and valid JSON" {
  export STUB_EDITS=b.txt STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  printf 'out of scope\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/one/b.txt"
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add b.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m out >/dev/null
  run dispatch land --slug one --no-test
  [ "$status" -eq 2 ]
  grep -q '"event":"land_refused"' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  while IFS= read -r line; do jq -e . >/dev/null <<<"$line"; done <"$K3DM_WORKTREE_ROOT/ledger.jsonl"
}

@test "codex dispatch: instruction files require explicit land authorization" {
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR/fixture" ]]
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/worktrees" ]]
  [[ "$K3DM_DISPATCH_PUSHGATEWAY_URL" == http://127.0.0.1:9 ]]
  export STUB_ARGV="$BATS_TEST_TMPDIR/guard.argv" STUB_ENV="$BATS_TEST_TMPDIR/guard.env"
  sed -i.bak '/| `a.txt` |/a\
| `AGENTS.md` |' "$FIXTURE/docs/plans/v9.9.9-demo.md"
  rm -f "$FIXTURE/docs/plans/v9.9.9-demo.md.bak"
  git -C "$FIXTURE" add docs/plans/v9.9.9-demo.md; git -C "$FIXTURE" commit -qm list-instruction-file
  git -C "$FIXTURE" push origin k3d-manager-v9.9.9 >/dev/null
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug protected >/dev/null; sleep 1
  local task="$K3DM_WORKTREE_ROOT/v9.9.9/protected" before
  printf 'new instruction\n' >"$task/AGENTS.md"
  git -C "$task" add AGENTS.md a.txt; git -C "$task" commit -qm protected
  before="$(git -C "$FIXTURE" rev-parse k3d-manager-v9.9.9)"
  run dispatch land --slug protected --no-test
  [ "$status" -eq 2 ]
  [[ "$output" == *'instruction-file: AGENTS.md'* ]]
  run dispatch land --slug protected --no-test --allow-out-of-scope
  [ "$status" -eq 2 ]
  [[ "$output" == *'instruction-file: AGENTS.md'* && "$output" == *'+new instruction'* ]]
  [ "$(git -C "$FIXTURE" rev-parse k3d-manager-v9.9.9)" = "$before" ]
  jq -e -s 'any(.[]; .slug=="protected" and .event=="land_refused" and .reason=="scope" and .detail=="instruction-files")' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
  if jq -e -s 'any(.[]; .slug=="protected" and .event=="land")' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null; then false; fi
  run dispatch land --slug protected --no-test --allow-out-of-scope --allow-instruction-files
  [ "$status" -eq 0 ]
  jq -e -s 'any(.[]; .slug=="protected" and .event=="land" and (.instruction_files|index("AGENTS.md")))' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
}

@test "codex dispatch: instruction path patterns cover nested names and uncommitted files" {
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR/fixture" ]]
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/worktrees" ]]
  export STUB_ARGV="$BATS_TEST_TMPDIR/pattern.argv" STUB_ENV="$BATS_TEST_TMPDIR/pattern.env"
  local path slug task
  for path in scripts/lib/foundation/CLAUDE.md .claude/hooks/x.sh .github/copilot-instructions.md nested/.envrc nested/.mcp.json; do
    slug="pattern-$RANDOM"
    dispatch start --spec docs/plans/v9.9.9-demo.md --slug "$slug" >/dev/null; sleep 1
    task="$K3DM_WORKTREE_ROOT/v9.9.9/$slug"
    mkdir -p "$task/${path%/*}" 2>/dev/null || true
    printf 'protected change\n' >"$task/$path"
    git -C "$task" add "$path" a.txt; git -C "$task" commit -qm protected
    run dispatch land --slug "$slug" --no-test --allow-out-of-scope
    [ "$status" -eq 2 ]
    [[ "$output" == *"instruction-file: $path"* ]]
  done
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug untracked >/dev/null; sleep 1
  task="$K3DM_WORKTREE_ROOT/v9.9.9/untracked"
  git -C "$task" add a.txt; git -C "$task" commit -qm baseline-edit
  mkdir -p "$task/nested"
  printf 'tracked marker\n' >"$task/nested/AGENTS.md"
  git -C "$task" add nested/AGENTS.md; git -C "$task" commit -qm tracked-instruction
  printf 'uncommitted marker\n' >>"$task/nested/AGENTS.md"
  printf 'untracked marker\n' >"$task/nested/CLAUDE.md"
  run dispatch land --slug untracked --no-test --allow-out-of-scope
  [ "$status" -eq 2 ]
  [[ "$output" == *'instruction-file: nested/AGENTS.md'* && "$output" == *'+uncommitted marker'* ]]
  [[ "$output" == *'instruction-file: nested/CLAUDE.md'* && "$output" == *'+untracked marker'* ]]
}

@test "codex dispatch: ordinary scope rules remain unchanged" {
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR/fixture" ]]
  export STUB_ARGV="$BATS_TEST_TMPDIR/scope.argv" STUB_ENV="$BATS_TEST_TMPDIR/scope.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug ordinary >/dev/null; sleep 1
  local task="$K3DM_WORKTREE_ROOT/v9.9.9/ordinary"
  printf 'changed\n' >"$task/a.txt"
  git -C "$task" add a.txt; git -C "$task" commit -qm ordinary
  run dispatch land --slug ordinary --no-test
  [ "$status" -eq 0 ]
  git -C "$FIXTURE" push origin k3d-manager-v9.9.9 >/dev/null
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug extra >/dev/null; sleep 1
  task="$K3DM_WORKTREE_ROOT/v9.9.9/extra"
  printf 'out of scope\n' >"$task/extra.txt"
  git -C "$task" add extra.txt a.txt; git -C "$task" commit -qm extra
  run dispatch land --slug extra --no-test
  [ "$status" -eq 2 ]
  run dispatch land --slug extra --no-test --allow-out-of-scope --superseding ordinary
  [ "$status" -eq 0 ]
}

