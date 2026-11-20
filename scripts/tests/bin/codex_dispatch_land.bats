#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load codex_dispatch_helpers

@test "codex dispatch: land marks approved plan Status after landed marker" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR/"* ]]
  printf '# Test spec\n\n**Status:** DRAFT v5 — notes\n**Intent approved:** operator, 2026-11-19\n\n## Files\n\n| File |\n|---|\n| `a.txt` |\n' >"$FIXTURE/docs/plans/v9.9.9-demo.md"
  git -C "$FIXTURE" add docs/plans/v9.9.9-demo.md
  git -C "$FIXTURE" commit -m 'draft status fixture' >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  export STUB_ARGV="$BATS_TEST_TMPDIR/status.argv" STUB_ENV="$BATS_TEST_TMPDIR/status.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug status-land >/dev/null
  sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/status-land" add a.txt
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/status-land" commit -m reviewed-change >/dev/null
  mkdir -p "$FIXTURE/.git/hooks"
  printf '#!/usr/bin/env bash\ntest -f "$K3DM_WORKTREE_ROOT/v9.9.9/status-land.run/landed"\n' >"$FIXTURE/.git/hooks/pre-commit"
  chmod +x "$FIXTURE/.git/hooks/pre-commit"
  run dispatch land --slug status-land --no-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"land: plan status set LANDED in docs/plans/v9.9.9-demo.md"* ]]
  [[ "$output" == *"landed: status-land"* ]]
  grep -Eq '^\*\*Status:\*\* LANDED — [0-9a-f]{8} \(auto: land [0-9]{4}-[0-9]{2}-[0-9]{2}; verify pending\); notes$' "$FIXTURE/docs/plans/v9.9.9-demo.md"
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/status-land.run/landed" ]
  [ ! -d "$K3DM_WORKTREE_ROOT/v9.9.9/status-land" ]
  [ "$(git -C "$FIXTURE" show --pretty='' --name-only HEAD)" = "docs/plans/v9.9.9-demo.md" ]
}

@test "codex dispatch: failed plan status commit does not block land or leave a dirty spec" {
  printf '# Test spec\n\n**Status:** READY — notes\n**Intent approved:** operator, 2026-11-19\n\n## Files\n\n| File |\n|---|\n| `a.txt` |\n' >"$FIXTURE/docs/plans/v9.9.9-demo.md"
  git -C "$FIXTURE" add docs/plans/v9.9.9-demo.md
  git -C "$FIXTURE" commit -m 'ready status fixture' >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  export STUB_ARGV="$BATS_TEST_TMPDIR/status-fail.argv" STUB_ENV="$BATS_TEST_TMPDIR/status-fail.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug status-commit-fails >/dev/null
  sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/status-commit-fails" add a.txt
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/status-commit-fails" commit -m reviewed-change >/dev/null
  local task_sha
  task_sha="$(git -C "$K3DM_WORKTREE_ROOT/v9.9.9/status-commit-fails" rev-parse HEAD)"
  mkdir -p "$FIXTURE/.git/hooks"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$FIXTURE/.git/hooks/pre-commit"
  chmod +x "$FIXTURE/.git/hooks/pre-commit"
  run dispatch land --slug status-commit-fails --no-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"land: plan status not updated (commit failed); set it by hand"* ]]
  [[ "$output" == *"landed: status-commit-fails"* ]]
  grep -q '^\*\*Status:\*\* READY — notes$' "$FIXTURE/docs/plans/v9.9.9-demo.md"
  [ -z "$(git -C "$FIXTURE" status --porcelain -- docs/plans/v9.9.9-demo.md)" ]
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/status-commit-fails.run/landed" ]
  [ ! -d "$K3DM_WORKTREE_ROOT/v9.9.9/status-commit-fails" ]
  [ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$task_sha" ]
}

