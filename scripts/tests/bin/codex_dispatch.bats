#!/usr/bin/env bats

setup() {
  export FIXTURE="$BATS_TEST_TMPDIR/fixture" ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  export K3DM_WORKTREE_ROOT="$BATS_TEST_TMPDIR/worktrees" HOME="$BATS_TEST_TMPDIR/home"
  export K3DM_CODEX_BIN="$BATS_TEST_TMPDIR/codex-stub"
  mkdir -p "$FIXTURE" "$HOME" "$K3DM_WORKTREE_ROOT"
  git init --bare "$ORIGIN" >/dev/null
  git clone "$ORIGIN" "$FIXTURE" >/dev/null
  git -C "$FIXTURE" checkout -b k3d-manager-v9.9.9 >/dev/null
  git -C "$FIXTURE" config user.email test@example.com; git -C "$FIXTURE" config user.name Test
  printf 'original\n' >"$FIXTURE/a.txt"
  mkdir -p "$FIXTURE/memory-bank"; touch "$FIXTURE/memory-bank/.keep"
  mkdir -p "$FIXTURE/docs/plans"; printf '# Readme\n\nNo files section here.\n' >"$FIXTURE/README.md"
  cat >"$FIXTURE/docs/plans/v9.9.9-demo.md" <<'EOF'
# Test spec

## Files

| File |
|---|
| `a.txt` |
| `docs/plans/v9.9.9-demo.md` |
EOF
  git -C "$FIXTURE" add a.txt README.md docs/plans/v9.9.9-demo.md memory-bank/.keep; git -C "$FIXTURE" commit -m base >/dev/null
  git -C "$FIXTURE" push -u origin k3d-manager-v9.9.9 >/dev/null
  cat >"$K3DM_CODEX_BIN" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${STUB_ARGV:?}"
printf 'K3DM_REPO_ROOT=%s\nK3DM_JOB_DIR=%s\nK3DM_RUN_DIR=%s\nK3DM_STATE_DIR=%s\nK3DM_LOG_DIR=%s\nK3DM_TMP_ROOT=%s\nK3DM_PORT_CACHE_DIR=%s\nTMPDIR=%s\nHOME=%s\n' "$K3DM_REPO_ROOT" "$K3DM_JOB_DIR" "$K3DM_RUN_DIR" "$K3DM_STATE_DIR" "$K3DM_LOG_DIR" "$K3DM_TMP_ROOT" "$K3DM_PORT_CACHE_DIR" "$TMPDIR" "$HOME" >"${STUB_ENV:?}"
codex_dir=""
while (($#)); do
  if [[ "$1" == -C ]]; then codex_dir="$2"; shift 2; else shift; fi
done
[[ -n "$codex_dir" ]] || exit 1
[[ -z "${STUB_SLEEP:-}" ]] || sleep "$STUB_SLEEP"
IFS=, read -ra edits <<<"${STUB_EDITS:-a.txt}"
for edit in "${edits[@]}"; do printf 'edited\n' >"$codex_dir/$edit"; done
STUB
  chmod +x "$K3DM_CODEX_BIN"
}

dispatch() { (cd "$FIXTURE" && "$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch" "$@"); }

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

@test "codex dispatch: parallel starts isolate each edit" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env" STUB_EDITS=a.txt
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  export STUB_ARGV="$BATS_TEST_TMPDIR/b.argv" STUB_ENV="$BATS_TEST_TMPDIR/b.env" STUB_EDITS=docs/plans/v9.9.9-demo.md
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug two >/dev/null; sleep 1
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/one/a.txt")" = edited ]
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/two/docs/plans/v9.9.9-demo.md")" = edited ]
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/one/docs/plans/v9.9.9-demo.md")" != edited ]
}

@test "codex dispatch: argv has sandbox worktree and state dir" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/argv" STUB_ENV="$BATS_TEST_TMPDIR/env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  argv="$(<"$BATS_TEST_TMPDIR/argv")"
  [[ "$argv" == *"exec --sandbox workspace-write -C $K3DM_WORKTREE_ROOT/v9.9.9/one --add-dir $K3DM_WORKTREE_ROOT/v9.9.9/one.run/state"* ]]
  [[ "$argv" != *"network_access=true"* ]]
}

