#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load codex_dispatch_helpers

@test "codex dispatch: metrics scheduling coalesces concurrent requests and preserves the last request" {
  local source_file="$BATS_TEST_TMPDIR/dispatcher-functions.sh"
  sed '/^main "\$@"$/d; s|source "${_dispatch_script_dir}/../scripts/lib/system.sh"|source "'"$BATS_TEST_DIRNAME"'/../../lib/system.sh"|' "$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch" >"$source_file"
  run bash -c 'source "$1"; for _ in {1..20}; do _dispatch_schedule_metrics; done' _ "$source_file"
  [ "$status" -eq 0 ]
  for _ in {1..50}; do [[ ! -d "$K3DM_WORKTREE_ROOT/metrics.lock" ]] && break; sleep 0.1; done
  [ "$(wc -l <"$METRICS_STARTS" | tr -d ' ')" -ge 2 ]
  [ ! -e "$METRICS_OVERLAP" ]
}

@test "codex dispatch: metrics scheduling takes stale lock and respects fresh lock" {
  local source_file="$BATS_TEST_TMPDIR/dispatcher-functions.sh"
  sed '/^main "\$@"$/d; s|source "${_dispatch_script_dir}/../scripts/lib/system.sh"|source "'"$BATS_TEST_DIRNAME"'/../../lib/system.sh"|' "$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch" >"$source_file"
  mkdir "$K3DM_WORKTREE_ROOT/metrics.lock"
  touch -t 202001010000 "$K3DM_WORKTREE_ROOT/metrics.lock"
  run bash -c 'source "$1"; _dispatch_schedule_metrics' _ "$source_file"
  [ "$status" -eq 0 ]; sleep 1.2
  [ "$(wc -l <"$METRICS_STARTS" | tr -d ' ')" -eq 1 ]
  rm -f "$METRICS_STARTS"; mkdir "$K3DM_WORKTREE_ROOT/metrics.lock"
  run bash -c 'source "$1"; _dispatch_schedule_metrics' _ "$source_file"
  [ "$status" -eq 0 ]; [ ! -e "$METRICS_STARTS" ]
}

@test "codex dispatch: make codex-dispatch passes --branch only when BRANCH is given" {
  root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  run env -u BRANCH -u REPO make -s -n -C "$root" codex-dispatch SPEC=docs/plans/x.md
  [ "$status" -eq 0 ]; [[ "$output" == *"--spec 'docs/plans/x.md'"* ]]; [[ "$output" != *"--branch"* ]]
  run env -u BRANCH make -s -n -C "$root" codex-dispatch SPEC=docs/plans/x.md REPO=/r BRANCH=fix/b
  [ "$status" -eq 0 ]; [[ "$output" == *"--repo '/r' --branch 'fix/b'"* ]]
}

