#!/usr/bin/env bats

setup() {
  export FIXTURE="$BATS_TEST_TMPDIR/fixture" ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  export K3DM_WORKTREE_ROOT="$BATS_TEST_TMPDIR/worktrees" HOME="$BATS_TEST_TMPDIR/home"
  export K3DM_DISPATCH_PUSHGATEWAY_URL="http://127.0.0.1:9"
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
printf '%s\n' "$*" >>"${STUB_ARGV:?}"
printf '%s\n' "$PWD" >>"${STUB_ARGV}.cwd"
printf 'session id: 01a122dd-71c3-7763-87f0-3de505f10168\n'
printf 'K3DM_REPO_ROOT=%s\nK3DM_JOB_DIR=%s\nK3DM_RUN_DIR=%s\nK3DM_STATE_DIR=%s\nK3DM_LOG_DIR=%s\nK3DM_TMP_ROOT=%s\nK3DM_PORT_CACHE_DIR=%s\nTMPDIR=%s\nHOME=%s\n' "$K3DM_REPO_ROOT" "$K3DM_JOB_DIR" "$K3DM_RUN_DIR" "$K3DM_STATE_DIR" "$K3DM_LOG_DIR" "$K3DM_TMP_ROOT" "$K3DM_PORT_CACHE_DIR" "$TMPDIR" "$HOME" >"${STUB_ENV:?}"
codex_dir="${K3DM_REPO_ROOT:-}"
out_file=""
while (($#)); do
  if [[ "$1" == -C ]]; then codex_dir="$2"; shift 2
  elif [[ "$1" == -o ]]; then out_file="$2"; shift 2
  else shift; fi
done
[[ -n "$codex_dir" ]] || exit 1
if [[ -n "$out_file" ]]; then printf 'stub last message\n' >"$out_file"; fi
[[ -z "${STUB_SLEEP:-}" ]] || sleep "$STUB_SLEEP"
if [[ "$*" != *"exec resume"* ]]; then
  IFS=, read -ra edits <<<"${STUB_EDITS:-a.txt}"
  for edit in "${edits[@]}"; do printf 'edited\n' >"$codex_dir/$edit"; done
fi
[[ "${STUB_TOKENS:-}" == none ]] || printf 'tokens used\n%s\n' "${STUB_TOKENS:-12,345}"
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

@test "codex dispatch: piped start returns before Codex exits" {
  export STUB_SLEEP=5 STUB_ARGV="$BATS_TEST_TMPDIR/one.argv" STUB_ENV="$BATS_TEST_TMPDIR/one.env"
  timeout_bin=timeout
  command -v "$timeout_bin" >/dev/null 2>&1 || timeout_bin=gtimeout
  command -v "$timeout_bin" >/dev/null 2>&1 || skip "timeout or gtimeout is unavailable"

  run "$timeout_bin" 3 bash -c 'cd "$1" && "$2" start --spec docs/plans/v9.9.9-demo.md --slug one | cat' _ "$FIXTURE" "$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch"
  [ "$status" -eq 0 ]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]
  sleep 6
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit")" = 0 ]
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
  run dispatch land --slug one --no-test; [ "$status" -eq 2 ]
  sleep 6
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  printf 'out\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/one/memory-bank/x.md"
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add memory-bank/x.md; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m out >/dev/null
  run dispatch land --slug one --no-test; [ "$status" -eq 2 ]
  printf 'dirty\n' >>"$K3DM_WORKTREE_ROOT/v9.9.9/one/a.txt"
  run dispatch land --slug one --no-test; [ "$status" -eq 2 ]
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
  run dispatch land --slug one --no-test
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
  before="$(git -C "$FIXTURE" rev-parse HEAD)"
  run dispatch land --slug one --test 'bash check.sh'
  [ "$status" -eq 2 ]; [[ "$output" == *"tests failed after rebase"* ]]
  [ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$before" ]
  [ "$(<"$FIXTURE/a.txt")" = original ]
  [ -e "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/land-test.log" ]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/.land.lock" ]
  run dispatch land --slug one --test false
  [ "$status" -eq 2 ]; [ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$before" ]
  run dispatch land --slug one --test true
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

@test "codex dispatch: network tasks are exclusive" {
  export STUB_SLEEP=5 STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one --network >/dev/null
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug two --network
  [ "$status" -eq 2 ]; [[ "$output" == *"only one networked task at a time"* ]]
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug two >/dev/null
  sleep 6
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug three --network >/dev/null
  run dispatch status one
  [[ "$output" == *"network: yes"* ]]
}

@test "codex dispatch: resume continues the same session" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  run dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]; sleep 1
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/prompt-2.md" ]
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/codex-2.log" ]
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/last-message-2.md" ]
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]
  [[ "$(<"$BATS_TEST_TMPDIR/a.argv")" == *"exec resume"* ]]
  [[ "$(<"$BATS_TEST_TMPDIR/a.argv")" == *"01a122dd-71c3-7763-87f0-3de505f10168"* ]]
  run dispatch status one; [[ "$output" == *"resumes: 1"* ]]
  export STUB_SLEEP=5
  dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md"
  run dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]; [[ "$output" == *"Codex is still running"* ]]
  sleep 6
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/codex-3.log" ]
}

