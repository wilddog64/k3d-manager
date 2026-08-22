#!/usr/bin/env bash
set -euo pipefail

# M2 remote E2E runner — bootstrap and preflight (v1.27.0 plan #2, increment 3).
#
# The M4 stays the hub, public edge, and observability source of truth. The M2
# (reached only through the configured SSH host, never a hard-coded LAN IP) runs
# one bounded vCluster/Playwright E2E at a time on its own dedicated k3d cluster.
# This module owns:
#   - e2e_runner_preflight : capacity/lock/docker gate, structured status only
#   - e2e_runner_bootstrap : start OrbStack if stopped, reconcile the dedicated
#                            runner cluster, verify the foundation vCluster CLI
#   - e2e_runner_status    : read-only health, never mutates the runner
#
# The gate evaluation (_e2e_remote_eval_gates) is intentionally a pure function
# so it is unit-testable without a live host, matching the repo's BATS rule.

E2E_M2_SSH_HOST="${E2E_M2_SSH_HOST:-m2jump}"
E2E_M2_RUNNER_CLUSTER="${E2E_M2_RUNNER_CLUSTER:-e2e-runner}"
E2E_M2_RUNNER_CONTEXT="${E2E_M2_RUNNER_CONTEXT:-k3d-${E2E_M2_RUNNER_CLUSTER}}"
E2E_M2_KUBECONFIG="${E2E_M2_KUBECONFIG:-\$HOME/.kube/e2e-runner.yaml}"
E2E_M2_LOCK="${E2E_M2_LOCK:-\$HOME/.k3dm/e2e/runner.lock}"
E2E_M2_REMOTE_REPORT_DIR="${E2E_M2_REMOTE_REPORT_DIR:-\$HOME/.k3dm/e2e}"
E2E_M2_ORB_TIMEOUT="${E2E_M2_ORB_TIMEOUT:-120}"
E2E_M2_ORB_INTERVAL="${E2E_M2_ORB_INTERVAL:-5}"
E2E_M2_SSH_CONNECT_TIMEOUT="${E2E_M2_SSH_CONNECT_TIMEOUT:-8}"
# Non-interactive SSH does not load the login PATH, and on the M2 k3d/vcluster
# live in /opt/homebrew/bin while orb/docker/kubectl live in /usr/local/bin —
# neither is guaranteed on a BatchMode shell. Prepend both so remote commands
# resolve their tools instead of failing with exit 127.
E2E_M2_REMOTE_PATH="${E2E_M2_REMOTE_PATH:-/opt/homebrew/bin:/usr/local/bin}"
E2E_M2_MIN_CPU_IDLE="${E2E_M2_MIN_CPU_IDLE:-35}"
E2E_M2_MIN_MEM_FREE="${E2E_M2_MIN_MEM_FREE:-25}"
E2E_M2_MIN_DISK_GB="${E2E_M2_MIN_DISK_GB:-40}"
# The k3d-manager checkout on the M2 that owns the remote E2E entry point.
E2E_M2_REPO="${E2E_M2_REPO:-\$HOME/src/gitrepo/personal/k3d-manager}"
# Runners a dispatch may target. RUNNER is matched against this exact list and
# then used verbatim as the run's provenance — never free-text from the caller.
E2E_RUNNER_ALLOWLIST="${E2E_RUNNER_ALLOWLIST:-m2}"

export E2E_M2_SSH_HOST E2E_M2_RUNNER_CLUSTER E2E_M2_RUNNER_CONTEXT
export E2E_M2_KUBECONFIG E2E_M2_LOCK E2E_M2_REMOTE_REPORT_DIR
export E2E_M2_ORB_TIMEOUT E2E_M2_ORB_INTERVAL E2E_M2_SSH_CONNECT_TIMEOUT
export E2E_M2_MIN_CPU_IDLE E2E_M2_MIN_MEM_FREE E2E_M2_MIN_DISK_GB
export E2E_M2_REMOTE_PATH E2E_M2_REPO E2E_RUNNER_ALLOWLIST

# Safe, non-interactive SSH options. BatchMode fails fast instead of prompting;
# host identity is verified through the existing known_hosts — we never weaken it
# with StrictHostKeyChecking=no (see the plan's security boundaries).
function _e2e_remote_ssh_opts() {
  printf '%s\n' \
    -o BatchMode=yes \
    -o "ConnectTimeout=${E2E_M2_SSH_CONNECT_TIMEOUT}" \
    -o LogLevel=ERROR
}

