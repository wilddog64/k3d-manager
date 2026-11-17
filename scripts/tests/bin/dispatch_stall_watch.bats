#!/usr/bin/env bats

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home" K3DM_WORKTREE_ROOT="$BATS_TEST_TMPDIR/root" PUSHGATEWAY_URL=http://127.0.0.1:9
  export K3DM_STALL_DISPATCH_BIN="$BATS_TEST_TMPDIR/dispatch" K3DM_STALL_NOTIFY_BIN="$BATS_TEST_TMPDIR/notify"
  export TEST_RUN="$K3DM_WORKTREE_ROOT/v1.0.0/task.run" TEST_TREE="$K3DM_WORKTREE_ROOT/v1.0.0/task" TEST_NOTICES="$BATS_TEST_TMPDIR/notices"
  mkdir -p "$HOME" "$TEST_RUN" "$TEST_TREE"
  [[ "$HOME" == "$BATS_TEST_TMPDIR/"* && "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  printf 'pid=123\nstarted=123\n' > "$TEST_RUN/start"
  printf 'hello\n' > "$TEST_RUN/codex.log"
  cat > "$K3DM_STALL_DISPATCH_BIN" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  stalled) if [[ "${2:-}" != --live ]]; then printf 'task\tv1.0.0\t%s\t%s\t3001\t3\n' "$TEST_RUN" "$TEST_TREE"; fi ;;
esac
STUB
  cat > "$K3DM_STALL_NOTIFY_BIN" <<'STUB'
#!/usr/bin/env bash
cat >> "$TEST_NOTICES"
[[ ! -e "$TEST_RUN/fail-notice" ]]
STUB
  chmod +x "$K3DM_STALL_DISPATCH_BIN" "$K3DM_STALL_NOTIFY_BIN"
}

teardown() {
  local pid
  for pid in $(jobs -pr); do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
}

_start_fixture() {
  local name="$1"
  /bin/bash -c 'exec -a "$1" /bin/sleep 300' _ "$name" &
  FIXTURE_PID=$!
  FIXTURE_PIDS="${FIXTURE_PIDS:-} $FIXTURE_PID"
}

_fixture_alive() {
  local pid
  for pid in "$@"; do kill -0 "$pid" 2>/dev/null || return 1; done
}

_scratch_watcher() {
  local copy="$1" mutation="$2"
  mkdir -p "${copy%/*}" "$BATS_TEST_TMPDIR/mutant/scripts"
  [[ -e "$BATS_TEST_TMPDIR/mutant/scripts/lib" ]] || ln -s "$REPO/scripts/lib" "$BATS_TEST_TMPDIR/mutant/scripts/lib"
  python3 - "$REPO/bin/k3dm-dispatch-stall-watch" "$copy" "$mutation" <<'PYCODE'
import sys
source = open(sys.argv[1]).read()
if sys.argv[3] == 'signal':
    source = source.replace('  pid="$(_run_command --soft --quiet awk', '  /usr/bin/pkill -TERM -f -- "$tree" || true\n  pid="$(_run_command --soft --quiet awk', 1)
if sys.argv[3] == 'disclose':
    source = source.replace('  local limit="${K3DM_DISPATCH_STALL_SECONDS:-2700}"', '  ps -axo command >> "$dir/summary.txt"\n  local limit="${K3DM_DISPATCH_STALL_SECONDS:-2700}"', 1)
source = source.replace('  _watch_capture "$slug" "$version" "$run" "$tree" "$silent" "$procs"', '  _watch_capture "$slug" "$version" "$run" "$tree" "$silent" "$procs"\n  printf "%s\\n" "$$" > "$WATCH_READY"\n  while [[ ! -e "$WATCH_RELEASE" ]]; do sleep 0.05; done')
open(sys.argv[2], 'w').write(source)
PYCODE
  chmod +x "$copy"
}

_wait_for_watcher() {
  local i
  for i in {1..200}; do [[ -s "$WATCH_READY" ]] && return 0; sleep 0.05; done
  return 1
}