@test "codex dispatch: terminal and verified plan statuses stay unchanged; auto LANDED is refreshed" {
  local status_value slug spec task task_sha first_word
  for status_value in LANDED VERIFIED SUPERSEDED; do
    slug="leave-${status_value,,}"
    spec="docs/plans/${slug}.md"
    printf '# Spec\n\n**Status:** %s — notes\n**Intent approved:** operator, 2026-11-19\n\n## Files\n\n| File |\n|---|\n| `a.txt` |\n' "$status_value" >"$FIXTURE/$spec"
    git -C "$FIXTURE" add "$spec"
    git -C "$FIXTURE" commit -m "fixture $status" >/dev/null
    git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
    export STUB_ARGV="$BATS_TEST_TMPDIR/$slug.argv" STUB_ENV="$BATS_TEST_TMPDIR/$slug.env"
    dispatch start --spec "$spec" --slug "$slug" >/dev/null
    sleep 1
    task="$K3DM_WORKTREE_ROOT/v9.9.9/$slug"
    printf 'landed %s\n' "$slug" >"$task/a.txt"
    git -C "$task" add a.txt
    git -C "$task" commit -m "$slug" >/dev/null
    task_sha="$(git -C "$task" rev-parse HEAD)"
    run dispatch land --slug "$slug" --no-test
    [ "$status" -eq 0 ]
    first_word="${status_value%% *}"
    [[ "$output" == *"land: plan status left as $first_word"* ]]
    [[ "$output" == *"landed: $slug"* ]]
    grep -Fqx "**Status:** $status_value — notes" "$FIXTURE/$spec"
    [ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$task_sha" ]
    git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  done

  slug=refresh-auto
  spec="docs/plans/$slug.md"
  printf '# Spec\n\n**Status:** LANDED — deadbeef (auto: land 2026-11-18; verify pending); notes\n**Intent approved:** operator, 2026-11-19\n\n## Files\n\n| File |\n|---|\n| `a.txt` |\n' >"$FIXTURE/$spec"
  git -C "$FIXTURE" add "$spec"
  git -C "$FIXTURE" commit -m 'fixture old auto status' >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  export STUB_ARGV="$BATS_TEST_TMPDIR/$slug.argv" STUB_ENV="$BATS_TEST_TMPDIR/$slug.env"
  dispatch start --spec "$spec" --slug "$slug" >/dev/null
  sleep 1
  task="$K3DM_WORKTREE_ROOT/v9.9.9/$slug"
  printf 'auto refresh\n' >"$task/a.txt"
  git -C "$task" add a.txt
  git -C "$task" commit -m "$slug" >/dev/null
  task_sha="$(git -C "$task" rev-parse HEAD)"
  run dispatch land --slug "$slug" --no-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"land: plan status set LANDED in $spec"* ]]
  grep -q "^\\*\\*Status:\\*\\* LANDED — ${task_sha:0:8} (auto: land [0-9-]*; verify pending); notes$" "$FIXTURE/$spec"
}