# Run one bounded command on the M2. The remote command string is passed to a
# non-login shell; callers build it from module constants only, never from
# untrusted input.
function _e2e_remote_ssh() {
  local -a opts
  mapfile -t opts < <(_e2e_remote_ssh_opts)
  local cmd="export PATH=\"${E2E_M2_REMOTE_PATH}:\$PATH\"; $*"
  _run_command --soft --quiet -- ssh "${opts[@]}" -- "${E2E_M2_SSH_HOST}" "$cmd"
}

# Extract one key=value from probe output (last wins).
function _e2e_kv() {
  local blob="$1" key="$2" line val=""
  while IFS= read -r line; do
    case "$line" in
      "${key}="*) val="${line#*=}" ;;
    esac
  done <<<"$blob"
  printf '%s' "$val"
}

# Numeric "a < b" that tolerates decimals (percentages). Empty/non-numeric a
# is treated as 0 (fails the floor), which correctly routes to a capacity stop.
function _e2e_num_lt() {
  awk -v a="${1:-0}" -v b="${2:-0}" 'BEGIN{ exit !((a+0) < (b+0)) }'
}

# Gather raw capacity metrics from the M2 in a single round-trip. Emits
# key=value lines; the CPU sampler drops the first (cumulative-since-boot)
# reading and returns two live samples.
function _e2e_remote_probe() {
  local script
  script="$(cat <<PROBE
set -u
if docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
  echo docker_ok=1
else
  echo docker_ok=0
fi
if [ -f "${E2E_M2_LOCK}" ]; then echo lock=1; else echo lock=0; fi
idx=0
for v in \$(top -l 3 -n 0 -s 1 2>/dev/null | awk '/^CPU usage/{gsub(/%/,"",\$7); print \$7}'); do
  idx=\$((idx+1))
  [ "\$idx" -eq 1 ] && continue
  echo "cpu_idle\${idx}=\${v}"
done
mem=\$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/{gsub(/%/,"",\$2); print \$2}')
echo "mem_free=\${mem:-0}"
disk=\$(df -g "${E2E_M2_REMOTE_REPORT_DIR}" 2>/dev/null | awk 'NR==2{print \$4}')
[ -z "\${disk:-}" ] && disk=\$(df -g "\$HOME" 2>/dev/null | awk 'NR==2{print \$4}')
echo "disk_gb=\${disk:-0}"
PROBE
)"
  _e2e_remote_ssh "bash -s" <<<"$script"
}

# Pure gate evaluator. Input: the probe key=value blob. Output: a status= token
# plus reason= lines. Returns 0 only when the runner is available. This is the
# unit-testable heart of the preflight; it performs no I/O.
function _e2e_remote_eval_gates() {
  local blob="$1"
  local docker_ok lock cpu2 cpu3 mem disk
  docker_ok="$(_e2e_kv "$blob" docker_ok)"
  lock="$(_e2e_kv "$blob" lock)"
  cpu2="$(_e2e_kv "$blob" cpu_idle2)"
  cpu3="$(_e2e_kv "$blob" cpu_idle3)"
  mem="$(_e2e_kv "$blob" mem_free)"
  disk="$(_e2e_kv "$blob" disk_gb)"

  if [[ "$docker_ok" != "1" ]]; then
    printf 'reason=%s\nstatus=docker_down\n' "Docker/OrbStack not responding on ${E2E_M2_SSH_HOST}"
    return 1
  fi
  if [[ "$lock" == "1" ]]; then
    printf 'reason=%s\nstatus=busy\n' "an E2E run already holds the runner lock"
    return 1
  fi
  if _e2e_num_lt "$cpu2" "$E2E_M2_MIN_CPU_IDLE" || _e2e_num_lt "$cpu3" "$E2E_M2_MIN_CPU_IDLE"; then
    printf 'reason=%s\nstatus=capacity_cpu\n' "CPU idle ${cpu2:-?}%/${cpu3:-?}% below floor ${E2E_M2_MIN_CPU_IDLE}%"
    return 1
  fi
  if _e2e_num_lt "$mem" "$E2E_M2_MIN_MEM_FREE"; then
    printf 'reason=%s\nstatus=capacity_mem\n' "memory free ${mem:-?}% below floor ${E2E_M2_MIN_MEM_FREE}%"
    return 1
  fi
  if _e2e_num_lt "$disk" "$E2E_M2_MIN_DISK_GB"; then
    printf 'reason=%s\nstatus=capacity_disk\n' "disk free ${disk:-?}GiB below floor ${E2E_M2_MIN_DISK_GB}GiB"
    return 1
  fi
  printf 'cpu_idle=%s/%s\nmem_free=%s\ndisk_gb=%s\nstatus=available\n' \
    "${cpu2}" "${cpu3}" "${mem}" "${disk}"
  return 0
}

