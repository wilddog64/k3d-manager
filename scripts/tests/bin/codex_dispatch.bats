#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export FIXTURE="$BATS_TEST_TMPDIR/fixture" ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  export K3DM_WORKTREE_ROOT="$BATS_TEST_TMPDIR/worktrees" HOME="$BATS_TEST_TMPDIR/home"
  export K3DM_DISPATCH_PUSHGATEWAY_URL="http://127.0.0.1:9" CODEX_HOME="$BATS_TEST_TMPDIR/codex-home"
  export K3DM_CODEX_BIN="$BATS_TEST_TMPDIR/codex-stub"
  mkdir -p "$FIXTURE" "$HOME" "$K3DM_WORKTREE_ROOT"
  export K3DM_DISPATCH_METRICS_BIN="$BATS_TEST_TMPDIR/metrics-stub"
  cat >"$K3DM_DISPATCH_METRICS_BIN" <<'METRICS'
#!/usr/bin/env bash
set -euo pipefail
printf 'start\n' >>"$METRICS_STARTS"
mkdir "$METRICS_ACTIVE" 2>/dev/null || : >"$METRICS_OVERLAP"
sleep 1
rmdir "$METRICS_ACTIVE" 2>/dev/null || true
METRICS
  chmod +x "$K3DM_DISPATCH_METRICS_BIN"
  export METRICS_STARTS="$BATS_TEST_TMPDIR/metrics-starts"
  export METRICS_ACTIVE="$BATS_TEST_TMPDIR/metrics-active" METRICS_OVERLAP="$BATS_TEST_TMPDIR/metrics-overlap"
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
exit "${STUB_RC:-0}"
STUB
  chmod +x "$K3DM_CODEX_BIN"
  export K3DM_AGY_BIN="$BATS_TEST_TMPDIR/agy-stub"
  cat >"$K3DM_AGY_BIN" <<'AGY'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == models ]]; then
  printf 'Fetching available models...\n'
  printf 'gemini-4-argon-medium\tGemini 4 Argon (Medium)\n'
  printf 'gemini-4-argon-high\tGemini 4 Argon (High)\n'
  printf 'gemini-4-argon-low\tGemini 4 Argon (Low)\n'
  printf 'gemini-test\tGemini Test\n'
  exit 0
fi
printf '%s\n' "$*" >>"${AGY_ARGV:?}"
printf '%s\n' "$PWD" >>"${AGY_ARGV}.cwd"
printf 'K3DM_DISPATCH_SLUG=%s\n' "${K3DM_DISPATCH_SLUG:-}" >>"${AGY_ARGV}.env"
[[ "${AGY_EDIT:-0}" != 1 ]] || printf 'agy working-tree edit\n' >a.txt
if [[ "${AGY_NO_USAGE:-0}" == 1 ]]; then
  printf '{"conversation_id":"agy-conversation-1"}\n'
else
  printf '{"conversation_id":"agy-conversation-1","usage":{"input_tokens":11,"output_tokens":3}}\n'
fi
[[ "${AGY_COMMIT:-0}" != 1 ]] || { printf 'agy commit\n' >a.txt; git add -A; git commit -m agy-commit >/dev/null; }
AGY
  chmod +x "$K3DM_AGY_BIN"
}

dispatch() { (cd "$FIXTURE" && "$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch" "$@"); }