@test "codex dispatch: dirty worktree index and untracked spec each leave land complete" {
  local mode slug spec task task_sha reason real_git wrapper
  for mode in worktree index untracked; do
    slug="dirty-$mode"
    spec="docs/plans/$slug.md"
    printf '# Test spec\n\n**Status:** DRAFT — %s notes\n**Intent approved:** operator, 2026-11-19\n\n## Files\n\n| File |\n|---|\n| `a.txt` |\n' "$mode" >"$FIXTURE/$spec"
    git -C "$FIXTURE" add "$spec"
    git -C "$FIXTURE" commit -m "fixture $mode" >/dev/null
    git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
    export STUB_ARGV="$BATS_TEST_TMPDIR/$slug.argv" STUB_ENV="$BATS_TEST_TMPDIR/$slug.env"
    dispatch start --spec "$spec" --slug "$slug" >/dev/null
    sleep 1
    task="$K3DM_WORKTREE_ROOT/v9.9.9/$slug"
    printf 'land %s\n' "$slug" >"$task/a.txt"
    git -C "$task" add a.txt
    git -C "$task" commit -m "$slug" >/dev/null
    task_sha="$(git -C "$task" rev-parse HEAD)"
    real_git="$(command -v git)"
    wrapper="$BATS_TEST_TMPDIR/$slug-bin"
    mkdir -p "$wrapper"
    cat >"$wrapper/git" <<'GIT'
#!/usr/bin/env bash
if [[ "$*" == *" branch -d task/v9.9.9/$STATUS_MUTATE_SLUG"* ]]; then
  "$REAL_GIT" "$@" || exit $?
  printf '\noperator mutation\n' >>"$FIXTURE/$STATUS_MUTATE_SPEC"
  case "$STATUS_MUTATE_MODE" in
    index) "$REAL_GIT" -C "$FIXTURE" add -- "$STATUS_MUTATE_SPEC" ;;
    untracked) "$REAL_GIT" -C "$FIXTURE" rm --cached -q -- "$STATUS_MUTATE_SPEC" ;;
  esac
  exit 0