@test "E3: captures once, records and notifies, and handles a new start" {
  run "$REPO/bin/k3dm-dispatch-stall-watch"
  [ "$status" -eq 0 ]
  [ "$(find "$TEST_RUN" -name summary.txt | wc -l | tr -d ' ')" = 1 ]
  [ "$(wc -l < "$K3DM_WORKTREE_ROOT/ledger.jsonl" | tr -d ' ')" = 1 ]
  [ "$(wc -l < "$TEST_NOTICES" | tr -d ' ')" = 1 ]
  run "$REPO/bin/k3dm-dispatch-stall-watch"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$TEST_NOTICES" | tr -d ' ')" = 1 ]
  [ "$(find "$TEST_RUN" -maxdepth 1 -type d -name 'stall-*' | wc -l | tr -d ' ')" = 1 ]
  [ "$(wc -l < "$K3DM_WORKTREE_ROOT/ledger.jsonl" | tr -d ' ')" = 1 ]
  printf 'pid=124\nstarted=124\n' > "$TEST_RUN/start"
  run "$REPO/bin/k3dm-dispatch-stall-watch"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$TEST_NOTICES" | tr -d ' ')" = 2 ]
  [ "$(wc -l < "$K3DM_WORKTREE_ROOT/ledger.jsonl" | tr -d ' ')" = 2 ]
  [ "$(find "$TEST_RUN" -maxdepth 1 -type d -name 'stall-*' | wc -l | tr -d ' ')" = 2 ]
}

@test "E4: failed notice is retried without a second event" {
  touch "$TEST_RUN/fail-notice"
  run "$REPO/bin/k3dm-dispatch-stall-watch"
  [ "$status" -eq 0 ]
  [[ "$output" == *notice* ]]
  rm "$TEST_RUN/fail-notice"
  run "$REPO/bin/k3dm-dispatch-stall-watch"
  [ "$status" -eq 0 ]
  [ "$(find "$TEST_RUN" -name notified | wc -l | tr -d ' ')" = 1 ]
  [ "$(find "$TEST_RUN" -maxdepth 1 -type d -name 'stall-*' | wc -l | tr -d ' ')" = 1 ]
  [ "$(wc -l < "$K3DM_WORKTREE_ROOT/ledger.jsonl" | tr -d ' ')" = 1 ]
}

@test "baseline keeps its time until the sampled count changes" {
  printf 'agy\n' > "$TEST_RUN/agent"
  printf '4\n' > "$BATS_TEST_TMPDIR/count"
  export SAMPLE_COUNT="$BATS_TEST_TMPDIR/count"
  cat > "$K3DM_STALL_DISPATCH_BIN" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  stalled) [[ "${2:-}" != --live ]] || printf 'task\tv1.0.0\t%s\t%s\n' "$TEST_RUN" "$TEST_TREE" ;;
  _stall-sample) printf '/fake/db\t%s\n' "$(cat "$SAMPLE_COUNT")" ;;
esac
STUB
  run "$REPO/bin/k3dm-dispatch-stall-watch"
  [ "$status" -eq 0 ]
  [[ "$(cat "$TEST_RUN/stall-watch.state")" == 'db=/fake/db steps=4 since='* ]]
  printf 'db=/fake/db steps=4 since=124\n' > "$TEST_RUN/stall-watch.state"
  run "$REPO/bin/k3dm-dispatch-stall-watch"
  [ "$status" -eq 0 ]
  grep -qx 'db=/fake/db steps=4 since=124' "$TEST_RUN/stall-watch.state"
  printf '5\n' > "$SAMPLE_COUNT"
  run "$REPO/bin/k3dm-dispatch-stall-watch"
  [ "$status" -eq 0 ]
  [[ "$(cat "$TEST_RUN/stall-watch.state")" == 'db=/fake/db steps=5 since='* ]]
  run grep -q 'since=124$' "$TEST_RUN/stall-watch.state"
  [ "$status" -eq 1 ]
}

@test "E3: evidence, notice and ledger disclose no fixture argv" {
  local dir copy="$BATS_TEST_TMPDIR/mutant/bin/watch" phase result
  _start_fixture "$TEST_TREE/private-marker"
  for phase in real disclose; do
    rm -f "$TEST_RUN"/stall-handled-* "$K3DM_WORKTREE_ROOT/ledger.jsonl" "$TEST_NOTICES"
    rm -rf "$TEST_RUN"/stall-20*
    export WATCH_READY="$BATS_TEST_TMPDIR/ready-$phase" WATCH_RELEASE="$BATS_TEST_TMPDIR/release-$phase"
    _scratch_watcher "$copy" "$phase"
    "$copy" > "$BATS_TEST_TMPDIR/output-$phase" 2>&1 &
    local watcher=$!
    FIXTURE_PIDS="${FIXTURE_PIDS:-} $watcher"
    _wait_for_watcher
    dir="$(cat "$TEST_RUN/stall-handled-123-123")"
    for file in ps.txt log-tail.txt status.txt diff.patch summary.txt notified; do [ -f "$dir/$file" ]; done
    grep -q 'private-marker' "$dir/ps.txt"
    result=0
    grep -q 'private-marker' "$dir/summary.txt" "$TEST_NOTICES" "$K3DM_WORKTREE_ROOT/ledger.jsonl" || result=$?
    if [[ "$phase" == real ]]; then
      [ "$result" -eq 1 ]
      [[ "$(cat "$TEST_NOTICES")" == *task* && "$(cat "$TEST_NOTICES")" == *v1.0.0* && "$(cat "$TEST_NOTICES")" == *3001* && "$(cat "$TEST_NOTICES")" == *'3 processes'* && "$(cat "$TEST_NOTICES")" == *"$dir"* ]]
      jq -e --arg stall "${dir##*/}" '.event == "stall_detected" and (.ts | type == "number" and . > 0) and .version == "v1.0.0" and .slug == "task" and .stall == $stall and .run == 1 and .reason == "silent" and .silent_s == 3001 and .procs == 3 and .killed == 0' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
      echo 'N9 real disclosure check: green' >&3
    else
      [ "$result" -eq 0 ]
      echo 'N9 mutant disclosure check: red (marker found in summary)' >&3
    fi
    touch "$WATCH_RELEASE"
    wait "$watcher"
  done
}

