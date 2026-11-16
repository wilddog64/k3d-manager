#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load codex_dispatch_helpers

@test "codex dispatch: cross-repo start snapshots the spec and land targets only the named branch" {
  export WORK_ORIGIN="$BATS_TEST_TMPDIR/work-origin.git" WORK_REPO="$BATS_TEST_TMPDIR/work-repo"
  git init --bare "$WORK_ORIGIN" >/dev/null
  git clone "$WORK_ORIGIN" "$WORK_REPO" >/dev/null
  git -C "$WORK_REPO" config user.email test@example.com; git -C "$WORK_REPO" config user.name Test
  git -C "$WORK_REPO" checkout -b fix/cross-repo >/dev/null
  printf 'original\n' >"$WORK_REPO/a.txt"
  git -C "$WORK_REPO" add a.txt; git -C "$WORK_REPO" commit -m work-base >/dev/null
  git -C "$WORK_REPO" push -u origin fix/cross-repo >/dev/null
  remote_before="$(git -C "$WORK_REPO" rev-parse origin/fix/cross-repo)"
  manager_before="$(git -C "$FIXTURE" rev-parse HEAD)"
  export STUB_ARGV="$BATS_TEST_TMPDIR/cross.argv" STUB_ENV="$BATS_TEST_TMPDIR/cross.env"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug cross --repo "$WORK_REPO" --branch fix/cross-repo
  [ "$status" -eq 0 ]; sleep 1
  task="$K3DM_WORKTREE_ROOT/v9.9.9/cross"; run_dir="$K3DM_WORKTREE_ROOT/v9.9.9/cross.run"
  [ "$(git -C "$task" branch --show-current)" = task/v9.9.9/cross ]
  [ "$(cat "$run_dir/repo-name")" = work-origin ]
  [ "$(cat "$run_dir/target")" = fix/cross-repo ]
  grep -q "$run_dir/spec.md" "$run_dir/prompt.md"
  [[ "$(<"$BATS_TEST_TMPDIR/cross.argv")" == *"--add-dir $run_dir/state -o"* ]]
  [[ "$(<"$BATS_TEST_TMPDIR/cross.argv")" != *"--add-dir $run_dir -o"* ]]
  [ "$(cat "$run_dir/spec-base")" = "$(git -C "$FIXTURE" rev-parse HEAD)" ]
  [ "$(jq -r -s '.[0].repo' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = work-origin ]
  printf 'edited\n' >"$task/a.txt"
  git -C "$task" add a.txt; git -C "$task" commit -m task-edit >/dev/null
  run dispatch land --slug cross --test false
  [ "$status" -eq 2 ]; [[ "$output" == *'tests failed'* ]]
  jq -e -s 'any(.[]; .slug=="cross" and .event=="land_refused" and .reason=="tests")' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
  run dispatch land --slug cross --test true
  [ "$status" -eq 0 ]; [[ "$output" == *"git -C $(git -C "$WORK_REPO" rev-parse --show-toplevel) push origin fix/cross-repo"* ]]
  [[ "$output" == *'land: fast gate not available in work-origin; --test is the gate'* ]]
  jq -e -s 'all(.[]; .slug!="cross" or .event!="land_refused" or .reason!="fast-gate")' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
  [ "$(git -C "$WORK_REPO" show fix/cross-repo:a.txt)" = edited ]
  [ "$(git -C "$WORK_REPO" rev-parse origin/fix/cross-repo)" = "$remote_before" ]
  [ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$manager_before" ]
  [ "$(jq -r -s 'map(select(.slug=="cross"))[-1].repo' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = work-origin ]
  [ "$(jq -r -s '[.[]|select(.slug=="cross" and .repo=="work-origin")]|length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 5 ]
  jq -e -s 'map(select(.slug=="cross" and .event=="primary_coordinator"))[-1] | .repo=="work-origin" and .primary_coordinator_identity.source=="unknown"' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
  jq -e -s 'map(select(.slug=="cross" and .event=="land"))[-1] | has("verifier_lines") and has("wait_seconds")' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
  [ "$(jq -r -s 'map(select(.slug=="cross" and .event=="land"))[-1].target_moved_commits' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = 0 ]
}

@test "codex dispatch: cross-repo start rejects incomplete and protected targets" {
  export WORK_ORIGIN="$BATS_TEST_TMPDIR/work-origin.git" WORK_REPO="$BATS_TEST_TMPDIR/work-repo"
  git init --bare "$WORK_ORIGIN" >/dev/null; git clone "$WORK_ORIGIN" "$WORK_REPO" >/dev/null
  git -C "$WORK_REPO" config user.email test@example.com; git -C "$WORK_REPO" config user.name Test
  mkdir -p "$WORK_REPO/scripts/ci"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK_REPO/scripts/ci/fast_gate.sh"
  chmod +x "$WORK_REPO/scripts/ci/fast_gate.sh"
  git -C "$WORK_REPO" add scripts/ci/fast_gate.sh
  git -C "$WORK_REPO" checkout -b fix/cross-repo >/dev/null
  touch "$WORK_REPO/a.txt"; git -C "$WORK_REPO" add a.txt; git -C "$WORK_REPO" commit -m base >/dev/null
  git -C "$WORK_REPO" push -u origin fix/cross-repo >/dev/null
  run dispatch start --spec docs/plans/v9.9.9-demo.md --repo "$WORK_REPO"
  [ "$status" -eq 2 ]; [[ "$output" == *"--repo and --branch must be used together"* ]]
  run dispatch start --spec docs/plans/v9.9.9-demo.md --branch fix/cross-repo
  [ "$status" -eq 2 ]; [[ "$output" == *"--repo and --branch must be used together"* ]]
  run dispatch start --spec docs/plans/v9.9.9-demo.md --repo "$WORK_REPO" --branch main
  [ "$status" -eq 2 ]; [[ "$output" == *"must not be main or master"* ]]
  run dispatch start --spec docs/plans/v9.9.9-demo.md --repo "$WORK_REPO" --branch master
  [ "$status" -eq 2 ]; [[ "$output" == *"must not be main or master"* ]]
  run dispatch start --spec docs/plans/v9.9.9-demo.md --repo "$WORK_REPO" --branch absent
  [ "$status" -eq 2 ]; [[ "$output" == *"branch does not exist on origin"* ]]
  run dispatch start --spec docs/plans/v9.9.9-demo.md --repo "$FIXTURE" --branch k3d-manager-v9.9.9
  [ "$status" -eq 2 ]; [[ "$output" == *"must not point at k3d-manager"* ]]
}

@test "codex dispatch: cross-repo scope uses the saved spec and refuses memory-bank" {
  export WORK_ORIGIN="$BATS_TEST_TMPDIR/work-origin.git" WORK_REPO="$BATS_TEST_TMPDIR/work-repo"
  git init --bare "$WORK_ORIGIN" >/dev/null; git clone "$WORK_ORIGIN" "$WORK_REPO" >/dev/null
  git -C "$WORK_REPO" config user.email test@example.com; git -C "$WORK_REPO" config user.name Test
  mkdir -p "$WORK_REPO/scripts/ci"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK_REPO/scripts/ci/fast_gate.sh"
  chmod +x "$WORK_REPO/scripts/ci/fast_gate.sh"
  git -C "$WORK_REPO" add scripts/ci/fast_gate.sh
  git -C "$WORK_REPO" checkout -b fix/cross-repo >/dev/null
  printf 'base\n' >"$WORK_REPO/a.txt"; git -C "$WORK_REPO" add a.txt; git -C "$WORK_REPO" commit -m base >/dev/null
  git -C "$WORK_REPO" push -u origin fix/cross-repo >/dev/null
  export STUB_ARGV="$BATS_TEST_TMPDIR/cross.argv" STUB_ENV="$BATS_TEST_TMPDIR/cross.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug cross-scope --repo "$WORK_REPO" --branch fix/cross-repo >/dev/null; sleep 1
  task="$K3DM_WORKTREE_ROOT/v9.9.9/cross-scope"
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/cross-scope.run/spec.md" ]
  [ "$(cat "$K3DM_WORKTREE_ROOT/v9.9.9/cross-scope.run/spec-sha256")" = "$(shasum -a 256 "$K3DM_WORKTREE_ROOT/v9.9.9/cross-scope.run/spec.md" | awk '{print $1}')" ]
  mkdir -p "$task/memory-bank"; printf 'out\n' >"$task/memory-bank/blocked.md"
  git -C "$task" add a.txt memory-bank/blocked.md; git -C "$task" commit -m out-of-scope >/dev/null
  run dispatch land --slug cross-scope --no-test
  [ "$status" -eq 2 ]; [[ "$output" == *"task changes are out of scope"* ]]
  [ "$(jq -r -s 'map(select(.event=="land_refused"))[-1].reason' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = scope ]
}

@test "codex dispatch: cross-repo land refuses target rewritten since dispatch" {
  export WORK_ORIGIN="$BATS_TEST_TMPDIR/work-origin.git" WORK_REPO="$BATS_TEST_TMPDIR/work-repo"
  git init --bare "$WORK_ORIGIN" >/dev/null; git clone "$WORK_ORIGIN" "$WORK_REPO" >/dev/null
  git -C "$WORK_REPO" config user.email test@example.com; git -C "$WORK_REPO" config user.name Test
  mkdir -p "$WORK_REPO/scripts/ci"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK_REPO/scripts/ci/fast_gate.sh"
  chmod +x "$WORK_REPO/scripts/ci/fast_gate.sh"
  git -C "$WORK_REPO" add scripts/ci/fast_gate.sh
  git -C "$WORK_REPO" checkout -b fix/cross-repo >/dev/null
  printf 'base\n' >"$WORK_REPO/a.txt"; git -C "$WORK_REPO" add a.txt; git -C "$WORK_REPO" commit -m base >/dev/null
  git -C "$WORK_REPO" push -u origin fix/cross-repo >/dev/null
  export STUB_ARGV="$BATS_TEST_TMPDIR/cross.argv" STUB_ENV="$BATS_TEST_TMPDIR/cross.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug rewritten --repo "$WORK_REPO" --branch fix/cross-repo >/dev/null; sleep 1
  task="$K3DM_WORKTREE_ROOT/v9.9.9/rewritten"
  printf 'task\n' >"$task/a.txt"; git -C "$task" add a.txt; git -C "$task" commit -m task >/dev/null
  git -C "$WORK_REPO" checkout --orphan rewrite >/dev/null
  printf 'rewritten\n' >"$WORK_REPO/a.txt"
  git -C "$WORK_REPO" add a.txt; git -C "$WORK_REPO" commit -m rewritten >/dev/null
  git -C "$WORK_REPO" branch -f fix/cross-repo HEAD; git -C "$WORK_REPO" checkout fix/cross-repo >/dev/null
  git -C "$WORK_REPO" push --force origin fix/cross-repo >/dev/null
  git -C "$WORK_REPO" fetch origin fix/cross-repo:refs/remotes/origin/fix/cross-repo >/dev/null 2>&1 || :
  run dispatch land --slug rewritten --no-test
  [ "$status" -eq 2 ]; [[ "$output" == *"rewritten since dispatch"* ]]
  [ "$(jq -r -s 'map(select(.event=="land_refused"))[-1].reason' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = target_rewritten ]
  [ -d "$task" ]
}

@test "codex dispatch: cross-repo land refuses a different target checkout and local divergence" {
  export WORK_ORIGIN="$BATS_TEST_TMPDIR/work-origin.git" WORK_REPO="$BATS_TEST_TMPDIR/work-repo"
  git init --bare "$WORK_ORIGIN" >/dev/null; git clone "$WORK_ORIGIN" "$WORK_REPO" >/dev/null
  git -C "$WORK_REPO" config user.email test@example.com; git -C "$WORK_REPO" config user.name Test
  mkdir -p "$WORK_REPO/scripts/ci"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK_REPO/scripts/ci/fast_gate.sh"
  chmod +x "$WORK_REPO/scripts/ci/fast_gate.sh"
  git -C "$WORK_REPO" add scripts/ci/fast_gate.sh
  git -C "$WORK_REPO" checkout -b fix/cross-repo >/dev/null
  printf 'base\n' >"$WORK_REPO/a.txt"; git -C "$WORK_REPO" add a.txt; git -C "$WORK_REPO" commit -m base >/dev/null
  git -C "$WORK_REPO" push -u origin fix/cross-repo >/dev/null
  export STUB_ARGV="$BATS_TEST_TMPDIR/cross.argv" STUB_ENV="$BATS_TEST_TMPDIR/cross.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug wrong-target --repo "$WORK_REPO" --branch fix/cross-repo >/dev/null; sleep 1
  task="$K3DM_WORKTREE_ROOT/v9.9.9/wrong-target"
  printf 'task\n' >"$task/a.txt"; git -C "$task" add a.txt; git -C "$task" commit -m task >/dev/null
  git -C "$WORK_REPO" checkout -b another-branch >/dev/null
  run dispatch land --slug wrong-target --no-test
  [ "$status" -eq 2 ]; [ "$(jq -r -s 'map(select(.event=="land_refused"))[-1].reason' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = target_diverged ]
  git -C "$WORK_REPO" checkout fix/cross-repo >/dev/null
  printf 'dirty\n' >>"$WORK_REPO/a.txt"
  run dispatch land --slug wrong-target --no-test
  [ "$status" -eq 2 ]; [[ "$output" == *"target checkout is dirty"* ]]
  git -C "$WORK_REPO" checkout -- a.txt
  printf 'local\n' >"$WORK_REPO/local.txt"; git -C "$WORK_REPO" add local.txt; git -C "$WORK_REPO" commit -m local-ahead >/dev/null
  run dispatch land --slug wrong-target --no-test
  [ "$status" -eq 2 ]; [ "$(jq -r -s 'map(select(.event=="land_refused"))[-1].reason' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = target_diverged ]
  [ -d "$task" ]
}

@test "codex dispatch: cross-repo land records a forward target move and catches movement during tests" {
  export WORK_ORIGIN="$BATS_TEST_TMPDIR/work-origin.git" WORK_REPO="$BATS_TEST_TMPDIR/work-repo"
  git init --bare "$WORK_ORIGIN" >/dev/null; git clone "$WORK_ORIGIN" "$WORK_REPO" >/dev/null
  git -C "$WORK_REPO" config user.email test@example.com; git -C "$WORK_REPO" config user.name Test
  mkdir -p "$WORK_REPO/scripts/ci"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK_REPO/scripts/ci/fast_gate.sh"
  chmod +x "$WORK_REPO/scripts/ci/fast_gate.sh"
  git -C "$WORK_REPO" add scripts/ci/fast_gate.sh
  git -C "$WORK_REPO" checkout -b fix/cross-repo >/dev/null
  printf 'base\n' >"$WORK_REPO/a.txt"; git -C "$WORK_REPO" add a.txt; git -C "$WORK_REPO" commit -m base >/dev/null
  git -C "$WORK_REPO" push -u origin fix/cross-repo >/dev/null
  export STUB_ARGV="$BATS_TEST_TMPDIR/cross.argv" STUB_ENV="$BATS_TEST_TMPDIR/cross.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug moved --repo "$WORK_REPO" --branch fix/cross-repo >/dev/null; sleep 1
  task="$K3DM_WORKTREE_ROOT/v9.9.9/moved"
  printf 'task\n' >"$task/a.txt"; git -C "$task" add a.txt; git -C "$task" commit -m task >/dev/null
  printf 'forward\n' >"$WORK_REPO/forward.txt"; git -C "$WORK_REPO" add forward.txt; git -C "$WORK_REPO" commit -m forward >/dev/null
  git -C "$WORK_REPO" push origin fix/cross-repo >/dev/null
  git -C "$WORK_REPO" fetch origin fix/cross-repo >/dev/null
  run dispatch land --slug moved --test true
  [ "$status" -eq 0 ]; [[ "$output" == *"target moved: +1 commits since dispatch"* ]]
  [ "$(jq -r -s 'map(select(.event=="land"))[-1].target_moved_commits' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = 1 ]
  git -C "$WORK_REPO" push origin fix/cross-repo >/dev/null

  dispatch start --spec docs/plans/v9.9.9-demo.md --slug moved-during --repo "$WORK_REPO" --branch fix/cross-repo >/dev/null; sleep 1
  task="$K3DM_WORKTREE_ROOT/v9.9.9/moved-during"
  printf 'next\n' >"$task/a.txt"; git -C "$task" add a.txt; git -C "$task" commit -m task >/dev/null
  run dispatch land --slug moved-during --superseding moved --test 'printf x > "$WORK_REPO/during.txt"; git -C "$WORK_REPO" add during.txt; git -C "$WORK_REPO" commit -m during'
  [ "$status" -eq 2 ]; [[ "$output" == *"moved during land"* ]]
  [ "$(jq -r -s 'map(select(.slug=="moved-during" and .event=="land_refused"))[-1].reason' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = target_moved_during_land ]
  [ -d "$task" ]
}

