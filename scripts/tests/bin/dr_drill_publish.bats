#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export STUB_BIN="$BATS_TEST_TMPDIR/bin" HOME="$BATS_TEST_TMPDIR/home"
  export LOG="$BATS_TEST_TMPDIR/calls.log" SSH_MODE=good
  mkdir -p "$STUB_BIN" "$HOME"
  : > "$LOG"
  cat > "$STUB_BIN/ssh" <<'STUB'
#!/usr/bin/env bash
printf 'ssh %s\n' "$*" >> "$LOG"
if [[ "$SSH_MODE" == malicious ]]; then
  printf '%s\n' "x'; touch pwned; '.json"
elif [[ "${@: -1}" == find\ * ]]; then
  printf '%s\n' '~/.k3dm/dr-drill/20261009T120000Z.json'
else
  printf '%s\n' '{"run_timestamp":"20261009T120000Z","export":"20261009T110000Z","success":true,"rto_seconds":42,"rpo_seconds":3600,"checks":{"V0":true,"V1":true,"V2":true,"V3":true,"V4":true,"V5":true,"V6":true,"V7":true}}'
fi
STUB
  cat > "$STUB_BIN/git" <<'STUB'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$LOG"
if [[ "${1:-}" == clone ]]; then mkdir -p "${@: -1}/results"; fi
if [[ "${1:-}" == push && "${GIT_PUSH_FAIL:-0}" == 1 ]]; then exit 1; fi
exit 0
STUB
  cat > "$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$LOG"
for arg in "$@"; do [[ "$arg" == @* ]] && cat "${arg#@}" >> "$LOG"; done
[[ "${CURL_FAIL:-0}" == 1 ]] && exit 1
exit 0
STUB
  chmod +x "$STUB_BIN"/*
  export PATH="$STUB_BIN:$PATH" K3DM_HUB_DATA_REPO=stub-repo K3DM_DR_DRILL_HOST=m2jump
}

@test "dr drill publish: reads M2, commits results, then pushes all metrics" {
  run bin/dr-drill-publish
  [ "$status" -eq 0 ]
  grep -q 'git clone.*--branch results' "$LOG"
  grep -q 'git.*results/20261009T120000Z.json' "$LOG"
  grep -q 'git push origin results' "$LOG"
  grep -q 'http://localhost:19094/metrics/job/k3dm-dr-drill' "$LOG"
  [ "$(grep -n 'git push origin results' "$LOG" | cut -d: -f1)" -lt "$(grep -n '^curl ' "$LOG" | cut -d: -f1)" ]
  expected="$(python3 -c 'import datetime; print(int(datetime.datetime.strptime("20261009T120000Z", "%Y%m%dT%H%M%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()))')"
  grep -q "k3dm_dr_drill_last_run_timestamp_seconds $expected" "$LOG"
  for check in V0 V1 V2 V3 V4 V5 V6 V7; do grep -q "check=\\\"$check\\\"" "$LOG"; done
}

@test "dr drill publish: duplicate result refuses before push and curl" {
  cat > "$STUB_BIN/git" <<'STUB'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$LOG"
if [[ "${1:-}" == clone ]]; then dest="${@: -1}"; mkdir -p "$dest/results"; printf x > "$dest/results/20261009T120000Z.json"; fi
STUB
  chmod +x "$STUB_BIN/git"
  run bin/dr-drill-publish
  [ "$status" -ne 0 ]
  [ "$(grep -c '^git push' "$LOG" || true)" -eq 0 ]
  [ "$(grep -c '^curl ' "$LOG" || true)" -eq 0 ]
}

@test "dr drill publish: invalid schema refuses before git" {
  cat > "$STUB_BIN/ssh" <<'STUB'
#!/usr/bin/env bash
if [[ "${@: -1}" == find\ * ]]; then printf '%s\n' '~/.k3dm/dr-drill/20261009T120000Z.json'; else printf '%s\n' '{"run_timestamp":"20261009T120000Z","success":"true","rto_seconds":1,"rpo_seconds":1,"checks":{}}'; fi
STUB
  chmod +x "$STUB_BIN/ssh"
  run bin/dr-drill-publish
  [ "$status" -ne 0 ]
  [ "$(grep -c '^git ' "$LOG" || true)" -eq 0 ]
}

@test "dr drill publish: unexpected M2 filename is refused before second ssh" {
  export SSH_MODE=malicious
  run bin/dr-drill-publish
  [ "$status" -ne 0 ]
  [ "$(grep -c '^ssh ' "$LOG" || true)" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}

@test "dr drill publish: Pushgateway failure is reported after git push" {
  export CURL_FAIL=1
  run bin/dr-drill-publish
  [ "$status" -ne 0 ]
  [[ "$output" == *"metrics push failed"* ]]
  grep -q 'git push origin results' "$LOG"
}
