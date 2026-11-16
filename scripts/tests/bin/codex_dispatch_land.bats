#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load codex_dispatch_helpers

@test "codex dispatch: spec stats failure does not block dispatch or add a field" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/codex.argv" STUB_ENV="$BATS_TEST_TMPDIR/codex.env"
  export K3DM_DISPATCH_SPEC_STATS_BIN="$BATS_TEST_TMPDIR/spec-stats-fails"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$K3DM_DISPATCH_SPEC_STATS_BIN"
  chmod +x "$K3DM_DISPATCH_SPEC_STATS_BIN"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug no-spec-stats >/dev/null
  sleep 1
  jq -e 'select(.event=="start" and .slug=="no-spec-stats") | has("spec_stats") | not' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
}

@test "codex dispatch: land records commit and categorized change size" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/codex.argv" STUB_ENV="$BATS_TEST_TMPDIR/codex.env"
  export STUB_EDITS='a.txt,scripts/tests/land.bats,docs/note.md'
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug change-size >/dev/null
  sleep 1
  task="$K3DM_WORKTREE_ROOT/v9.9.9/change-size"
  git -C "$task" add a.txt scripts/tests/land.bats docs/note.md
  git -C "$task" commit -m reviewed-change >/dev/null
  dispatch land --slug change-size --no-test >/dev/null
  jq -e --arg commit "$(git -C "$FIXTURE" rev-parse HEAD)" 'select(.event=="land" and .slug=="change-size") | .commit == $commit and .change.files == 3 and .change.code == 2 and .change.tests == 2 and .change.docs == 2' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
}

@test "codex dispatch: numstat failure does not block land or record change size" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/codex.argv" STUB_ENV="$BATS_TEST_TMPDIR/codex.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug no-change-stats >/dev/null
  sleep 1
  task="$K3DM_WORKTREE_ROOT/v9.9.9/no-change-stats"
  git -C "$task" add a.txt
  git -C "$task" commit -m reviewed-change >/dev/null
  real_git="$(command -v git)"
  wrapper="$BATS_TEST_TMPDIR/git-wrapper"
  mkdir -p "$wrapper"
  cat >"$wrapper/git" <<'GIT'
#!/usr/bin/env bash
if [[ "$*" == *"diff --numstat k3d-manager-v9.9.9 HEAD"* ]]; then exit 1; fi
exec "$REAL_GIT" "$@"
GIT
  chmod +x "$wrapper/git"
  export REAL_GIT="$real_git" PATH="$wrapper:$PATH"
  run dispatch land --slug no-change-stats --no-test
  PATH="${PATH#"$wrapper:"}"
  unset REAL_GIT
  [ "$status" -eq 0 ]
  jq -e 'select(.event=="land" and .slug=="no-change-stats") | has("commit") and (has("change") | not)' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
}

@test "codex dispatch: only one same-spec slug lands without explicit superseding" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/one.argv" STUB_ENV="$BATS_TEST_TMPDIR/one.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug first >/dev/null
  sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/first" add a.txt
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/first" commit -m first >/dev/null
  dispatch land --slug first --no-test >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  git -C "$FIXTURE" fetch -q origin k3d-manager-v9.9.9:refs/remotes/origin/k3d-manager-v9.9.9
  export STUB_ARGV="$BATS_TEST_TMPDIR/two.argv" STUB_ENV="$BATS_TEST_TMPDIR/two.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug second >/dev/null
  sleep 1
  printf 'second implementation\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/second/a.txt"
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/second" add a.txt
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/second" commit -m second >/dev/null
  run dispatch land --slug second --no-test
  [ "$status" -eq 2 ]; [[ "$output" == *"spec already landed by first"* ]]
  run dispatch land --slug second --no-test --superseding first
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.event=="land" and .slug=="second")|.chosen' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = true ]
}

@test "codex dispatch: third same-spec landing names every prior round" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR/"* ]]
  [[ "$K3DM_DISPATCH_PUSHGATEWAY_URL" == http://127.0.0.1:9 ]]
  export STUB_ARGV="$BATS_TEST_TMPDIR/rounds.argv" STUB_ENV="$BATS_TEST_TMPDIR/rounds.env"
  local slug
  for slug in round1 round2 round3; do
    dispatch start --spec docs/plans/v9.9.9-demo.md --slug "$slug" >/dev/null
    sleep 1
    printf '%s implementation\n' "$slug" >"$K3DM_WORKTREE_ROOT/v9.9.9/$slug/a.txt"
    git -C "$K3DM_WORKTREE_ROOT/v9.9.9/$slug" add a.txt
    git -C "$K3DM_WORKTREE_ROOT/v9.9.9/$slug" commit -m "$slug" >/dev/null
    if [[ "$slug" != round3 ]]; then
      if [[ "$slug" == round1 ]]; then
        dispatch land --slug "$slug" --no-test >/dev/null
      else
        dispatch land --slug "$slug" --no-test --superseding round1 >/dev/null
      fi
      git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
      git -C "$FIXTURE" fetch -q origin k3d-manager-v9.9.9:refs/remotes/origin/k3d-manager-v9.9.9
    fi
  done
  run dispatch land --slug round3 --no-test
  [ "$status" -eq 2 ]
  [[ "$output" == *"round1"* ]]
  [[ "$output" == *"round2"* ]]
  run dispatch land --slug round3 --no-test --superseding round1
  [ "$status" -eq 2 ]
  [[ "$output" == *"round2"* ]]
  [[ "$output" != *"round1"* ]]
  run dispatch land --slug round3 --no-test --superseding round1 --superseding round2
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.event=="land" and .slug=="round3")|.chosen' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = true ]
}