@test "codex dispatch: agy runs in its worktree with default model and ledger identity" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv" STUB_ARGV="$BATS_TEST_TMPDIR/codex.argv" STUB_ENV="$BATS_TEST_TMPDIR/codex.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug agy --agent agy >/dev/null
  sleep 1
  [[ "$(<"$BATS_TEST_TMPDIR/agy.argv")" == *"--model gemini-4-argon-medium"* ]]
  [[ "$(<"$BATS_TEST_TMPDIR/agy.argv")" == *"--sandbox"* ]]
  grep -q '^K3DM_DISPATCH_SLUG=agy$' "$BATS_TEST_TMPDIR/agy.argv.env"
  [ "$(cd "$(<"$BATS_TEST_TMPDIR/agy.argv.cwd")" && pwd -P)" = "$(cd "$K3DM_WORKTREE_ROOT/v9.9.9/agy" && pwd -P)" ]
  [ "$(jq -r 'select(.event=="start")|.agent+":"+.model_source+":"+.model' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "agy:default:gemini-4-argon-medium" ]
  [ "$(jq -r 'select(.event=="agent_exit")|(.run|tostring)+":"+.session' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "1:agy-conversation-1" ]
  grep -q '"event":"agent_usage"' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  [ ! -e "$BATS_TEST_TMPDIR/codex.argv" ]
}

@test "codex dispatch: uncommitted agy work can be reviewed and landed" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv" AGY_EDIT=1
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug agy-land --agent agy >/dev/null
  sleep 1
  run dispatch status agy-land
  [[ "$output" == *"state: exited successfully"* ]]
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/agy-land/a.txt")" = "agy working-tree edit" ]
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/agy-land" add a.txt
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/agy-land" commit -m reviewed-agy-edit >/dev/null
  run dispatch land --slug agy-land --no-test
  [ "$status" -eq 0 ]; [[ "$output" == *"landed: agy-land"* ]]
}

@test "codex dispatch: unknown agy model fails before worktree creation" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug unknown --agent agy --model nope
  [ "$status" -eq 2 ]; [[ "$output" == *"unknown agy model: nope"* ]]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/unknown" ]
}

@test "codex dispatch: agy model matching uses only exact model IDs" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug display-name --agent agy --model 'Gemini 4 Argon (Medium)'
  [ "$status" -eq 2 ]; [[ "$output" == *"unknown agy model: Gemini 4 Argon (Medium)"* ]]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/display-name" ]
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug model-prefix --agent agy --model gemini-4-argon
  [ "$status" -eq 2 ]; [[ "$output" == *"unknown agy model: gemini-4-argon"* ]]
  [ ! -e "$K3DM_WORKTREE_ROOT/v9.9.9/model-prefix" ]
}

