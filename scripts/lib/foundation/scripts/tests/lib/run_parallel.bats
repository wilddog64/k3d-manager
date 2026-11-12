#!/usr/bin/env bats
# shellcheck disable=SC1091

setup() {
  # shellcheck source=/dev/null
  source "${RP_SYSTEM_LIB:-${BATS_TEST_DIRNAME}/../../lib/system.sh}"
  export RP_ROOT="$BATS_TEST_TMPDIR" RP_JOB="$BATS_TEST_TMPDIR/job" RP_LOG="$BATS_TEST_TMPDIR/argv"
  cat >"$RP_JOB" <<'EOF'
#!/usr/bin/env bash
case "$0" in "$BATS_TEST_TMPDIR"/*) ;; *) exit 91 ;; esac
item="$1"
printf '<%s>\n' "$item" >>"$RP_LOG"
if [[ "$item" == fail* ]]; then exit 7; fi
if [[ "$item" == flaky ]]; then
  marker="$RP_ROOT/flaky.marker"
  if [[ ! -e "$marker" ]]; then touch "$marker"; exit 9; fi
fi
if [[ "$item" == sleep:* ]]; then
  python3 - "$RP_ROOT/events" "$item" start <<'PY'
import sys,time
with open(sys.argv[1], 'a') as f: f.write('%.6f %s %s\n' % (time.time(), sys.argv[2], sys.argv[3]))
PY
  sleep 0.25
  python3 - "$RP_ROOT/events" "$item" end <<'PY'
import sys,time
with open(sys.argv[1], 'a') as f: f.write('%.6f %s %s\n' % (time.time(), sys.argv[2], sys.argv[3]))
PY
fi
EOF
  chmod +x "$RP_JOB"
}

assert_max_overlap() {
  python3 - "$1" "$2" <<'PY'
import sys
events=[]
for line in open(sys.argv[1]):
    stamp, item, kind=line.split()
    events.append((float(stamp), 1 if kind == 'start' else -1))
active=peak=0
for _, delta in sorted(events):
    active += delta
    peak=max(peak, active)
assert peak == int(sys.argv[2]), (peak, sys.argv[2])
PY
}

@test "bounds concurrency and records each result; sanitized collisions keep separate files" {
  printf 'sleep:a\0sleep:b\0sleep:c\0sleep:d\0a b\0a_b\0' | _run_parallel --jobs 2 --out "$RP_ROOT/out" -- "$RP_JOB"
  assert_max_overlap "$RP_ROOT/events" 2
  for key in sleep_a sleep_b sleep_c sleep_d a_b a_b-2; do
    [ -f "$RP_ROOT/out/$key.log" ] && [ -f "$RP_ROOT/out/$key.rc" ] && [ -f "$RP_ROOT/out/$key.sec" ]
  done
  [ "$(cat "$RP_ROOT/out/a_b.rc")" -eq 0 ]
  [ "$(cat "$RP_ROOT/out/a_b-2.rc")" -eq 0 ]
}

@test "orders unknown items first and known items longest first; times file is reusable" {
  printf 'known-short\0unknown-b\0known-long\0unknown-a\0' >"$RP_ROOT/items"
  printf '2 known-short\n8 known-long\n' >"$RP_ROOT/order"
  run bash -c 'source "$1"; _run_parallel --jobs 1 --out "$2/out" --order-by "$2/order" -- "$3" <"$2/items"' _ "${RP_SYSTEM_LIB:-${BATS_TEST_DIRNAME}/../../lib/system.sh}" "$RP_ROOT" "$RP_JOB"
  [ "$status" -eq 0 ]
  [ "$(cat "$RP_LOG")" = $'<unknown-b>\n<unknown-a>\n<known-long>\n<known-short>' ]
  cp "$RP_ROOT/out/times.txt" "$RP_ROOT/order2"
  : >"$RP_LOG"
  run bash -c 'source "$1"; _run_parallel --jobs 1 --out "$2/out2" --order-by "$2/order2" -- "$3" <"$2/items"' _ "${RP_SYSTEM_LIB:-${BATS_TEST_DIRNAME}/../../lib/system.sh}" "$RP_ROOT" "$RP_JOB"
  [ "$status" -eq 0 ]
  [ -n "$(head -n 1 "$RP_LOG")" ]
}

@test "retry reports flaky by item and honors flaky-ok" {
  printf 'flaky\0' | _run_parallel --jobs 1 --retry-failed --out "$RP_ROOT/out" -- "$RP_JOB" >"$RP_ROOT/summary" && status=0 || status=$?
  [ "$status" -eq 1 ]
  grep -F 'FLAKY flaky ' "$RP_ROOT/summary"
  [ -f "$RP_ROOT/out/flaky.try1.log" ]
  rm -f "$RP_ROOT/flaky.marker"
  printf 'flaky\0' | _run_parallel --jobs 1 --retry-failed --flaky-ok --out "$RP_ROOT/out2" -- "$RP_JOB" >"$RP_ROOT/summary2"
  grep -F 'FLAKY flaky ' "$RP_ROOT/summary2"
}

@test "summary has sorted result lines followed by slowest and total" {
  printf 'zeta\0alpha\0fail-item\0' | _run_parallel --jobs 2 --out "$RP_ROOT/out" -- "$RP_JOB" >"$RP_ROOT/summary" && status=0 || status=$?
  [ "$status" -eq 1 ]
  [ "$(sed -n '1p' "$RP_ROOT/summary" | cut -d' ' -f1-2)" = 'PASS alpha' ]
  [ "$(sed -n '2p' "$RP_ROOT/summary" | cut -d' ' -f1-2)" = 'FAIL fail-item' ]
  [ "$(sed -n '3p' "$RP_ROOT/summary" | cut -d' ' -f1-2)" = 'PASS zeta' ]
  grep -Eq '^FAIL fail-item 0s \(rc 7\)$' "$RP_ROOT/summary"
  grep -Eq '^SLOWEST .+ [0-9]+s$' "$RP_ROOT/summary"
  grep -Eq '^TOTAL [0-9]+s$' "$RP_ROOT/summary"
}

@test "default jobs use sysctl value and fall back to getconf" {
  mkdir "$RP_ROOT/bin"
  cat >"$RP_ROOT/bin/sysctl" <<'EOF'
#!/bin/sh
echo 3
EOF
  cat >"$RP_ROOT/bin/getconf" <<'EOF'
#!/bin/sh
echo 1
EOF
  chmod +x "$RP_ROOT/bin/"*
  PATH="$RP_ROOT/bin:$PATH"; export PATH
  printf 'sleep:a\0sleep:b\0sleep:c\0sleep:d\0sleep:e\0sleep:f\0' | _run_parallel --out "$RP_ROOT/out" -- "$RP_JOB" >/dev/null
  assert_max_overlap "$RP_ROOT/events" 3
  rm -f "$RP_ROOT/events"
  cat >"$RP_ROOT/bin/sysctl" <<'EOF'
#!/bin/sh
exit 1
EOF
  cat >"$RP_ROOT/bin/getconf" <<'EOF'
#!/bin/sh
echo 2
EOF
  chmod +x "$RP_ROOT/bin/"*
  printf 'sleep:g\0sleep:h\0sleep:i\0sleep:j\0' | _run_parallel --out "$RP_ROOT/out2" -- "$RP_JOB" >/dev/null
  assert_max_overlap "$RP_ROOT/events" 2
}

@test "items with shell syntax arrive as single literal arguments" {
  items=( 'two words' "single'quote" 'double"quote' '$(touch never)' 'semi;colon' '-leading' )
  for item in "${items[@]}"; do printf '%s\0' "$item"; done | _run_parallel --jobs 2 --out "$RP_ROOT/out" -- "$RP_JOB"
  for item in "${items[@]}"; do grep -Fqx "<$item>" "$RP_LOG"; done
}

@test "without retry every item runs exactly once; failures remain nonzero at all job counts" {
  printf 'flaky\0' | _run_parallel --jobs 1 --out "$RP_ROOT/once" -- "$RP_JOB" >/dev/null && return 1 || :
  [ "$(grep -Fc '<flaky>' "$RP_LOG")" -eq 1 ]
  for jobs in 1 4; do
    for order in none file; do
      args=(--jobs "$jobs" --out "$RP_ROOT/n1-$jobs-$order")
      if [[ "$order" == file ]]; then printf '1 fail-item\n' >"$RP_ROOT/order"; args+=(--order-by "$RP_ROOT/order"); fi
      if printf 'fail-item\0ok\0' | _run_parallel "${args[@]}" -- "$RP_JOB" >/dev/null; then return 1; fi
    done
  done
}

@test "set -e caller continues after failed execution and bad usage" {
  printf 'fail-item\0' >"$RP_ROOT/items"
  run bash -c 'source "$1"; set -e; _run_parallel --jobs 1 --out "$2/out" -- "$3" <"$2/items" || rc=$?; [ "$rc" -eq 1 ]; echo after-failure; rc=0; _run_parallel --jobs 0 --out "$2/out" -- "$3" || rc=$?; [ "$rc" -eq 2 ]; echo after-usage' _ "${RP_SYSTEM_LIB:-${BATS_TEST_DIRNAME}/../../lib/system.sh}" "$RP_ROOT" "$RP_JOB"
  [ "$status" -eq 0 ]
  [[ "$output" == *after-failure*after-usage* ]]
}

@test "works with GNU xargs when installed" {
  if ! command -v gxargs >/dev/null 2>&1; then skip "gxargs is not installed"; fi
  mkdir "$RP_ROOT/gnu-bin"
  ln -s "$(command -v gxargs)" "$RP_ROOT/gnu-bin/xargs"
  PATH="$RP_ROOT/gnu-bin:$PATH"; export PATH
  printf 'one\0two\0' | _run_parallel --jobs 2 --out "$RP_ROOT/out" -- "$RP_JOB"
  [ "$(wc -l <"$RP_LOG" | tr -d ' ')" -eq 2 ]
}

@test "a final item without a trailing NUL still runs" {
  [[ "$RP_JOB" == "$BATS_TEST_TMPDIR/"* ]]
  run bash -c 'source "$1"; printf "one\0fail-last" | _run_parallel --jobs 1 --out "$2/out" -- "$3"' _ "${BATS_TEST_DIRNAME}/../../lib/system.sh" "$BATS_TEST_TMPDIR" "$RP_JOB"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL fail-last"* ]]
}