@test "codex dispatch: state is isolated and HOME is unchanged" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  export STUB_ARGV="$BATS_TEST_TMPDIR/b.argv" STUB_ENV="$BATS_TEST_TMPDIR/b.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug two >/dev/null; sleep 1
  grep -q "K3DM_JOB_DIR=$K3DM_WORKTREE_ROOT/v9.9.9/one.run/state/jobs" "$BATS_TEST_TMPDIR/a.env"
  grep -q "K3DM_RUN_DIR=$K3DM_WORKTREE_ROOT/v9.9.9/one.run/state/run" "$BATS_TEST_TMPDIR/a.env"
  grep -q "K3DM_STATE_DIR=$K3DM_WORKTREE_ROOT/v9.9.9/one.run/state/state" "$BATS_TEST_TMPDIR/a.env"
  grep -q "K3DM_LOG_DIR=$K3DM_WORKTREE_ROOT/v9.9.9/one.run/state/logs" "$BATS_TEST_TMPDIR/a.env"
  grep -q "K3DM_TMP_ROOT=$K3DM_WORKTREE_ROOT/v9.9.9/one.run/state/tmp" "$BATS_TEST_TMPDIR/a.env"
  grep -q "K3DM_PORT_CACHE_DIR=$K3DM_WORKTREE_ROOT/v9.9.9/one.run/state/port-cache" "$BATS_TEST_TMPDIR/a.env"
  grep -q "TMPDIR=$K3DM_WORKTREE_ROOT/v9.9.9/one.run/state/tmp" "$BATS_TEST_TMPDIR/a.env"
  grep -q "K3DM_REPO_ROOT=$K3DM_WORKTREE_ROOT/v9.9.9/one" "$BATS_TEST_TMPDIR/a.env"
  grep -q "HOME=$HOME" "$BATS_TEST_TMPDIR/a.env"
  run grep -q "one.run" "$BATS_TEST_TMPDIR/b.env"; [ "$status" -eq 1 ]
  [ -z "$(find "$HOME" -mindepth 1 -print -quit)" ]
}

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
  run dispatch land --slug one; [ "$status" -eq 2 ]
  sleep 6
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  printf 'out\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/one/memory-bank/x.md"
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add memory-bank/x.md; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m out >/dev/null
  run dispatch land --slug one; [ "$status" -eq 2 ]
  printf 'dirty\n' >>"$K3DM_WORKTREE_ROOT/v9.9.9/one/a.txt"
  run dispatch land --slug one; [ "$status" -eq 2 ]
}

@test "codex dispatch: land refuses a dirty operator checkout" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  printf 'dirty\n' >>"$FIXTURE/a.txt"; run dispatch land --slug one; [ "$status" -eq 2 ]
}

@test "codex dispatch: land fast-forwards without pushing" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  task_head="$(git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" rev-parse HEAD)"
  before="$(git -C "$FIXTURE" rev-parse origin/k3d-manager-v9.9.9)"; run dispatch land --slug one
  [ "$status" -eq 0 ]
  [ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$task_head" ]
  [ "$(<"$FIXTURE/a.txt")" = edited ]
  run bash -c 'git -C "$FIXTURE" worktree list --porcelain | grep -Fq "$K3DM_WORKTREE_ROOT/v9.9.9/one"'; [ "$status" -eq 1 ]
  run git -C "$FIXTURE" show-ref --verify --quiet refs/heads/task/v9.9.9/one; [ "$status" -ne 0 ]
  [ "$(git -C "$FIXTURE" rev-parse origin/k3d-manager-v9.9.9)" = "$before" ]
}

@test "codex dispatch: abandon without yes changes nothing" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; run dispatch abandon --slug one
  [ "$status" -eq 2 ]; [ -d "$K3DM_WORKTREE_ROOT/v9.9.9/one" ]
  git -C "$FIXTURE" show-ref --verify --quiet refs/heads/task/v9.9.9/one
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
  run dispatch land --slug one
  [ "$status" -eq 2 ]
}

@test "codex dispatch: records the release base at start" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/base")" = "$(git -C "$FIXTURE" rev-parse origin/k3d-manager-v9.9.9)" ]
}

@test "codex dispatch: scope ignores commits pushed after dispatch" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  printf 'release change\n' >"$FIXTURE/release.txt"
  git -C "$FIXTURE" add release.txt; git -C "$FIXTURE" commit -m release-change >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  git -C "$FIXTURE" fetch -q origin k3d-manager-v9.9.9:refs/remotes/origin/k3d-manager-v9.9.9
  run dispatch status one
  [[ "$output" != *"release.txt"* ]]
}

@test "codex dispatch: land refuses a missing recorded base" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  rm "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/base"
  run dispatch status one
  [[ "$output" == *"scope: unknown (no recorded base)"* ]]
  run dispatch land --slug one
  [ "$status" -eq 2 ]
  [[ "$output" == *"no recorded base"* ]]
}