@test "codex dispatch: resume passes the state root and runs in the worktree" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md" >/dev/null; sleep 1
  resume_argv="$(tail -n 1 "$BATS_TEST_TMPDIR/a.argv")"
  [[ "$resume_argv" == *"writable_roots=[\"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/state\"]"* ]]
  [[ "$resume_argv" != *"network_access=true"* ]]
  [ "$(cd "$(tail -n 1 "$BATS_TEST_TMPDIR/a.argv.cwd")" && pwd -P)" = "$(cd "$K3DM_WORKTREE_ROOT/v9.9.9/one" && pwd -P)" ]
}

@test "codex dispatch: resume refuses a landed task and a log without a session id" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  sed -i.bak '/^session id: /d' "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/codex.log"
  run dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]; [[ "$output" == *"no valid session id"* ]]
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]
  run dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/empty.md"
  [ "$status" -eq 2 ]
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug two >/dev/null; sleep 1
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/two" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/two" commit -m edit >/dev/null
  dispatch land --slug two --no-test >/dev/null
  run dispatch resume --slug two --prompt-file "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]
}

@test "codex dispatch: a refused networked resume leaves the task finished" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one --network >/dev/null; sleep 1
  STUB_SLEEP=5 dispatch start --spec docs/plans/v9.9.9-demo.md --slug two --network >/dev/null
  run dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]; [[ "$output" == *"network task two is still running"* ]]
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/prompt-2.md" ]
  sleep 6
}

@test "codex dispatch: ledger snapshots Codex output and restores the index" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  ledger="$K3DM_WORKTREE_ROOT/ledger.jsonl"
  [ "$(jq -s 'length' "$ledger")" -eq 2 ]
  [ "$(jq -r -s '.[0].event' "$ledger")" = start ]
  [ "$(jq -r -s '.[1].event' "$ledger")" = codex_exit ]
  [ "$(jq -r -s '.[1].tokens' "$ledger")" = 12345 ]
  [[ "$(jq -r -s '.[1].tree' "$ledger")" =~ ^[0-9a-f]{40}$ ]]
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/codex-tree" ]
  [ -z "$(git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" diff --cached --name-only)" ]
}

@test "codex dispatch: ledger records verifier lines before a release rebase" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  printf 'edited\nextra\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/one/a.txt"
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  printf 'release\n' >"$FIXTURE/release.txt"
  git -C "$FIXTURE" add release.txt; git -C "$FIXTURE" commit -m release >/dev/null
  run dispatch land --slug one --no-test
  [ "$status" -eq 0 ]
  [ "$(jq -r -s '.[-1].event' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = land ]
  [ "$(jq -r -s '.[-1].verifier_lines' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = 1 ]
  [ "$(jq -r -s '.[-1].wait_seconds' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -ge 0 ]
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

@test "codex dispatch: resume records the latest token total" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  export STUB_TOKENS=20000
  dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md" >/dev/null; sleep 1
  [ "$(jq -r -s 'map(select(.event == "resume"))[0].n' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = 2 ]
  [ "$(jq -r -s 'map(select(.event == "codex_exit"))[-1].tokens' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = 20000 ]
}

@test "codex dispatch: ledger records a Codex exit with no token count" {
  export STUB_TOKENS=none STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  ledger="$K3DM_WORKTREE_ROOT/ledger.jsonl"
  [ "$(jq -r -s 'map(select(.event == "codex_exit"))[0].tokens' "$ledger")" = null ]
  [[ "$(jq -r -s 'map(select(.event == "codex_exit"))[0].tree' "$ledger")" =~ ^[0-9a-f]{40}$ ]]
}