@test "E4: ledger failure does not prevent evidence or notice" {
  mkdir "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run "$REPO/bin/k3dm-dispatch-stall-watch"
  [ "$status" -eq 0 ]
  [[ "$output" == *'ledger write failed'* ]]
  [ -s "$TEST_NOTICES" ]
  [ -f "$(cat "$TEST_RUN/stall-handled-123-123")/summary.txt" ]
}

@test "N2 and N3: no process signals or future hooks, with mutation controls" {
  local copy="$BATS_TEST_TMPDIR/watch-copy"
  cp "$REPO/bin/k3dm-dispatch-stall-watch" "$copy"
  run grep -Eq '(^|[[:space:];])([^[:space:];]*/)?(kill|pkill)([[:space:];]|$)|K3DM_STALL_(DRAIN|DIAGNOSE)' "$copy"
  [ "$status" -eq 1 ]
  printf '\n/usr/bin/pkill -TERM 123\n' >> "$copy"
  grep -Eq '(^|[[:space:];])([^[:space:];]*/)?(kill|pkill)([[:space:];]|$)|K3DM_STALL_(DRAIN|DIAGNOSE)' "$copy"
  cp "$REPO/bin/k3dm-dispatch-stall-watch" "$copy"
  printf '\n/bin/kill -s TERM 123\n' >> "$copy"
  grep -Eq '(^|[[:space:];])([^[:space:];]*/)?(kill|pkill)([[:space:];]|$)|K3DM_STALL_(DRAIN|DIAGNOSE)' "$copy"
  cp "$REPO/bin/k3dm-dispatch-stall-watch" "$copy"
  printf '\n"$K3DM_STALL_DRAIN_CMD"\n' >> "$copy"
  grep -Eq '(^|[[:space:];])([^[:space:];]*/)?(kill|pkill)([[:space:];]|$)|K3DM_STALL_(DRAIN|DIAGNOSE)' "$copy"
}

@test "N2: real fixtures survive and the pkill mutation fails the same check" {
  local phase watcher target worker lookalike result copy="$BATS_TEST_TMPDIR/mutant/bin/watch"
  for phase in real signal; do
    _start_fixture "$TEST_TREE/target"; target="$FIXTURE_PID"
    _start_fixture "$TEST_TREE/worker"; worker="$FIXTURE_PID"
    _start_fixture "$TEST_TREE-lookalike"; lookalike="$FIXTURE_PID"
    printf 'pid=%s\nstarted=123\n' "$worker" > "$TEST_RUN/start"
    export WATCH_READY="$BATS_TEST_TMPDIR/ready-$phase" WATCH_RELEASE="$BATS_TEST_TMPDIR/release-$phase"
    _scratch_watcher "$copy" "$phase"
    "$copy" > "$BATS_TEST_TMPDIR/output-$phase" 2>&1 & watcher=$!
    FIXTURE_PIDS="${FIXTURE_PIDS:-} $watcher"
    _wait_for_watcher
    [ "$(cat "$WATCH_READY")" = "$watcher" ]
    result=0
    _fixture_alive "$target" "$lookalike" "$worker" "$watcher" || result=$?
    if [[ "$phase" == real ]]; then
      [ "$result" -eq 0 ]
      echo 'N2 real process check: green' >&3
    else
      [ "$result" -ne 0 ]
      echo 'N2 pkill mutant process check: red' >&3
    fi
    touch "$WATCH_RELEASE"
    wait "$watcher"
  done
}