@test "codex dispatch: make targets pass a declared coordinator" {
  local root="$BATS_TEST_DIRNAME/../../.."
  run make -s -n -C "$root" codex-dispatch SPEC=docs/plans/x.md COORDINATOR=anthropic/claude-test
  [ "$status" -eq 0 ] && [[ "$output" == *"--coordinator 'anthropic/claude-test'"* ]]
  run make -s -n -C "$root" codex-dispatch SPEC=docs/plans/x.md PRIMARY_COORDINATOR=openai/gpt-6-luna PRIMARY_COORDINATOR_SOURCE=runtime-reported
  [ "$status" -eq 0 ] && [[ "$output" == *"--primary-coordinator 'openai/gpt-6-luna' --primary-coordinator-source 'runtime-reported'"* ]]
  run make -s -n -C "$root" codex-dispatch SPEC=docs/plans/x.md PARENT=p0-s1 ROLE=build
  [ "$status" -eq 0 ] && [[ "$output" == *"--parent 'p0-s1' --role 'build'"* ]]
  run make -s -n -C "$root" codex-handoff SLUG=x ACTING_COORDINATOR=openai/gpt-6-luna HANDOFF_REASON=manual
  [ "$status" -eq 0 ] && [[ "$output" == *"handoff --slug 'x' --acting-coordinator 'openai/gpt-6-luna' --reason 'manual'"* ]]
  run make -s -n -C "$root" codex-land SLUG=x TEST=true LANDING_ACTOR=codex LANDING_MODEL=openai/gpt-6-luna
  [ "$status" -eq 0 ] && [[ "$output" == *"--landing-actor 'codex' --landing-model 'openai/gpt-6-luna'"* ]]
  run make -s -n -C "$root" codex-land-pending SLUG=x TEST=true LANDING_ACTOR=human
  [ "$status" -eq 0 ] && [[ "$output" == *"codex-land-pending --slug 'x' --test 'true' --landing-actor 'human'"* ]]
  run make -s -n -C "$root" codex-resume SLUG=x PROMPT=/tmp/p.md REASON=correction COORDINATOR=anthropic/claude-test
  [ "$status" -eq 0 ] && [[ "$output" == *"--reason 'correction'"* ]] && [[ "$output" == *"--coordinator 'anthropic/claude-test'"* ]]
}

@test "codex dispatch: fast gate refuses land with or without task tests" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug gate >/dev/null; sleep 1
  local task="$K3DM_WORKTREE_ROOT/v9.9.9/gate"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$task/scripts/ci/fast_gate.sh"
  printf 'changed\n' > "$task/a.txt"
  git -C "$task" add a.txt scripts/ci/fast_gate.sh
  git -C "$task" commit -qm broken-gate
  run dispatch land --slug gate --test true --allow-out-of-scope
  [ "$status" -eq 2 ]; [[ "$output" == *'fast gate failed'* ]]
  jq -e -s 'any(.[]; .slug=="gate" and .event=="land_refused" and .reason=="fast-gate")' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
  run dispatch land --slug gate --no-test --allow-out-of-scope
  [ "$status" -eq 2 ]; [[ "$output" == *'fast gate failed'* && "$output" == *'land-fast-gate.log'* ]]
  run bash -c 'cd "$1" && K3DM_SKIP_FAST_GATE=1 "$2" land --slug gate --no-test --allow-out-of-scope' _ "$FIXTURE" "$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch"
  [ "$status" -eq 0 ]; [[ "$output" == *'fast gate skipped'* ]]
}

@test "codex dispatch: fast gate receives isolated state and logs output" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug isolation >/dev/null; sleep 1
  local task="$K3DM_WORKTREE_ROOT/v9.9.9/isolation" run_dir="$K3DM_WORKTREE_ROOT/v9.9.9/isolation.run"
  printf '#!/usr/bin/env bash\nprintf "%%s\n%%s\n" "$K3DM_JOB_DIR" "$TMPDIR"\n' > "$task/scripts/ci/fast_gate.sh"
  printf 'changed\n' > "$task/a.txt"
  git -C "$task" add a.txt scripts/ci/fast_gate.sh
  git -C "$task" commit -qm gate
  run dispatch land --slug isolation --no-test --allow-out-of-scope
  [ "$status" -eq 0 ]
  [ "$(cat "$run_dir/land-fast-gate.log")" = "$(printf '%s\n%s' "$run_dir/state/jobs" "$run_dir/state/tmp")" ]
  [[ "$output" == *"$run_dir/state/jobs"* && "$output" == *"$run_dir/state/tmp"* ]]
}

