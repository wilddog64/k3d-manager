#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export ROOT="${BATS_TEST_DIRNAME}/../../.."
  export K3DM_AGENT_LEDGER_DIR="$BATS_TEST_TMPDIR/ledger"
  export K3DM_AGY_REAL="$BATS_TEST_TMPDIR/real-agy"
  export TMPDIR="$BATS_TEST_TMPDIR"
  cat >"$K3DM_AGY_REAL" <<'SH'
#!/usr/bin/env bash
printf '  status: done\n{"usage":{"input_tokens":12,"output_tokens":3,"response":"private"},"response":"private"}\n'
SH
  chmod +x "$K3DM_AGY_REAL"
}

@test "agy wrapper: records filtered JSON usage and passes output and exit through" {
  run "$ROOT/bin/k3dm-agy" --print 'secret prompt' --output-format json --model model-x
  [ "$status" -eq 0 ]
  [[ "$output" == *'"response":"private"'* ]]
  run python3 - "$K3DM_AGENT_LEDGER_DIR/agy.jsonl" <<'PY'
import json,sys
x=json.loads(open(sys.argv[1]).read())
assert x['agent']=='agy' and x['usage']=={'input_tokens':12,'output_tokens':3}
assert 'secret prompt' not in open(sys.argv[1]).read() and x['model']=='model-x'
PY
  [ "$status" -eq 0 ]
}

@test "agy wrapper: missing binary exits 127 without recursion" {
  run -127 env -u K3DM_AGY_REAL PATH="/usr/bin:/bin" "$ROOT/bin/k3dm-agy" --print x
  [ "$status" -eq 127 ]
  [[ "$output" == *'real agy not found on PATH'* ]]
}

@test "agy wrapper: finds the real binary after itself on PATH" {
  mkdir -p "$BATS_TEST_TMPDIR/path-first" "$BATS_TEST_TMPDIR/path-second"
  ln -s "$ROOT/bin/k3dm-agy" "$BATS_TEST_TMPDIR/path-first/agy"
  ln -s "$K3DM_AGY_REAL" "$BATS_TEST_TMPDIR/path-second/agy"
  run env -u K3DM_AGY_REAL PATH="$BATS_TEST_TMPDIR/path-first:$BATS_TEST_TMPDIR/path-second:/usr/bin:/bin" \
    K3DM_AGENT_LEDGER_DIR="$K3DM_AGENT_LEDGER_DIR" "$BATS_TEST_TMPDIR/path-first/agy" models
  [ "$status" -eq 0 ]
  [ ! -e "$K3DM_AGENT_LEDGER_DIR/agy.jsonl" ]
}

@test "agy wrapper: preserves the real exit code" {
  cat >"$K3DM_AGY_REAL" <<'SH'
#!/usr/bin/env bash
printf 'pass-through\n'
exit 23
SH
  chmod +x "$K3DM_AGY_REAL"
  run "$ROOT/bin/k3dm-agy" --prompt ignored
  [ "$status" -eq 23 ]
  [[ "$output" == *pass-through* ]]
  [ "$(wc -l <"$K3DM_AGENT_LEDGER_DIR/agy.jsonl" | tr -d ' ')" -eq 1 ]
}

@test "agy wrapper: interactive child receives wrapper stdin" {
  cat >"$K3DM_AGY_REAL" <<'SH'
#!/usr/bin/env bash
IFS= read -r line || line=
printf 'got:[%s]\n' "$line"
SH
  chmod +x "$K3DM_AGY_REAL"
  run bash -c 'printf "hello\\n" | K3DM_AGY_REAL="$1" K3DM_AGENT_LEDGER_DIR="$2" "$3"' \
    _ "$K3DM_AGY_REAL" "$K3DM_AGENT_LEDGER_DIR" "$ROOT/bin/k3dm-agy"
  [ "$status" -eq 0 ]
  [[ "$output" == *'got:[hello]'* ]]
}

@test "agy wrapper: interactive child receives default SIGINT disposition" {
  cat >"$K3DM_AGY_REAL" <<'SH'
#!/usr/bin/env bash
exec python3 -c 'import signal; print(signal.getsignal(signal.SIGINT) == signal.SIG_IGN)'
SH
  chmod +x "$K3DM_AGY_REAL"
  run "${K3DM_AGY_WRAPPER_BIN:-$ROOT/bin/k3dm-agy}"
  [ "$status" -eq 0 ]
  [ "$output" = False ]
}

@test "agy wrapper: records child SIGINT exit status" {
  cat >"$K3DM_AGY_REAL" <<'SH'
#!/usr/bin/env bash
kill -INT "$$"
SH
  chmod +x "$K3DM_AGY_REAL"
  run "$ROOT/bin/k3dm-agy"
  [ "$status" -eq 130 ]
  run python3 - "$K3DM_AGENT_LEDGER_DIR/agy.jsonl" <<'PY'
import json,sys
assert json.loads(open(sys.argv[1]).read())['exit']==130
PY
  [ "$status" -eq 0 ]
}

@test "agy wrapper: help as a print prompt is still recorded" {
  run "$ROOT/bin/k3dm-agy" --print help --output-format json
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$K3DM_AGENT_LEDGER_DIR/agy.jsonl" | tr -d ' ')" -eq 1 ]
}

@test "agy wrapper: equals form of JSON output format records usage" {
  run "$ROOT/bin/k3dm-agy" --print x --output-format=json
  [ "$status" -eq 0 ]
  run python3 - "$K3DM_AGENT_LEDGER_DIR/agy.jsonl" <<'PY'
import json,sys
assert json.loads(open(sys.argv[1]).read())['usage']=={'input_tokens':12,'output_tokens':3}
PY
  [ "$status" -eq 0 ]
}

@test "agy wrapper install: refuses to replace a real agy binary in the target dir" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho real\n' >"$BATS_TEST_TMPDIR/bin/agy"
  chmod +x "$BATS_TEST_TMPDIR/bin/agy"
  cp "$BATS_TEST_TMPDIR/bin/agy" "$BATS_TEST_TMPDIR/expected"
  run make -s -C "$ROOT" agy-wrapper-install AGY_WRAPPER_DIR="$BATS_TEST_TMPDIR/bin"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not the k3dm-agy wrapper"* ]]
  [ ! -L "$BATS_TEST_TMPDIR/bin/agy" ]
  cmp "$BATS_TEST_TMPDIR/bin/agy" "$BATS_TEST_TMPDIR/expected"
}

@test "agy wrapper install: default dir is not ~/.local/bin and reinstall is idempotent" {
  grep -qxF 'AGY_WRAPPER_DIR ?= $(HOME)/.local/share/k3d-manager/bin' "$ROOT/Makefile"
  run make -s -C "$ROOT" agy-wrapper-install AGY_WRAPPER_DIR="$BATS_TEST_TMPDIR/wbin"
  [ "$status" -eq 0 ]
  run make -s -C "$ROOT" agy-wrapper-install AGY_WRAPPER_DIR="$BATS_TEST_TMPDIR/wbin"
  [ "$status" -eq 0 ]
  [ -L "$BATS_TEST_TMPDIR/wbin/agy" ]
}