@test "E7: watcher avoids BSD time flags and the guard catches a mutation" {
  local copy="$BATS_TEST_TMPDIR/time-copy"
  cp "$REPO/bin/k3dm-dispatch-stall-watch" "$copy"
  run grep -E 'stat[[:space:]]+-f|date[[:space:]]+-(r|j)' "$copy"
  [ "$status" -eq 1 ]
  printf '\nstat -f %%m file\n' >> "$copy"
  run grep -E 'stat[[:space:]]+-f|date[[:space:]]+-(r|j)' "$copy"
  [ "$status" -eq 0 ]
}

@test "E4: missing notifier and failed git still leave evidence and ledger" {
  export K3DM_STALL_NOTIFY_BIN="$BATS_TEST_TMPDIR/missing-notifier"
  run "$REPO/bin/k3dm-dispatch-stall-watch"
  [ "$status" -eq 0 ]
  [[ "$output" == *'notice failed'* ]]
  local dir
  dir="$(cat "$TEST_RUN/stall-handled-123-123")"
  [ -s "$dir/errors.txt" ]
  [ -f "$dir/status.txt" ]
  [ -f "$dir/diff.patch" ]
  [ -s "$K3DM_WORKTREE_ROOT/ledger.jsonl" ]
}


@test "N3 control: only a mutated watcher runs future hook commands" {
  mkdir -p "$BATS_TEST_TMPDIR/hook-mutant/bin" "$BATS_TEST_TMPDIR/hook-mutant/scripts"
  ln -s "$REPO/scripts/lib" "$BATS_TEST_TMPDIR/hook-mutant/scripts/lib"
  printf '#!/bin/bash\nprintf called >> "$HOOK_CALLS"\n' > "$BATS_TEST_TMPDIR/hook"
  chmod +x "$BATS_TEST_TMPDIR/hook"
  export HOOK_CALLS="$BATS_TEST_TMPDIR/hook-calls" K3DM_STALL_DRAIN_CMD="$BATS_TEST_TMPDIR/hook" K3DM_STALL_DIAGNOSE_CMD="$BATS_TEST_TMPDIR/hook"
  run "$REPO/bin/k3dm-dispatch-stall-watch"
  [ "$status" -eq 0 ]
  [ ! -e "$HOOK_CALLS" ]
  cp "$REPO/bin/k3dm-dispatch-stall-watch" "$BATS_TEST_TMPDIR/hook-mutant/bin/watch"
  printf '\n"$K3DM_STALL_DRAIN_CMD"\n"$K3DM_STALL_DIAGNOSE_CMD"\n' >> "$BATS_TEST_TMPDIR/hook-mutant/bin/watch"
  run "$BATS_TEST_TMPDIR/hook-mutant/bin/watch"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOOK_CALLS")" = calledcalled ]
}

@test "invalid numeric fields skip only their run" {
  local bad_run="$K3DM_WORKTREE_ROOT/v1.0.0/bad.run" bad_tree="$K3DM_WORKTREE_ROOT/v1.0.0/bad"
  mkdir -p "$bad_run" "$bad_tree"
  printf 'pid=456\nstarted=456\n' > "$bad_run/start"
  export BAD_RUN="$bad_run" BAD_TREE="$bad_tree"
  cat > "$K3DM_STALL_DISPATCH_BIN" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == stalled && "${2:-}" != --live ]]; then
  printf 'bad\tv1.0.0\t%s\t%s\t%s\t%s\n' "$BAD_RUN" "$BAD_TREE" "$BAD_SILENT" "$BAD_PROCS"
  printf 'task\tv1.0.0\t%s\t%s\t3001\t3\n' "$TEST_RUN" "$TEST_TREE"
fi
STUB
  local field
  for field in silent procs; do
    rm -f "$TEST_RUN"/stall-handled-* "$K3DM_WORKTREE_ROOT/ledger.jsonl" "$TEST_NOTICES"
    export BAD_SILENT=3001 BAD_PROCS=3
    if [[ "$field" == silent ]]; then BAD_SILENT=wrong; else BAD_PROCS=wrong; fi
    run "$REPO/bin/k3dm-dispatch-stall-watch"
    [ "$status" -eq 0 ]
    [[ "$output" == *'invalid'* ]]
    [ "$(printf '%s\n' "$output" | grep -c 'invalid stall values')" = 1 ]
    [ ! -e "$BAD_RUN/stall-handled-456-456" ]
    [ -f "$TEST_RUN/stall-handled-123-123" ]
    [ "$(wc -l < "$K3DM_WORKTREE_ROOT/ledger.jsonl" | tr -d ' ')" = 1 ]
    [ -s "$TEST_NOTICES" ]
  done
}