@test "codex dispatch: evidence refusals and failure without evidence" {
  printf '{"ts":1,"event":"land","version":"v9.9.9","slug":"sample"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  [ "$FIXTURE" != "$(git rev-parse --show-toplevel)" ]
  [ "$K3DM_WORKTREE_ROOT" = "$BATS_TEST_TMPDIR/worktrees" ]
  sha="$(git -C "$FIXTURE" rev-parse HEAD)"
  file="$BATS_TEST_TMPDIR/evidence"
  for variant in missing missing_file empty separator verifier tests_from fix_missing command rc_missing pre_missing pre_command pre_rc_missing rc pre_rc fix_sha pre_sha; do
    printf 'verifier: codex\ntests_from: acceptance\nfix_sha: %s\ncommand: test\nrc: 0\npre_fix_sha: %s\npre_fix_command: test\npre_fix_rc: 1\n---\noutput\n' "$sha" "$sha" >"$file"
    case "$variant" in
      empty) : >"$file" ;;
      separator) sed -i.bak '/^---$/d' "$file" ;;
      verifier) sed -i.bak '/^verifier:/d' "$file" ;;
      tests_from) sed -i.bak '/^tests_from:/d' "$file" ;;
      fix_missing) sed -i.bak '/^fix_sha:/d' "$file" ;;
      command) sed -i.bak '/^command:/d' "$file" ;;
      rc_missing) sed -i.bak '/^rc:/d' "$file" ;;
      pre_missing) sed -i.bak '/^pre_fix_sha:/d' "$file" ;;
      pre_command) sed -i.bak '/^pre_fix_command:/d' "$file" ;;
      pre_rc_missing) sed -i.bak '/^pre_fix_rc:/d' "$file" ;;
      rc) sed -i.bak 's/^rc: 0/rc: 1/' "$file" ;;
      pre_rc) sed -i.bak 's/^pre_fix_rc: 1/pre_fix_rc: 0/' "$file" ;;
      fix_sha) sed -i.bak 's/^fix_sha:.*/fix_sha: deadbeef/' "$file" ;;
      pre_sha) sed -i.bak 's/^pre_fix_sha:.*/pre_fix_sha: deadbeef/' "$file" ;;
    esac
    if [ "$variant" = missing ]; then run dispatch verify --slug sample --result pass
    elif [ "$variant" = missing_file ]; then run dispatch verify --slug sample --result pass --evidence "$file.absent"
    else run dispatch verify --slug sample --result pass --evidence "$file"; fi
    [ "$status" -ne 0 ]
    [ "$(wc -l <"$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
    [ ! -d "$K3DM_WORKTREE_ROOT/v9.9.9/sample.run" ]
  done
  run dispatch verify --slug sample --result fail
  [ "$status" -eq 0 ]
  [ "$(jq -r -s '.[-1].result' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = fail ]
}

@test "codex dispatch: evidence SHAs resolve in the task's work repository" {
  printf '{"ts":1,"event":"land","version":"v9.9.9","slug":"other"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  [ "$K3DM_WORKTREE_ROOT" = "$BATS_TEST_TMPDIR/worktrees" ]
  other="$BATS_TEST_TMPDIR/other-repo"
  git init -q "$other"
  git -C "$other" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m other
  sha="$(git -C "$other" rev-parse HEAD)"
  [ "$other" != "$(git rev-parse --show-toplevel)" ]
  run git -C "$FIXTURE" cat-file -e "$sha^{commit}"
  [ "$status" -ne 0 ]
  printf 'verifier: codex\ntests_from: acceptance\nfix_sha: %s\ncommand: test\nrc: 0\npre_fix_sha: %s\npre_fix_command: test\npre_fix_rc: 1\n---\noutput\n' "$sha" "$sha" >"$BATS_TEST_TMPDIR/evidence"
  run dispatch verify --slug other --result pass --evidence "$BATS_TEST_TMPDIR/evidence"
  [ "$status" -ne 0 ]
  mkdir -p "$K3DM_WORKTREE_ROOT/v9.9.9/other.run"
  printf '%s\n' "$other" >"$K3DM_WORKTREE_ROOT/v9.9.9/other.run/repo"
  run dispatch verify --slug other --result pass --evidence "$BATS_TEST_TMPDIR/evidence"
  [ "$status" -eq 0 ]
  [ -n "$(jq -r -s '.[-1].evidence_sha256' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" ]
}