fi
exec "$REAL_GIT" "$@"
GIT
    chmod +x "$wrapper/git"
    export REAL_GIT="$real_git" FIXTURE STATUS_MUTATE_SLUG="$slug" STATUS_MUTATE_MODE="$mode" STATUS_MUTATE_SPEC="$spec"
    export PATH="$wrapper:$PATH"
    run dispatch land --slug "$slug" --no-test
    PATH="${PATH#"$wrapper:"}"
    unset REAL_GIT STATUS_MUTATE_SLUG STATUS_MUTATE_MODE STATUS_MUTATE_SPEC
    [ "$status" -eq 0 ]
    if [[ "$mode" == untracked ]]; then
      [[ "$output" == *"land: plan status not updated (spec not tracked in "*"; set it by hand"* ]]
    else
      reason="spec has local changes"
      [[ "$output" == *"land: plan status not updated ($reason); set it by hand"* ]]
    fi
    [[ "$output" == *"landed: $slug"* ]]
    [ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$task_sha" ]
    [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/$slug.run/landed" ]
    [ ! -d "$K3DM_WORKTREE_ROOT/v9.9.9/$slug" ]
    git -C "$FIXTURE" reset -q HEAD -- "$spec"
    git -C "$FIXTURE" checkout -q HEAD -- "$spec"
    [ -z "$(git -C "$FIXTURE" status --porcelain -- "$spec")" ]
    git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  done
}

@test "codex dispatch: review pending review child bug spec and no-status plan skip status writes" {
  local mode slug spec task task_sha
  for mode in review-pending review-child bug-spec no-status; do
    slug="skip-$mode"
    if [[ "$mode" == bug-spec ]]; then
      spec=docs/bugs/skip-status.md
      mkdir -p "$FIXTURE/docs/bugs"
      printf '# Bug spec\n\n**Status:** DRAFT\n**Intent approved:** operator, 2026-11-19\n\n## Files\n\n| File |\n|---|\n| `a.txt` |\n' >"$FIXTURE/$spec"
    elif [[ "$mode" == no-status ]]; then
      spec=docs/plans/v9.9.9-demo.md
      printf '# Plan without Status\n\n**Intent approved:** operator, 2026-11-19\n\n## Files\n\n| File |\n|---|\n| `a.txt` |\n' >"$FIXTURE/$spec"
    else
      spec="docs/plans/$slug.md"
      printf '# Plan\n\n**Status:** DRAFT — notes\n**Intent approved:** operator, 2026-11-19\n\n## Files\n\n| File |\n|---|\n| `a.txt` |\n' >"$FIXTURE/$spec"
    fi
    git -C "$FIXTURE" add "$spec"
    git -C "$FIXTURE" commit -m "fixture $mode" >/dev/null
    git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
    export STUB_ARGV="$BATS_TEST_TMPDIR/$slug.argv" STUB_ENV="$BATS_TEST_TMPDIR/$slug.env"
    if [[ "$mode" == review-child ]]; then
      dispatch start --spec "$spec" --slug "$slug" --parent parent-task --role review >/dev/null
    else
      dispatch start --spec "$spec" --slug "$slug" >/dev/null
    fi
    sleep 1
    task="$K3DM_WORKTREE_ROOT/v9.9.9/$slug"
    printf 'land %s\n' "$slug" >"$task/a.txt"
    git -C "$task" add a.txt
    git -C "$task" commit -m "$slug" >/dev/null
    task_sha="$(git -C "$task" rev-parse HEAD)"
    if [[ "$mode" == review-pending ]]; then
      run dispatch land --slug "$slug" --no-test --review-pending
    else
      run dispatch land --slug "$slug" --no-test
    fi
    [ "$status" -eq 0 ]
    [[ "$output" != *"land: plan status"* ]]
    [[ "$output" == *"landed: $slug"* ]]
    [ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$task_sha" ]
    [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/$slug.run/landed" ]
    [ ! -d "$K3DM_WORKTREE_ROOT/v9.9.9/$slug" ]
    git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  done
}

@test "codex dispatch: nonzero status helper cannot change successful land result" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/nonzero-helper.argv" STUB_ENV="$BATS_TEST_TMPDIR/nonzero-helper.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug helper-nonzero >/dev/null
  sleep 1
  task="$K3DM_WORKTREE_ROOT/v9.9.9/helper-nonzero"
  git -C "$task" add a.txt
  git -C "$task" commit -m helper-nonzero >/dev/null
  stub_root="$BATS_TEST_TMPDIR/dispatcher-stub"
  mkdir -p "$stub_root/bin"
  cp "$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch" "$stub_root/bin/k3dm-codex-dispatch"
  ln -s "$BATS_TEST_DIRNAME/../../../scripts" "$stub_root/scripts"
  python3 - "$stub_root/bin/k3dm-codex-dispatch" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
start = s.index("_dispatch_mark_plan_landed() {")
end = s.index("\n_dispatch_handoff()", start)
s = s[:start] + "_dispatch_mark_plan_landed() { return 1; }\n" + s[end:]
p.write_text(s)
PY
  chmod +x "$stub_root/bin/k3dm-codex-dispatch"
  export DISPATCH_STUB="$stub_root/bin/k3dm-codex-dispatch"
  run bash -c 'cd "$FIXTURE" && "$DISPATCH_STUB" land --slug helper-nonzero --no-test'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"landed: helper-nonzero"* ]]
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/helper-nonzero.run/landed" ]
}

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

@test "codex dispatch: land accepts a finished run whose PID was reused" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR/"* ]]
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  sleep 1
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  sleep 30 & sleeper=$!
  printf '%s\n' "$sleeper" >"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/pid"
  printf 'pid=%s\nprocess_start=not-the-worker\n' "$sleeper" >"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/start"
  kill -0 "$sleeper"
  run dispatch land --slug one --no-test
  kill "$sleeper"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Codex is still running"* ]]
}

@test "codex dispatch: land accepts a dead worker whose PID identity is stale" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR/"* ]]
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  sleep 1
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  sleep 30 & sleeper=$!
  printf '%s\n' "$sleeper" >"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/pid"
  printf 'pid=%s\nprocess_start=not-the-worker\n' "$sleeper" >"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/start"
  rm "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit"
  kill -0 "$sleeper"
  run dispatch land --slug one --no-test
  kill "$sleeper"
  [ "$status" -eq 0 ]
}

@test "codex dispatch: land refuses while the worker is still running" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR/"* ]]
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  export STUB_SLEEP=5
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  sleep 1
  run dispatch land --slug one --no-test
  [ "$status" -eq 2 ]
  [[ "$output" == *"Codex is still running"* ]]
  sleep 5
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

