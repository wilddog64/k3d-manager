#!/usr/bin/env bats

setup() {
  export K3DM_NODE_RECOVERY_LOG="$BATS_TEST_TMPDIR/node-health-watch.log"
  export K3DM_NODE_RECOVERY_STATE="$BATS_TEST_TMPDIR/node-health-watch.state"
  export K3DM_NODE_RECOVERY_ENABLED=1
  export K3DM_NODE_RECOVERY_FAILURE_THRESHOLD=2
  export K3DM_NODE_RECOVERY_COOLDOWN=0
  unset K3DM_NODE_TUNNEL_THRESHOLD
  export K3DM_NODE_RECOVERY_NODE=agent-x
  export K3DM_NODE_RECOVERY_CONTEXT=ctx-x
  export READY_FILE="$BATS_TEST_TMPDIR/ready"
  export READYZ_FILE="$BATS_TEST_TMPDIR/readyz"
  export HEALTHZ_FILE="$BATS_TEST_TMPDIR/healthz"
  export CONTAINER_STATE_FILE="$BATS_TEST_TMPDIR/container-state"
  export DOCKER_CALLS="$BATS_TEST_TMPDIR/docker-calls"
  export DRIFT_CALLS="$BATS_TEST_TMPDIR/drift-calls"
  export K3DM_HOSTNET_DRIFT_BIN="$BATS_TEST_TMPDIR/hostnet-drift"
  printf 'True\n' >"$READY_FILE"
  printf 'ok\n' >"$READYZ_FILE"
  printf 'ok\n' >"$HEALTHZ_FILE"
  printf 'running\n' >"$CONTAINER_STATE_FILE"
  : >"$DOCKER_CALLS"
  : >"$DRIFT_CALLS"
  cat >"$K3DM_HOSTNET_DRIFT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DRIFT_CALLS"
STUB
  chmod +x "$K3DM_HOSTNET_DRIFT_BIN"

  kubectl() {
    case "$*" in
      *"get --raw /readyz"*) [[ -s "$READYZ_FILE" ]] || return 1; cat "$READYZ_FILE" ;;
      *"get node"*) cat "$READY_FILE" ;;
      *"/proxy/healthz"*)
        case "$(<"$HEALTHZ_FILE")" in
          ok) echo ok ;;
          tunnel) echo 'Error from server: error dialing backend: proxy error from 127.0.0.1:6443 while dialing 192.168.97.4:10250, code 502: 502 Bad Gateway' >&2; return 1 ;;
          *) echo 'Unable to connect to the server: context deadline exceeded' >&2; return 1 ;;
        esac
        ;;
    esac
  }

  docker() {
    case "$1" in
      inspect) cat "$CONTAINER_STATE_FILE" ;;
      restart|start) printf '%s %s\n' "$1" "$2" >>"$DOCKER_CALLS"; printf 'True\n' >"$READY_FILE"; printf 'ok\n' >"$HEALTHZ_FILE" ;;
    esac
  }

  sleep() { :; }

  source "${BATS_TEST_DIRNAME}/../../../bin/k3dm-node-health-watch"
}

@test "node health watchdog: Ready node with dead kubelet tunnel restarts after 6 ticks" {
  printf 'tunnel\n' >"$HEALTHZ_FILE"
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  [ "$(<"$DOCKER_CALLS")" = "restart agent-x" ]
  grep -q 'kubelet tunnel dead (6/6)' "$K3DM_NODE_RECOVERY_LOG"
  [ "$tunnel_failures" -eq 0 ]
}

@test "node health watchdog: tunnel streak broken by ok does not restart" {
  printf 'tunnel\n' >"$HEALTHZ_FILE"
  _tick
  _tick
  _tick
  _tick
  _tick
  printf 'ok\n' >"$HEALTHZ_FILE"
  _tick
  printf 'tunnel\n' >"$HEALTHZ_FILE"
  _tick
  _tick
  _tick
  _tick
  _tick
  [ ! -s "$DOCKER_CALLS" ]
}

@test "node health watchdog: slow healthz on a Ready node never restarts (2026-08-28 guard)" {
  printf 'slow\n' >"$HEALTHZ_FILE"
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  [ ! -s "$DOCKER_CALLS" ]
  [ "$tunnel_failures" -eq 0 ]
}

@test "node health watchdog: tunnel failure during cooldown does not restart again" {
  export K3DM_NODE_RECOVERY_COOLDOWN=3600
  printf '%s\n' "$(date +%s)" >"$K3DM_NODE_RECOVERY_STATE"
  source "${BATS_TEST_DIRNAME}/../../../bin/k3dm-node-health-watch"
  printf 'tunnel\n' >"$HEALTHZ_FILE"
  _tick
  _tick
  _tick
  _tick
  _tick
  _tick
  [ ! -s "$DOCKER_CALLS" ]
  grep -q 'recovery cooldown active' "$K3DM_NODE_RECOVERY_LOG"
}

@test "node health watchdog: Ready node resets failures and never restarts" {
  _tick
  _tick
  _tick
  [ "$failures" -eq 0 ]
  [ ! -s "$DOCKER_CALLS" ]
  [ ! -s "$DRIFT_CALLS" ]
}

@test "node health watchdog: NotReady with reachable API restarts after threshold" {
  printf 'False\n' >"$READY_FILE"
  _tick
  _tick
  [ "$(<"$DOCKER_CALLS")" = "restart agent-x" ]
  grep -q 'NotReady (2/2)' "$K3DM_NODE_RECOVERY_LOG"
  [ "$(<"$DRIFT_CALLS")" = "--context ctx-x --fix" ]
}

@test "node health watchdog: advisory Ready path never runs host-network drift fix" {
  _tick
  [ ! -s "$DRIFT_CALLS" ]
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