# Public: gate the runner and print a structured result. Never starts a run.
function e2e_runner_preflight() {
  local blob
  if ! blob="$(_e2e_remote_probe)" || [[ -z "$blob" ]]; then
    printf 'reason=%s\nstatus=unreachable\n' "cannot reach runner ${E2E_M2_SSH_HOST} over SSH"
    return 1
  fi
  _e2e_remote_eval_gates "$blob"
}

# Start OrbStack only when stopped, then wait a bounded time for Docker.
function _e2e_remote_start_orbstack() {
  local state
  state="$(_e2e_remote_ssh "orb status 2>/dev/null" || true)"
  if [[ "$state" == *Running* ]]; then
    _info "[e2e-remote] OrbStack already running on ${E2E_M2_SSH_HOST}"
    return 0
  fi
  _info "[e2e-remote] starting OrbStack on ${E2E_M2_SSH_HOST} (state: ${state:-unknown})"
  _e2e_remote_ssh "orb start >/dev/null 2>&1 || true"
  local waited=0
  while (( waited < E2E_M2_ORB_TIMEOUT )); do
    if _e2e_remote_ssh "docker version --format '{{.Server.Version}}' >/dev/null 2>&1"; then
      _info "[e2e-remote] Docker responsive on ${E2E_M2_SSH_HOST} after ${waited}s"
      return 0
    fi
    sleep "$E2E_M2_ORB_INTERVAL"
    waited=$(( waited + E2E_M2_ORB_INTERVAL ))
  done
  _err "[e2e-remote] OrbStack/Docker did not become responsive on ${E2E_M2_SSH_HOST} within ${E2E_M2_ORB_TIMEOUT}s"
}

# Create the dedicated runner cluster if missing. Never touches the hub cluster.
function _e2e_remote_reconcile_cluster() {
  if [[ "$E2E_M2_RUNNER_CLUSTER" == "k3d-cluster" ]]; then
    _err "[e2e-remote] refusing to operate on the hub cluster name 'k3d-cluster'"
  fi
  if _e2e_remote_ssh "k3d cluster list ${E2E_M2_RUNNER_CLUSTER} >/dev/null 2>&1"; then
    _info "[e2e-remote] runner cluster ${E2E_M2_RUNNER_CONTEXT} already present"
    return 0
  fi
  _info "[e2e-remote] creating dedicated runner cluster ${E2E_M2_RUNNER_CONTEXT}"
  _e2e_remote_ssh "mkdir -p \"\$(dirname ${E2E_M2_KUBECONFIG})\" && KUBECONFIG=${E2E_M2_KUBECONFIG} k3d cluster create ${E2E_M2_RUNNER_CLUSTER} --wait --kubeconfig-update-default=false --kubeconfig-switch-context=false"
}

# Verify the exact vCluster CLI through the foundation contract. The runner
# executes E2E on the M2, so the CLI must resolve on the M2 via the k3d-manager
# checkout there; a missing checkout is reported, not silently skipped.
function _e2e_remote_verify_vcluster_cli() {
  local version="${VCLUSTER_VERSION:-}"
  if [[ -z "$version" ]]; then
    _warn "[e2e-remote] VCLUSTER_VERSION unset; skipping remote CLI pin verification"
    return 0
  fi
  if _e2e_remote_ssh "test -x \$HOME/src/gitrepo/personal/k3d-manager/scripts/k3d-manager"; then
    if _e2e_remote_ssh "\$HOME/src/gitrepo/personal/k3d-manager/scripts/k3d-manager vcluster_ensure_cli ${version} >/dev/null 2>&1"; then
      _info "[e2e-remote] vCluster CLI ${version} verified on ${E2E_M2_SSH_HOST} via foundation contract"
      return 0
    fi
    _warn "[e2e-remote] remote vCluster CLI verification for ${version} did not succeed; dispatch will re-verify"
    return 0
  fi
  _warn "[e2e-remote] k3d-manager checkout not found on ${E2E_M2_SSH_HOST}; CLI is verified at dispatch time"
  return 0
}

