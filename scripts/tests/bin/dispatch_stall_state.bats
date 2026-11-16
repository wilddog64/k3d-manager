#!/usr/bin/env bats

setup() {
  export HOME="$BATS_TEST_TMPDIR/home" CODEX_HOME="$BATS_TEST_TMPDIR/codex"
  export K3DM_WORKTREE_ROOT="$BATS_TEST_TMPDIR/worktrees" PUSHGATEWAY_URL=http://127.0.0.1:9
  export K3DM_DISPATCH_STALL_SECONDS=10 K3DM_DISPATCH_STALL_MAX_PROCS=200
  export TEST_WORK="$K3DM_WORKTREE_ROOT/v9.9.9/task" TEST_RUN="$K3DM_WORKTREE_ROOT/v9.9.9/task.run"
  export TEST_DB="$HOME/.gemini/antigravity-cli/conversations/test.db"
  mkdir -p "$HOME/bin" "$(dirname "$TEST_DB")" "$CODEX_HOME/sessions" "$TEST_WORK" "$TEST_RUN"
  [[ "$HOME" == "$BATS_TEST_TMPDIR"/* && "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR"/* && "$CODEX_HOME" == "$BATS_TEST_TMPDIR"/* ]]
  export PATH="$HOME/bin:$PATH"
  sleep 300 & export TEST_WORKER=$!
  printf 'pid=%s\nstarted=1\nprocess_start=unavailable\n' "$TEST_WORKER" >"$TEST_RUN/start"
  printf '%s\n' "$TEST_WORKER" >"$TEST_RUN/pid"
  printf 'agy\n' >"$TEST_RUN/agent"
  # Shape from macOS M4 ps -axo pid=,ppid=,command=, 2026-11-16.
  cat >"$HOME/bin/ps" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == -p ]]; then exec /bin/ps "$@"; fi
printf '%s %s %s\n' "$TEST_WORKER" 1 worker
printf '%s %s %s\n' "$((TEST_WORKER + 100000))" "$TEST_WORKER" agy
printf '300000 1 %s-extra/job\n' "$TEST_WORK"
if [[ "${TEST_PROCESS_EXACT:-0}" == 1 ]]; then printf '300001 1 %s\n' "$TEST_WORK"; fi
for ((i=0; i<${TEST_PROC_COUNT:-0}; i++)); do printf '%s 1 %s/job\n' "$((i+200000))" "$TEST_WORK"; done
STUB
  # Shape from lsof -Fn -p on M4, agy pid 84968, 2026-11-16.
  cat >"$HOME/bin/lsof" <<'STUB'
#!/usr/bin/env bash
[[ "${TEST_LSOF:-yes}" == yes && "$3" == "$((TEST_WORKER + 100000))" ]] || exit 1
printf 'p%s\nn%s\n' "$3" "$TEST_DB"
STUB
  cat >"$HOME/bin/git" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *'rev-parse --show-toplevel'*) printf '%s\n' "$TEST_WORK" ;;
  *'symbolic-ref --quiet --short HEAD'*) printf 'k3d-manager-v9.9.9\n' ;;
  *) exit 0 ;;
esac
STUB
  for tool in date stat; do
    cat >"$HOME/bin/$tool" <<'STUB'
#!/usr/bin/env bash
case " $* " in *' -f '*|*' -r '*|*' -j '*) exit 1;; esac
exec "/bin/${0##*/}" "$@"
STUB
  done
  cat >"$HOME/bin/cp" <<'STUB'
#!/usr/bin/env bash
if [[ "${TEST_RECORD_COPY:-0}" == 1 ]]; then
  printf '%s\n' "${@: -1}" >"$HOME/failed-copy-destination"
fi
exec /bin/cp "$@"
STUB
  chmod +x "$HOME/bin/"*
  python3 - "$TEST_DB" "$HOME/ready" <<'PY' &
import sqlite3, sys, time
c = sqlite3.connect(sys.argv[1]); c.execute('pragma journal_mode=wal'); c.execute('create table steps(id integer)'); c.execute('insert into steps values(1)'); c.commit()
open(sys.argv[2], 'w').close()
time.sleep(300)
PY
  export TEST_DB_HOLDER=$!
  for i in {1..100}; do [[ -e "$HOME/ready" ]] && break; sleep 0.05; done
  [ -e "$HOME/ready" ]
  : >"$TEST_RUN/agy.log"
  export SCRIPT="${TEST_DISPATCH_SCRIPT:-$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch}"
}

teardown() {
  kill "$TEST_DB_HOLDER" "$TEST_WORKER" 2>/dev/null || true
  wait "$TEST_DB_HOLDER" "$TEST_WORKER" 2>/dev/null || true
}

snapshot() {
  find "$HOME/.gemini" "$K3DM_WORKTREE_ROOT" "$TEST_WORK" -type f -exec shasum -a 256 {} \; | sort
}

@test "E1: frozen agy steps stall with a fresh log, but growing steps stay running with an old log" {
  local old
  old="$(($(date +%s)-100))"
  printf 'db=%s steps=1 since=%s\n' "$TEST_DB" "$old" >"$TEST_RUN/stall-watch.state"
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled (silent '* ]]
  rm "$TEST_RUN/agy.log"
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled (silent '* ]]
  : >"$TEST_RUN/agy.log"
  perl -e 'utime(time-3000,time-3000,$ARGV[0])' "$TEST_RUN/agy.log"
  sqlite3 "$TEST_DB" 'insert into steps values(2);'
  run "$SCRIPT" status task
  [[ "$output" == *'state: running'* ]]
}

@test "E1: codex rollout overrides log age in both directions" {
  printf 'codex\n' >"$TEST_RUN/agent"
  printf 'session id: abc123\n' >"$TEST_RUN/codex.log"
  local rollout="$CODEX_HOME/sessions/rollout-2026-abc123.jsonl"
  : >"$rollout"
  perl -e 'utime(time-3000,time-3000,$ARGV[0])' "$rollout"
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled (silent '* ]]
  touch "$rollout"
  perl -e 'utime(time-3000,time-3000,$ARGV[0])' "$TEST_RUN/codex.log"
  run "$SCRIPT" status task
  [[ "$output" == *'state: running'* ]]
}

@test "E1: process threshold and disabled threshold" {
  export TEST_PROC_COUNT=3 K3DM_DISPATCH_STALL_MAX_PROCS=2 TEST_LSOF=no
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled (silent '* ]]
  export K3DM_DISPATCH_STALL_MAX_PROCS=0
  run "$SCRIPT" status task
  [[ "$output" == *'state: running'* ]]
}

@test "E2: live and stalled listings are read-only and restricted to newest version" {
  local old before
  old="$(($(date +%s)-100))"
  printf 'db=%s steps=1 since=%s\n' "$TEST_DB" "$old" >"$TEST_RUN/stall-watch.state"
  mkdir -p "$K3DM_WORKTREE_ROOT/v1.0.0/older" "$K3DM_WORKTREE_ROOT/v1.0.0/older.run"
  cp "$TEST_RUN/start" "$K3DM_WORKTREE_ROOT/v1.0.0/older.run/start"
  before="$(snapshot)"
  run "$SCRIPT" stalled --live
  [ "$status" -eq 0 ]; [[ "$output" == *$'task\tv9.9.9\t'* && "$output" != *older* ]]
  run "$SCRIPT" stalled
  [ "$status" -eq 0 ]; [[ "$output" == *$'task\tv9.9.9\t'* ]]
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
  run "$SCRIPT" open
  local after
  after="$(snapshot)"
  if [[ "$before" != "$after" ]]; then diff -u <(printf "%s\n" "$before") <(printf "%s\n" "$after"); return 1; fi
}

@test "M4: lsof holder selects the db on first run and resume despite other candidates" {
  local old
  old="$(($(date +%s)-100))"
  sqlite3 "$(dirname "$TEST_DB")/other.db" 'create table steps(id);'
  printf 'db=%s steps=1 since=%s\n' "$TEST_DB" "$old" >"$TEST_RUN/stall-watch.state"
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
  printf 'resume-session\n' >"$TEST_RUN/session"
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
  printf 'db=%s steps=0 since=%s\n' "$(dirname "$TEST_DB")/other.db" "$old" >"$TEST_RUN/stall-watch.state"
  run "$SCRIPT" status task
  [[ "$output" == *'state: running'* ]]
}

@test "M4: fallback needs exactly one database born within ten seconds of the log" {
  local candidate second old
  export TEST_LSOF=no
  candidate="$(dirname "$TEST_DB")/candidate.db"
  second="$(dirname "$TEST_DB")/second.db"
  old="$(($(date +%s)-100))"
  sqlite3 "$candidate" 'create table steps(id); insert into steps values(1);'
  printf 'db=%s steps=1 since=%s\n' "$candidate" "$old" >"$TEST_RUN/stall-watch.state"
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
  sqlite3 "$second" 'create table steps(id); insert into steps values(1);'
  run "$SCRIPT" status task
  [[ "$output" == *'state: running'* ]]
  rm "$candidate" "$second"
  run "$SCRIPT" status task
  [[ "$output" == *'state: running'* ]]
  export TEST_PROC_COUNT=3 K3DM_DISPATCH_STALL_MAX_PROCS=2
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
}

@test "M4: failed db copy gives no steps signal with a working-copy control" {
  local old
  old="$(($(date +%s)-100))"
  printf 'db=%s steps=1 since=%s\n' "$TEST_DB" "$old" >"$TEST_RUN/stall-watch.state"
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
  chmod 000 "$TEST_DB"
  [ ! -r "$TEST_DB" ]
  export TEST_RECORD_COPY=1
  run "$SCRIPT" status task
  [[ "$output" == *'state: running'* ]]
  local destination
  destination="$(cat "$HOME/failed-copy-destination")"
  [ ! -e "${destination%/*}" ]
  chmod 600 "$TEST_DB"
  export TEST_PROC_COUNT=3 K3DM_DISPATCH_STALL_MAX_PROCS=2
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
}

@test "N6 control: pointing the probe at the live db changes the snapshot" {
  local mutant="$BATS_TEST_TMPDIR/mutant" before old
  mkdir -p "$mutant/bin" "$mutant/scripts"
  ln -s "$(cd "$BATS_TEST_DIRNAME/../../lib" && pwd)" "$mutant/scripts/lib"
  python3 - "$SCRIPT" "$mutant/bin/k3dm-codex-dispatch" <<'PYMUTATE'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text()
a = s.index('_dispatch_stall_count() (')
b = s.index('_dispatch_stall_db_sample() {', a)
s = s[:a] + "_dispatch_stall_count() { sqlite3 \"file:$1?mode=ro\" 'select count(*) from steps'; }\n\n" + s[b:]
pathlib.Path(sys.argv[2]).write_text(s)
PYMUTATE
  chmod +x "$mutant/bin/k3dm-codex-dispatch"
  old="$(($(date +%s)-100))"
  printf 'db=%s steps=1 since=%s\n' "$TEST_DB" "$old" >"$TEST_RUN/stall-watch.state"
  before="$(snapshot)"
  run "$mutant/bin/k3dm-codex-dispatch" status task
  [[ "$output" == *'state: stalled'* ]]
  [ "$before" != "$(snapshot)" ]
}

@test "N4: open row is identical when the status changes to stalled" {
  local old running_row
  printf '{"ts":1,"event":"start","version":"v9.9.9","slug":"task"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run "$SCRIPT" status task
  [[ "$output" == *'state: running'* ]]
  run "$SCRIPT" open
  [ "$status" -eq 1 ]; running_row="$output"
  old="$(($(date +%s)-100))"
  printf 'db=%s steps=1 since=%s\n' "$TEST_DB" "$old" >"$TEST_RUN/stall-watch.state"
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
  run "$SCRIPT" open
  [ "$status" -eq 1 ]; [ "$output" = "$running_row" ]
}

@test "M3: nonnumeric process limit falls back to 200 and zero disables silence" {
  local old
  export K3DM_DISPATCH_STALL_MAX_PROCS=invalid TEST_PROC_COUNT=201
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
  export TEST_PROC_COUNT=200
  run "$SCRIPT" status task
  [[ "$output" == *'state: running'* ]]
  old="$(($(date +%s)-100))"
  printf 'db=%s steps=1 since=%s\n' "$TEST_DB" "$old" >"$TEST_RUN/stall-watch.state"
  export K3DM_DISPATCH_STALL_SECONDS=0
  run "$SCRIPT" status task
  [[ "$output" == *'state: running'* ]]
}

@test "M6: stalled listing is cwd independent and usage names both forms" {
  local old
  old="$(($(date +%s)-100))"
  printf 'db=%s steps=1 since=%s\n' "$TEST_DB" "$old" >"$TEST_RUN/stall-watch.state"
  run bash -c 'cd /; "$1" stalled' _ "$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
  [ "$status" -eq 0 ]; [[ "$output" == *$'task\tv9.9.9\t'* ]]
  run "$SCRIPT" --help
  [[ "$output" == *'stalled [--live]'* ]]
}

@test "M4: unopenable database falls back to the process limit" {
  local old
  old="$(($(date +%s)-100))"
  printf 'db=%s steps=1 since=%s\n' "$TEST_DB" "$old" >"$TEST_RUN/stall-watch.state"
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
  export TEST_DB="$(dirname "$TEST_DB")/broken.db"
  printf 'not a sqlite database\n' >"$TEST_DB"
  printf 'db=%s steps=1 since=%s\n' "$TEST_DB" "$old" >"$TEST_RUN/stall-watch.state"
  run "$SCRIPT" status task
  [[ "$output" == *'state: running'* ]]
  export TEST_PROC_COUNT=3 K3DM_DISPATCH_STALL_MAX_PROCS=2
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
}

@test "M2: missing or ambiguous rollouts fall back to the newest codex log" {
  printf 'codex\n' >"$TEST_RUN/agent"
  printf 'session id: abc123\n' >"$TEST_RUN/codex.log"
  perl -e 'utime(time-3000,time-3000,$ARGV[0])' "$TEST_RUN/codex.log"
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
  mkdir -p "$CODEX_HOME/sessions/one" "$CODEX_HOME/sessions/two"
  : >"$CODEX_HOME/sessions/one/rollout-a-abc123.jsonl"
  : >"$CODEX_HOME/sessions/two/rollout-b-abc123.jsonl"
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
  touch "$TEST_RUN/codex.log"
  run "$SCRIPT" status task
  [[ "$output" == *'state: running'* ]]
}

@test "M6: status reports only the newest version directory" {
  local newrun="$K3DM_WORKTREE_ROOT/v10.0.0/newer.run"
  mkdir -p "$K3DM_WORKTREE_ROOT/v10.0.0/newer" "$newrun"
  cp "$TEST_RUN/start" "$newrun/start"
  printf 'agy\n' >"$newrun/agent"
  run "$SCRIPT" status
  [[ "$output" == *'task: newer'* && "$output" != *'task: task'* ]]
}

@test "M3: process path boundary excludes lookalikes and accepts the exact path" {
  export TEST_PROC_COUNT=1 K3DM_DISPATCH_STALL_MAX_PROCS=1 TEST_LSOF=no
  run "$SCRIPT" status task
  [[ "$output" == *'state: running'* ]]
  export TEST_PROCESS_EXACT=1
  run "$SCRIPT" status task
  [[ "$output" == *'state: stalled'* ]]
}

@test "N10 control: BSD time flags fail under the fixture PATH" {
  run stat -f '%m' "$TEST_RUN/start"
  [ "$status" -ne 0 ]
  run date -r "$TEST_RUN/start"
  [ "$status" -ne 0 ]
  run perl -e 'print((stat shift)[9])' "$TEST_RUN/start"
  [ "$status" -eq 0 ]; [[ "$output" =~ ^[0-9]+$ ]]
}

@test "A2: watcher refresh uses the dispatcher database sample" {
  local watch="$BATS_TEST_DIRNAME/../../../bin/k3dm-dispatch-stall-watch" before
  export K3DM_STALL_NOTIFY_BIN="$HOME/bin/missing-notifier"
  run "$watch"
  [ "$status" -eq 0 ]
  [[ "$(cat "$TEST_RUN/stall-watch.state")" == "db=$TEST_DB steps=1 since="* ]]
  printf 'db=%s steps=1 since=2\n' "$TEST_DB" > "$TEST_RUN/stall-watch.state"
  sqlite3 "$TEST_DB" 'insert into steps values(2);'
  before="$(find "$HOME/.gemini" -type f -exec shasum -a 256 {} \; | sort)"
  run "$watch"
  [ "$status" -eq 0 ]
  [[ "$(cat "$TEST_RUN/stall-watch.state")" == "db=$TEST_DB steps=2 since="* ]]
  [ "$(find "$HOME/.gemini" -type f -exec shasum -a 256 {} \; | sort)" = "$before" ]
}
