#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  RUN_LOG="$BATS_TEST_TMPDIR/run.log"
  : > "$RUN_LOG"
}

@test "--prefer-sudo uses sudo when available" {
  sudo() { echo "sudo $*" >> "$RUN_LOG"; shift; "$@"; }
  export -f sudo
  run _run_command --prefer-sudo -- echo hi
  [ "$status" -eq 0 ]
  [[ "$output" = "hi" ]]
  read_lines "$RUN_LOG" log
  [ "${log[1]}" = "sudo -n echo hi" ]
}

@test "--prefer-sudo falls back when sudo unavailable" {
  sudo() { echo "sudo $*" >> "$RUN_LOG"; return 1; }
  export -f sudo
  run _run_command --prefer-sudo -- echo hi
  [ "$status" -eq 0 ]
  [[ "$output" = "hi" ]]
  ! grep -q 'sudo -n echo hi' "$RUN_LOG"
}

@test "--require-sudo fails when sudo unavailable" {
  sudo() { return 1; }
  export -f sudo
  run -127 _run_command --require-sudo -- echo hi
  [[ "$output" == *"sudo non-interactive not available"* ]]
}

@test "--probe supports multi-word subcommands" {
  fakecmd() {
    if [[ "$1" == version && "$2" == --short ]]; then
      return 0
    elif [[ "$1" == run ]]; then
      return 0
    else
      return 1
    fi
  }
  sudo() { echo "sudo $*" >> "$RUN_LOG"; return 0; }
  export -f fakecmd sudo
  run _run_command --probe 'version --short' -- fakecmd run
  [ "$status" -eq 0 ]
  ! grep -q 'sudo -n fakecmd run' "$RUN_LOG"
}

@test "--probe escalates to sudo when user probe fails" {
  fakecmd() {
    [[ "$1" == probe ]] && return 1
    return 0
  }
  sudo() { echo "sudo $*" >> "$RUN_LOG"; shift; return 0; }
  export -f fakecmd sudo
  run _run_command --probe 'probe' -- fakecmd run
  [ "$status" -eq 0 ]
  grep -q 'sudo -n fakecmd run' "$RUN_LOG"
}