# Public: bring the runner to a dispatch-ready state, then gate it.
function e2e_runner_bootstrap() {
  if ! _e2e_remote_ssh "true"; then
    printf 'reason=%s\nstatus=unreachable\n' "cannot reach runner ${E2E_M2_SSH_HOST} over SSH"
    return 1
  fi
  _e2e_remote_start_orbstack
  _e2e_remote_reconcile_cluster
  _e2e_remote_verify_vcluster_cli
  _info "[e2e-remote] bootstrap complete; running preflight"
  e2e_runner_preflight
}

# Public: read-only health. Reports reachability + capacity, never mutates.
function e2e_runner_status() {
  if ! _e2e_remote_ssh "true"; then
    printf 'runner=%s\nreachable=0\nstatus=unreachable\n' "${E2E_M2_SSH_HOST}"
    return 1
  fi
  printf 'runner=%s\nreachable=1\n' "${E2E_M2_SSH_HOST}"
  e2e_runner_preflight
}

# --- Remote dispatch (increment 4) -----------------------------------------

# Empty (optional) or a conservative image reference pinned by digest. The value
# is interpolated into the remote command and a kubectl set-image, so anything
# outside [repo@]sha256:<64 hex> is rejected before it can cross SSH.
function _e2e_valid_digest() {
  local d="${1:-}"
  [[ -z "$d" ]] && return 0
  [[ "$d" =~ ^([A-Za-z0-9._/-]+@)?sha256:[0-9a-f]{64}$ ]]
}

function _e2e_runner_allowed() {
  local want="${1:-}" allowed
  for allowed in $E2E_RUNNER_ALLOWLIST; do
    [[ "$want" == "$allowed" ]] && return 0
  done
  return 1
}

# Public: run the existing E2E entry point on a remote runner. Validates the
# runner allowlist and digest, gates on preflight, streams remote output while
# persisting a local transcript, returns the remote exit code unchanged, and
# never falls back to running the workload locally on M4.
function e2e_runner_dispatch() {
  local runner="${1:-}" digest="${2:-}"

  [[ -n "$runner" ]] || _err "usage: e2e_runner_dispatch <runner> [digest]"
  if ! _e2e_runner_allowed "$runner"; then
    _err "[e2e-remote] runner '${runner}' not in allowlist (${E2E_RUNNER_ALLOWLIST})"
  fi
  if ! _e2e_valid_digest "$digest"; then
    _err "[e2e-remote] invalid DIGEST '${digest}' (expected empty or [repo@]sha256:<64 hex>)"
  fi

  local pf status
  if ! pf="$(e2e_runner_preflight)"; then
    printf '%s\n' "$pf"
    status="$(_e2e_kv "$pf" status)"
    _err "[e2e-remote] runner ${runner} not available (status=${status:-unknown}); not dispatching, no local fallback"
  fi
  _info "[e2e-remote] runner ${runner} available; dispatching E2E (digest=${digest:-none})"

  mkdir -p "${E2E_REPORT_DIR}/dispatch"
  local ts transcript
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  transcript="${E2E_REPORT_DIR}/dispatch/${runner}-${ts}.log"

  local -a opts
  mapfile -t opts < <(_e2e_remote_ssh_opts)
  local remote
  remote="export PATH=\"${E2E_M2_REMOTE_PATH}:\$PATH\"; \
export E2E_RUNNER=${runner} KUBECONFIG=${E2E_M2_KUBECONFIG} E2E_REPORT_DIR=${E2E_M2_REMOTE_REPORT_DIR}; \
cd ${E2E_M2_REPO} && ./scripts/k3d-manager e2e_verify_vcluster ${digest}"

  ssh "${opts[@]}" -- "${E2E_M2_SSH_HOST}" "$remote" 2>&1 | tee "$transcript"
  local rc="${PIPESTATUS[0]}"
  _info "[e2e-remote] dispatch exit ${rc}; transcript: ${transcript}"
  return "$rc"
}
