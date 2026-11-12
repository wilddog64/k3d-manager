#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load codex_dispatch_helpers

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

@test "codex dispatch: detached worker survives launcher SIGHUP" {
  command -v python3 >/dev/null 2>&1 || skip "python3 is unavailable"
  export STUB_SLEEP=3 STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  helper="$BATS_TEST_TMPDIR/grouped-start.sh"
  cat >"$helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$FIXTURE"
"$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch" start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
EOF
  chmod +x "$helper"
  python3 -c 'import os, sys; os.setpgrp(); os.execv(sys.argv[1], sys.argv[1:])' "$helper" & launcher_pid=$!
  wait "$launcher_pid"
  kill -HUP -"$launcher_pid" 2>/dev/null || true
  sleep 1
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]
  sleep 4
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit")" = 0 ]
  run dispatch status one
  [[ "$output" == *"state: exited successfully"* ]]
}

@test "codex dispatch: detached worker survives launcher process-group SIGKILL" {
  command -v python3 >/dev/null 2>&1 || skip "python3 is unavailable"
  export STUB_SLEEP=3 STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  helper="$BATS_TEST_TMPDIR/grouped-start.sh"
  cat >"$helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$FIXTURE"
"$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch" start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
EOF
  chmod +x "$helper"
  python3 -c 'import os, sys; os.setpgrp(); os.execv(sys.argv[1], sys.argv[1:])' "$helper" & launcher_pid=$!
  wait "$launcher_pid"
  kill -KILL -"$launcher_pid" 2>/dev/null || true
  sleep 1
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]
  sleep 4
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit")" = 0 ]
  run dispatch status one
  [[ "$output" == *"state: exited successfully"* ]]
}

@test "codex dispatch: plain background worker is killed by launcher group" {
  command -v python3 >/dev/null 2>&1 || skip "python3 is unavailable"
  helper="$BATS_TEST_TMPDIR/plain-background.sh"
  marker="$BATS_TEST_TMPDIR/plain-background.done"
  cat >"$helper" <<EOF
#!/usr/bin/env bash
( sleep 3; : >"$marker" ) &
EOF
  chmod +x "$helper"
  # Negative control for the pre-fix `( ... ) &` launcher: its worker remains in this group.
  python3 -c 'import os, sys; os.setpgrp(); os.execv(sys.argv[1], sys.argv[1:])' "$helper" & launcher_pid=$!
  wait "$launcher_pid"
  kill -KILL -"$launcher_pid" 2>/dev/null || true
  sleep 1
  [ ! -e "$marker" ]
}

@test "codex dispatch: records nonzero Codex exit before bookkeeping" {
  export STUB_RC=42 STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit")" = 42 ]
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/codex-exit-ts" ]
  run dispatch status one
  [[ "$output" == *"state: exited nonzero (42)"* ]]
}

@test "codex dispatch: missing Codex is a terminal nonzero exit" {
  export K3DM_CODEX_BIN="$BATS_TEST_TMPDIR/does-not-exist" STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  sleep 1
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit")" = 127 ]
  run dispatch status one
  [[ "$output" == *"state: exited nonzero (127)"* ]]
}

@test "codex dispatch: bookkeeping failure does not hide the exit" {
  export STUB_SLEEP=1 STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  rm "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  mkdir "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  sleep 2
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit")" = 0 ]
  grep -q 'Codex bookkeeping failed after exit code 0 was recorded' "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/supervisor.log"
}

@test "codex dispatch: a killed worker is unexpectedly terminated" {
  export STUB_SLEEP=30 STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  worker_pid="$(awk -F= '$1 == "pid" {print $2}' "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/start")"
  kill -KILL "$worker_pid"
  sleep 1
  run dispatch status one
  [[ "$output" == *"state: terminated unexpectedly"* ]]
  [[ "$output" == *"supervisor.log"* ]]
}

@test "codex dispatch: a reused PID identity is not reported running" {
  export STUB_SLEEP=5 STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  sed -i.bak 's/^process_start=.*/process_start=not-the-worker/' "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/start"
  run dispatch status one
  [[ "$output" == *"state: terminated unexpectedly"* ]]
  worker_pid="$(awk -F= '$1 == "pid" {print $2}' "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/start")"
  kill "$worker_pid" 2>/dev/null || true
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

@test "codex dispatch: argv has sandbox worktree and run dir" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/argv" STUB_ENV="$BATS_TEST_TMPDIR/env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  sleep 1
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

