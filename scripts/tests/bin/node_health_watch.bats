#!/usr/bin/env bats

setup() {
  export K3DM_NODE_RECOVERY_LOG="$BATS_TEST_TMPDIR/node-health-watch.log"
  export K3DM_NODE_RECOVERY_STATE="$BATS_TEST_TMPDIR/node-health-watch.state"
  export K3DM_NODE_RECOVERY_ENABLED=1
  export K3DM_NODE_RECOVERY_FAILURE_THRESHOLD=2
  export K3DM_NODE_RECOVERY_COOLDOWN=0
  export K3DM_NODE_RECOVERY_NODE=agent-x
  export K3DM_NODE_RECOVERY_CONTEXT=ctx-x
  export READY_FILE="$BATS_TEST_TMPDIR/ready"
  export READYZ_FILE="$BATS_TEST_TMPDIR/readyz"
  export CONTAINER_STATE_FILE="$BATS_TEST_TMPDIR/container-state"
  export DOCKER_CALLS="$BATS_TEST_TMPDIR/docker-calls"
  printf 'True\n' >"$READY_FILE"
  printf 'ok\n' >"$READYZ_FILE"
  printf 'running\n' >"$CONTAINER_STATE_FILE"
  : >"$DOCKER_CALLS"

  kubectl() {
    case "$*" in
      *"get --raw /readyz"*) [[ -s "$READYZ_FILE" ]] || return 1; cat "$READYZ_FILE" ;;
      *"get node"*) cat "$READY_FILE" ;;
      *"/proxy/healthz"*) echo ok ;;
    esac
  }

  docker() {
    case "$1" in
      inspect) cat "$CONTAINER_STATE_FILE" ;;
      restart|start) printf '%s %s\n' "$1" "$2" >>"$DOCKER_CALLS"; printf 'True\n' >"$READY_FILE" ;;
    esac
  }

  sleep() { :; }

  source "${BATS_TEST_DIRNAME}/../../../bin/k3dm-node-health-watch"
}

@test "node health watchdog: Ready node resets failures and never restarts" {
  _tick
  _tick
  _tick
  [ "$failures" -eq 0 ]
  [ ! -s "$DOCKER_CALLS" ]
}

@test "node health watchdog: NotReady with reachable API restarts after threshold" {
  printf 'False\n' >"$READY_FILE"
  _tick
  _tick
  [ "$(<"$DOCKER_CALLS")" = "restart agent-x" ]
  grep -q 'NotReady (2/2)' "$K3DM_NODE_RECOVERY_LOG"
}

@test "node health watchdog: unreachable API never restarts the agent" {
  printf 'False\n' >"$READY_FILE"
  : >"$READYZ_FILE"
  _tick
  _tick
  _tick
  _tick
  _tick
  [ ! -s "$DOCKER_CALLS" ]
  [ "$failures" -eq 0 ]
  grep -q 'API server unreachable from host via ctx-x' "$K3DM_NODE_RECOVERY_LOG"
}

@test "node health watchdog: an unreachable API interval resets the NotReady streak" {
  printf 'False\n' >"$READY_FILE"
  _tick
  : >"$READYZ_FILE"
  _tick
  printf 'ok\n' >"$READYZ_FILE"
  _tick
  [ ! -s "$DOCKER_CALLS" ]
  [ "$failures" -eq 1 ]
}

@test "node health watchdog: starts an exited agent instead of restarting it" {
  printf 'exited\n' >"$CONTAINER_STATE_FILE"
  printf 'False\n' >"$READY_FILE"
  _tick
  _tick
  [ "$(<"$DOCKER_CALLS")" = "start agent-x" ]
}

@test "node health watchdog: sourcing does not enter the loop and keeps bounded defaults" {
  local script="${BATS_TEST_DIRNAME}/../../../bin/k3dm-node-health-watch"
  local -a command=(env -u K3DM_NODE_RECOVERY_FAILURE_THRESHOLD -u K3DM_NODE_RECOVERY_COOLDOWN -u K3DM_NODE_RECOVERY_INTERVAL HOME="$BATS_TEST_TMPDIR" bash -c 'source "$1"; printf "%s %s\\n" "$threshold" "$cooldown"' bash "$script")
  if command -v timeout >/dev/null 2>&1; then
    command=(timeout 10 "${command[@]}")
  fi
  run "${command[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "5 300" ]
}