@test "codex dispatch: explicit agy and Codex models are recorded and passed" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug agy-model --agent agy --model gemini-test >/dev/null
  sleep 1
  [[ "$(<"$BATS_TEST_TMPDIR/agy.argv")" == *"--model gemini-test"* ]]
  [ "$(jq -r 'select(.event=="start" and .slug=="agy-model")|.model_source' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = explicit ]
  export STUB_ARGV="$BATS_TEST_TMPDIR/codex-model.argv" STUB_ENV="$BATS_TEST_TMPDIR/codex-model.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug codex-model --model gpt-test >/dev/null
  sleep 1
  [[ "$(<"$BATS_TEST_TMPDIR/codex-model.argv")" == "exec -m gpt-test --sandbox workspace-write -C $K3DM_WORKTREE_ROOT/v9.9.9/codex-model --add-dir $K3DM_WORKTREE_ROOT/v9.9.9/codex-model.run/state -o $K3DM_WORKTREE_ROOT/v9.9.9/codex-model.run/last-message.md -" ]]
  [ "$(jq -r 'select(.event=="start" and .slug=="codex-model")|.model_source' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = explicit ]
}

@test "codex dispatch: missing agy usage is recorded as null without token counts" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv" AGY_NO_USAGE=1
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug agy-no-usage --agent agy >/dev/null
  sleep 1
  [ "$(jq -r 'select(.event=="agent_exit")|.usage' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = null ]
  [ "$(jq -s '[.[]|select(.event=="agent_usage")]|length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 0 ]
  [ "$(jq -s '[.[]|select(has("tokens"))]|length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 0 ]
}

@test "codex dispatch: agy commit is a scope violation and cannot land" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv" AGY_COMMIT=1
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug committed --agent agy >/dev/null
  sleep 1
  grep -q '"event":"scope_violation"' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch status committed
  [[ "$output" == *"VIOLATION: agent committed"* ]]
  run dispatch land --slug committed --no-test
  [ "$status" -eq 2 ]; [[ "$output" == *"VIOLATION: agent committed"* ]]
}

@test "codex dispatch: default Codex command is unchanged and start identity is explicit" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/default.argv" STUB_ENV="$BATS_TEST_TMPDIR/default.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug codex >/dev/null
  sleep 1
  [ "$(jq -r 'select(.event=="start")|.agent+":"+(.model|tostring)+":"+.model_source' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "codex:null:inherited" ]
  [[ "$(<"$BATS_TEST_TMPDIR/default.argv")" == "exec --sandbox workspace-write -C $K3DM_WORKTREE_ROOT/v9.9.9/codex --add-dir $K3DM_WORKTREE_ROOT/v9.9.9/codex.run/state -o $K3DM_WORKTREE_ROOT/v9.9.9/codex.run/last-message.md -" ]]
}

@test "codex dispatch: agy resume requires and uses its stored conversation" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug resume --agent agy >/dev/null
  sleep 1
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  rm "$K3DM_WORKTREE_ROOT/v9.9.9/resume.run/session"
  run dispatch resume --slug resume --prompt-file "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 2 ]; [[ "$output" == *"agy run returned no conversation id; start a new task"* ]]
  printf 'agy-conversation-1\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/resume.run/session"
  dispatch resume --slug resume --prompt-file "$BATS_TEST_TMPDIR/p.md" >/dev/null
  sleep 1
  grep -q -- '--conversation agy-conversation-1' "$BATS_TEST_TMPDIR/agy.argv"
  ! grep -q -- '--continue' "$BATS_TEST_TMPDIR/agy.argv"
}

@test "codex dispatch: network is refused for agy" {
  export AGY_ARGV="$BATS_TEST_TMPDIR/agy.argv"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --agent agy --network
  [ "$status" -eq 2 ]; [[ "$output" == *"--network is not supported with --agent agy"* ]]
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

@test "codex dispatch: start records the spec path in the ledger" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/one.argv" STUB_ENV="$BATS_TEST_TMPDIR/one.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  [ "$(jq -r -s '.[0].spec' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "docs/plans/v9.9.9-demo.md" ]
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

@test "codex dispatch: land completes when the ledger is unwritable" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  sleep 1
  printf 'edited\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/one/a.txt"
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  rm "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  mkdir "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch land --slug one --no-test
  [ "$status" -eq 0 ]
  [ ! -d "$K3DM_WORKTREE_ROOT/v9.9.9/one" ]
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/landed" ]
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

@test "codex dispatch: argv has sandbox worktree and state dir" {
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

@test "codex dispatch: resume accepts a dead worker whose PID identity is stale" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  sleep 1
  rm "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit"
  sed -i.bak 's/^process_start=.*/process_start=not-the-worker/' "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/start"
  printf 'follow up\n' >"$BATS_TEST_TMPDIR/p.md"
  run dispatch resume --slug one --prompt-file "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 0 ]
  sleep 1
  [ "$(<"$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit")" = 0 ]
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/codex-2.log" ]
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
  [ "$(jq -r -s '.[0].spec' "$ledger")" = docs/plans/v9.9.9-demo.md ]
  [[ "$(jq -r -s '.[1].tree' "$ledger")" =~ ^[0-9a-f]{40}$ ]]
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/codex-tree" ]
  [ -z "$(git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" diff --cached --name-only)" ]
}

@test "codex dispatch: verify records pass tokens only for a landed task" {
  printf '{"ts":1,"event":"land","version":"v9.9.9","slug":"verified"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch verify --slug verified --result pass --tokens 456 --verifier codex
  [ "$status" -eq 0 ]
  [ "$(jq -r -s '.[-1].event' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = verify ]
  [ "$(jq -r -s '.[-1].result' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = pass ]
  [ "$(jq -r -s '.[-1].tokens' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = 456 ]
  [ "$(jq -r -s '.[-1].verifier' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = codex ]
}

@test "codex dispatch: verify refusals do not append ledger events" {
  printf '{"ts":1,"event":"start","version":"9.9.9","slug":"unlanded"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  before="$(wc -l <"$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  run dispatch verify --slug unlanded --result pass
  [ "$status" -ne 0 ]
  run dispatch verify --slug absent --result pass
  [ "$status" -ne 0 ]
  run dispatch verify --slug absent --result maybe
  [ "$status" -ne 0 ]
  run dispatch verify --slug absent --result pass --tokens 1.5
  [ "$status" -ne 0 ]
  run dispatch verify --slug absent --result pass --tokens ""
  [ "$status" -ne 0 ]
  [ "$(wc -l <"$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq "$before" ]
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

@test "codex dispatch: start records session token usage from CODEX_HOME" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  mkdir -p "$CODEX_HOME/sessions/2026/10/23"
  cat >"$CODEX_HOME/sessions/2026/10/23/rollout-test-01a122dd-71c3-7763-87f0-3de505f10168.jsonl" <<'EOF'
{"type":"session_meta","payload":{"id":"01a122dd-71c3-7763-87f0-3de505f10168","timestamp":"2026-10-23T10:00:00Z"}}
{"type":"turn_context","payload":{"model":"gpt-5.6-luna"}}
{"type":"event_msg","payload":{"info":{"total_token_usage":{"input_tokens":611180,"cached_input_tokens":561408,"output_tokens":5912,"reasoning_output_tokens":10}}}}
EOF
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  usage="$(jq -s 'map(select(.event == "codex_usage")) | .[0]' "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  [ "$(jq -r '.session' <<<"$usage")" = 01a122dd-71c3-7763-87f0-3de505f10168 ]
  [ "$(jq -r '.model' <<<"$usage")" = gpt-5.6-luna ]
  [ "$(jq -r '.input' <<<"$usage")" = 611180 ]
  [ "$(jq -r '.cached_input' <<<"$usage")" = 561408 ]
  [ "$(jq -r '.output' <<<"$usage")" = 5912 ]
}

@test "codex dispatch: missing session usage warns but start succeeds" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug one
  [ "$status" -eq 0 ]; sleep 1
  grep -q 'WARNING: expected one session file' "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/supervisor.log"
  [ "$(jq -s 'map(select(.event == "codex_usage")) | length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 0 ]
}

@test "codex dispatch: usage-backfill is idempotent" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  sleep 1
  for _ in {1..50}; do [[ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]] && break; sleep 0.1; done
  for _ in {1..50}; do [[ ! -d "$K3DM_WORKTREE_ROOT/metrics.lock" ]] && break; sleep 0.1; done
  : >"$METRICS_STARTS"
  mkdir -p "$CODEX_HOME/sessions/2026/10/23"
  cat >"$CODEX_HOME/sessions/2026/10/23/rollout-test-01a122dd-71c3-7763-87f0-3de505f10168.jsonl" <<'EOF'
{"type":"session_meta","payload":{"id":"01a122dd-71c3-7763-87f0-3de505f10168","timestamp":"2026-10-23T10:00:00Z"}}
{"type":"turn_context","payload":{"model":"gpt-5.6-luna"}}
{"type":"event_msg","payload":{"info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3}}}}
EOF
  run dispatch usage-backfill
  [ "$status" -eq 0 ]; [[ "$output" == *"backfilled: 1"* ]]; [[ "$output" == *"missing: 0"* ]]
  sleep 1.2
  [ "$(wc -l <"$METRICS_STARTS" | tr -d ' ')" -eq 1 ]
  run dispatch usage-backfill
  [ "$status" -eq 0 ]; [[ "$output" == *"backfilled: 0"* ]]
  [ "$(wc -l <"$METRICS_STARTS" | tr -d ' ')" -eq 1 ]
  [ "$(jq -s 'map(select(.event == "codex_usage")) | length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
}

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