@test "codex dispatch: land refuses a dirty operator checkout" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  printf 'dirty\n' >>"$FIXTURE/a.txt"; run dispatch land --slug one --no-test; [ "$status" -eq 2 ]
}

@test "codex dispatch: land fast-forwards without pushing" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  task_head="$(git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" rev-parse HEAD)"
  before="$(git -C "$FIXTURE" rev-parse origin/k3d-manager-v9.9.9)"; run dispatch land --slug one --no-test
  [ "$status" -eq 0 ]
  [ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$task_head" ]
  [ "$(<"$FIXTURE/a.txt")" = edited ]
  run bash -c 'git -C "$FIXTURE" worktree list --porcelain | grep -Fq "$K3DM_WORKTREE_ROOT/v9.9.9/one"'; [ "$status" -eq 1 ]
  run git -C "$FIXTURE" show-ref --verify --quiet refs/heads/task/v9.9.9/one; [ "$status" -ne 0 ]
  [ "$(git -C "$FIXTURE" rev-parse origin/k3d-manager-v9.9.9)" = "$before" ]
}

@test "codex dispatch: land refuses a missing recorded base" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  rm "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/base"
  run dispatch status one
  [[ "$output" == *"scope: unknown (no recorded base)"* ]]
  run dispatch land --slug one --no-test
  [ "$status" -eq 2 ]
  [[ "$output" == *"no recorded base"* ]]
}

@test "codex dispatch: tests the rebased task before merging" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  printf 'v1\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/one/a.txt"
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m task >/dev/null
  printf '#!/usr/bin/env bash\ngrep -qx v2 a.txt\n' >"$FIXTURE/check.sh"
  chmod +x "$FIXTURE/check.sh"
  git -C "$FIXTURE" add check.sh; git -C "$FIXTURE" commit -m check >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  before="$(git -C "$FIXTURE" rev-parse HEAD)"
  run dispatch land --slug one --test 'bash check.sh'
  [ "$status" -eq 2 ]; [[ "$output" == *"tests failed after rebase"* ]]
  [ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$before" ]
  [ "$(<"$FIXTURE/a.txt")" = original ]
  [ -e "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/land-test.log" ]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/.land.lock" ]
  run dispatch land --slug one --test 'printf "not ok 1 - failure\n"; false'
  [ "$status" -eq 2 ]; [ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$before" ]
  run dispatch land --slug one --test 'printf "ok 1 - success\n"'
  [ "$(cat "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/land-test.2.log")" = 'not ok 1 - failure' ]
  [ "$(cat "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/land-test.3.log")" = 'ok 1 - success' ]
  [ "$status" -eq 0 ]; [[ "$output" == *"tests: passed"* ]]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/.land.lock" ]
}

@test "codex dispatch: land --no-test says the tests were skipped" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  run dispatch land --slug one --no-test
  [ "$status" -eq 0 ]; [[ "$output" == *"tests: skipped (--no-test)"* ]]
}

@test "codex dispatch: land requires exactly one test selector" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  run dispatch land --slug one; [ "$status" -eq 2 ]
  run dispatch land --slug one --test true --no-test; [ "$status" -eq 2 ]
}

@test "codex dispatch: land test command sees isolated state" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  run dispatch land --slug one --test '[[ "$K3DM_JOB_DIR" == *one.run/state/jobs ]]'
  [ "$status" -eq 0 ]; [[ "$output" == *"tests: passed"* ]]
}

@test "codex dispatch: landing lock is released after refusal" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  mkdir "$K3DM_WORKTREE_ROOT/v9.9.9/.land.lock"; sleep 30 & lock_pid=$!; printf '%s\n' "$lock_pid" >"$K3DM_WORKTREE_ROOT/v9.9.9/.land.lock/pid"
  run dispatch land --slug one --no-test; [ "$status" -eq 2 ]; [[ "$output" == *"another land is in progress"* ]]
  kill "$lock_pid" 2>/dev/null || true; wait "$lock_pid" 2>/dev/null || true
  printf '999999\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/.land.lock/pid"
  run dispatch land --slug one --no-test; [ "$status" -eq 0 ]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/.land.lock" ]
}

