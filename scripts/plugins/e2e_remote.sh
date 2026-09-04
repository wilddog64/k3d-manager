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
# This plugin can be lazy-loaded on its own (dispatcher sources only the file
# holding the invoked function), so it must not depend on e2e.sh for the report
# directory default. Keep this in sync with e2e.sh.
E2E_REPORT_DIR="${E2E_REPORT_DIR:-${HOME}/.k3dm/e2e}"
E2E_RESULT_EVENT_NAMESPACE="${E2E_RESULT_EVENT_NAMESPACE:-platform-ops}"
E2E_RESULT_EVENT_KEEP="${E2E_RESULT_EVENT_KEEP:-20}"
# Result-publisher (increment 5): the M4 hub is assigned internally, never taken
# from the M2's payload; KUBECONFIG is pinned so an inherited one cannot redirect
# the write to another cluster.
E2E_HUB_CONTEXT="${E2E_HUB_CONTEXT:-k3d-k3d-cluster}"
E2E_PUBLISH_KUBECONFIG="${E2E_PUBLISH_KUBECONFIG:-${HOME}/.kube/config}"
E2E_PUBLISH_MAX_BYTES="${E2E_PUBLISH_MAX_BYTES:-65536}"
E2E_PUBLISH_AUDIT_LOG="${E2E_PUBLISH_AUDIT_LOG:-${E2E_REPORT_DIR}/publish-audit.log}"
# Failure/operations (increment 6). The runner lock is a directory (mkdir is
# atomic) holding an owner/timestamp marker; a stale lock is cleared only by the
# explicit guarded unlock, never automatically, and only past this age with no
# live run. Publish-back is the M2->M4 result hop over the dedicated key; when no
# M4 target is configured the M2 retains the result as publication_pending for a
# later bounded replay.
E2E_M2_LOCK_MAX_AGE="${E2E_M2_LOCK_MAX_AGE:-7200}"
E2E_M2_PUBLISH_BACK_HOST="${E2E_M2_PUBLISH_BACK_HOST:-}"
E2E_M2_PUBLISH_BACK_KEY="${E2E_M2_PUBLISH_BACK_KEY:-\$HOME/.ssh/e2e-m4-publisher}"
# Read by e2e_runner_publish_back when it runs ON the M2 (injected by dispatch
# from the M4-side values above). Empty host => retain as publication_pending.
E2E_PUBLISH_BACK_HOST="${E2E_PUBLISH_BACK_HOST:-}"
E2E_PUBLISH_BACK_KEY="${E2E_PUBLISH_BACK_KEY:-${HOME}/.ssh/e2e-m4-publisher}"

export E2E_M2_SSH_HOST E2E_M2_RUNNER_CLUSTER E2E_M2_RUNNER_CONTEXT
export E2E_M2_KUBECONFIG E2E_M2_LOCK E2E_M2_REMOTE_REPORT_DIR
export E2E_M2_ORB_TIMEOUT E2E_M2_ORB_INTERVAL E2E_M2_SSH_CONNECT_TIMEOUT
export E2E_M2_MIN_CPU_IDLE E2E_M2_MIN_MEM_FREE E2E_M2_MIN_DISK_GB
export E2E_M2_REMOTE_PATH E2E_M2_REPO E2E_RUNNER_ALLOWLIST
export E2E_REPORT_DIR E2E_RESULT_EVENT_NAMESPACE E2E_RESULT_EVENT_KEEP
export E2E_HUB_CONTEXT E2E_PUBLISH_KUBECONFIG E2E_PUBLISH_MAX_BYTES E2E_PUBLISH_AUDIT_LOG
export E2E_M2_LOCK_MAX_AGE E2E_M2_PUBLISH_BACK_HOST E2E_M2_PUBLISH_BACK_KEY
export E2E_PUBLISH_BACK_HOST E2E_PUBLISH_BACK_KEY

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
if [ -e "${E2E_M2_LOCK}" ]; then echo lock=1; else echo lock=0; fi
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

# A dispatch-owned token identifying this M4 process, safe for a grep -qxF match
# (hostname, epoch, pid — no shell metacharacters).
function _e2e_lock_token() {
  printf 'owner=%s pid=%s ts=%s' "$(hostname -s 2>/dev/null || echo m4)" "$$" "$(date -u +%s)"
}

# Atomically claim the runner lock on the M2 (mkdir is atomic; a losing racer
# gets a non-zero return and is treated as busy). Records the owner token so the
# release and the guarded unlock can verify ownership.
function _e2e_remote_lock_acquire() {
  local token="$1"
  _e2e_remote_ssh "mkdir \"${E2E_M2_LOCK}\" 2>/dev/null && printf '%s\n' \"${token}\" > \"${E2E_M2_LOCK}/meta\""
}

# Release the runner lock only when this process owns it — never blind rm.
function _e2e_remote_lock_release() {
  local token="$1"
  _e2e_remote_ssh "if [ -f \"${E2E_M2_LOCK}/meta\" ] && grep -qxF \"${token}\" \"${E2E_M2_LOCK}/meta\"; then rm -rf \"${E2E_M2_LOCK}\"; fi"
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

  local token
  token="$(_e2e_lock_token)"
  if ! _e2e_remote_lock_acquire "$token"; then
    _err "[e2e-remote] runner ${runner} is busy (lock held); not dispatching, no local fallback"
  fi
  # shellcheck disable=SC2064
  trap "_e2e_remote_lock_release '${token}' >/dev/null 2>&1 || true" RETURN

  mkdir -p "${E2E_REPORT_DIR}/dispatch"
  local ts transcript
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  transcript="${E2E_REPORT_DIR}/dispatch/${runner}-${ts}.log"

  # When an M4 publish-back target is configured, hand it to the M2 so the runner
  # can push its own result over the dedicated key; otherwise the M2 retains the
  # result as publication_pending for a later replay.
  local backenv=""
  if [[ -n "$E2E_M2_PUBLISH_BACK_HOST" ]]; then
    backenv="export E2E_PUBLISH_BACK_HOST=${E2E_M2_PUBLISH_BACK_HOST} E2E_PUBLISH_BACK_KEY=${E2E_M2_PUBLISH_BACK_KEY}; "
  fi
  local imageenv=""
  if [[ -n "${E2E_IMAGE_TAG:-}" ]]; then
    local _image_tag_q
    printf -v _image_tag_q '%q' "${E2E_IMAGE_TAG}"
    imageenv="export E2E_IMAGE_TAG=${_image_tag_q}; "
  fi

  local -a opts
  mapfile -t opts < <(_e2e_remote_ssh_opts)
  local remote
  remote="export PATH=\"${E2E_M2_REMOTE_PATH}:\$PATH\"; \
export E2E_RUNNER=${runner} KUBECONFIG=${E2E_M2_KUBECONFIG} E2E_REPORT_DIR=${E2E_M2_REMOTE_REPORT_DIR}; \
${imageenv}${backenv}\
cd ${E2E_M2_REPO} || exit 1; ./scripts/k3d-manager e2e_verify_vcluster ${digest}; rc=\$?; \
./scripts/k3d-manager e2e_runner_publish_back \$rc || true; exit \$rc"

  ssh "${opts[@]}" -- "${E2E_M2_SSH_HOST}" "$remote" 2>&1 | tee "$transcript"
  local rc="${PIPESTATUS[0]}"
  _info "[e2e-remote] dispatch exit ${rc}; transcript: ${transcript}"
  return "$rc"
}

# --- Restricted result publication (increment 5) ---------------------------

# Append one redacted line to the publisher audit trail. Deliberately records
# only run id, runner, result, and outcome — never the payload or a digest.
function _e2e_publish_audit() {
  local outcome="$1" run_id="$2" runner="$3" result="$4"
  mkdir -p "$(dirname "$E2E_PUBLISH_AUDIT_LOG")" 2>/dev/null || true
  printf '%s outcome=%s run_id=%s runner=%s result=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "${outcome:-unknown}" "${run_id:-}" "${runner:-}" "${result:-}" \
    >> "$E2E_PUBLISH_AUDIT_LOG" 2>/dev/null || true
}

# Strict validator + manifest builder. Reads the M2 payload from <infile>,
# enforces the exact E2E result schema with bounded fields and no unexpected
# keys, and — only on success — writes a deterministic-name ConfigMap manifest
# to <outfile> and prints `name=… run_id=… runner=… result=…` on stdout. The
# hub namespace and runner allowlist come from the environment (M4-controlled),
# never from the payload. Exits non-zero with a reason on any violation.
function _e2e_publish_build() {
  local infile="$1" outfile="$2"
  E2E_PUBLISH_IN="$infile" \
  E2E_PUBLISH_OUT="$outfile" \
  E2E_EVENT_NS="$E2E_RESULT_EVENT_NAMESPACE" \
  E2E_PUBLISH_ALLOWLIST="$E2E_RUNNER_ALLOWLIST" \
  python3 <<'PY'
import datetime, hashlib, json, os, re, sys

def die(msg):
    sys.stderr.write("reject: %s\n" % msg)
    sys.exit(1)

ns = os.environ["E2E_EVENT_NS"]
# The publisher only accepts remote runners; local-m4 publishes itself directly.
allow = {r for r in os.environ.get("E2E_PUBLISH_ALLOWLIST", "").split() if r} - {"local-m4"}

with open(os.environ["E2E_PUBLISH_IN"], encoding="utf-8") as fh:
    raw = fh.read()
try:
    s = json.loads(raw)
except Exception as e:
    die("payload is not valid JSON (%s)" % e)
if not isinstance(s, dict):
    die("payload must be a JSON object")

ALLOWED = {
    "run_id", "tier", "runner", "service", "project", "candidate_digest",
    "passed", "total", "failed", "duration_seconds", "timestamp", "commit",
    "exit_code", "phase", "result",
}
REQUIRED = {
    "run_id", "tier", "runner", "service", "project", "candidate_digest",
    "duration_seconds", "timestamp", "exit_code", "phase", "result",
}
extra = set(s) - ALLOWED
missing = REQUIRED - set(s)
problems = []
problems.extend(["unexpected keys: " + ",".join(sorted(extra))] if extra else [])
problems.extend(["missing required keys: " + ",".join(sorted(missing))] if missing else [])
if problems:
    die("; ".join(problems))

# candidate_digest is legitimately null when a run pins no candidate image.
s["candidate_digest"] = s.get("candidate_digest") or ""

def sstr(key, maxlen, pattern=None, allow_empty=False):
    v = s.get(key)
    ok = (isinstance(v, str) and len(v) <= maxlen
          and (allow_empty or bool(v))
          and (pattern is None or not v or re.match(pattern, v) is not None))
    if not ok:
        die("%s invalid (want string <=%d chars matching format)" % (key, maxlen))
    return v

# key, maxlen, pattern, allow_empty
STR_FIELDS = [
    ("run_id", 128, r"^[A-Za-z0-9._-]+$", False),
    ("tier", 64, r"^[A-Za-z0-9._-]+$", False),
    ("runner", 64, r"^[A-Za-z0-9._-]+$", False),
    ("service", 128, r"^[A-Za-z0-9._/-]+$", False),
    ("project", 128, r"^[A-Za-z0-9._+/ -]*$", True),
    ("candidate_digest", 256, r"^([A-Za-z0-9._/-]+@)?sha256:[0-9a-f]{64}$", True),
    ("timestamp", 64, r"^[0-9T:.+\-Z ]+$", False),
    ("phase", 64, r"^[A-Za-z0-9._-]+$", False),
    ("commit", 64, r"^[A-Za-z0-9._-]*$", True),
]
vals = {k: sstr(k, m, p, e) for (k, m, p, e) in STR_FIELDS}
run_id, tier, runner = vals["run_id"], vals["tier"], vals["runner"]
service, project, digest = vals["service"], vals["project"], vals["candidate_digest"]
timestamp, commit = vals["timestamp"], vals["commit"]
if runner not in allow:
    die("runner %r not permitted for remote publication" % runner)

result = s.get("result")
if result not in ("pass", "fail"):
    die("result must be 'pass' or 'fail'")

ec = s.get("exit_code")
if isinstance(ec, bool) or not isinstance(ec, int) or not (0 <= ec <= 255):
    die("exit_code must be an int in 0..255")

def isnum(v, allow_float):
    types = (int, float) if allow_float else (int,)
    return not isinstance(v, bool) and isinstance(v, types) and 0 <= v <= 10**7

def numstr(key, allow_float=False):
    v = s.get(key)
    if v is not None and not isnum(v, allow_float):
        die("%s must be a non-negative number" % key)
    return "" if v is None else (repr(v) if isinstance(v, float) else str(v))

passed = numstr("passed")
total = numstr("total")
failed = numstr("failed")
dur_s = numstr("duration_seconds", allow_float=True)

created_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
event = {
    "run_id": run_id, "tier": tier, "runner": runner, "service": service,
    "project": project, "candidate_digest": digest,
    "passed": "true" if result == "pass" else "false",
    "total": total, "failed": failed, "duration_seconds": dur_s,
    "timestamp": timestamp, "commit": commit,
}

# Deterministic name -> apply is idempotent per run id; SSH retries cannot
# create duplicate observations.
digest12 = hashlib.sha256(run_id.encode()).hexdigest()[:12]
name = "e2e-result-%s-%s" % (re.sub(r"[^a-z0-9-]", "-", runner.lower()), digest12)

manifest = {
    "apiVersion": "v1", "kind": "ConfigMap",
    "metadata": {
        "name": name, "namespace": ns,
        "labels": {
            "k3dm.k3d.io/e2e-result": "true",
            "k3dm.k3d.io/e2e-service": service,
            "k3dm.k3d.io/e2e-tier": tier,
            "k3dm.k3d.io/e2e-runner": runner,
        },
    },
    "data": {"created_at": created_at, "event.json": json.dumps(event)},
}
with open(os.environ["E2E_PUBLISH_OUT"], "w", encoding="utf-8") as fh:
    json.dump(manifest, fh)
sys.stdout.write("name=%s run_id=%s runner=%s result=%s service=%s tier=%s\n"
                 % (name, run_id, runner, result, service, tier))
PY
}

# Retention keyed on (service,tier,runner), pinned to the hub context so a
# stray current-context (e.g. an ACG sandbox) can never be the delete target.
function _e2e_publish_prune() {
  local service="$1" tier="$2" runner="$3"
  local selector="k3dm.k3d.io/e2e-result=true,k3dm.k3d.io/e2e-service=${service},k3dm.k3d.io/e2e-tier=${tier},k3dm.k3d.io/e2e-runner=${runner}"
  local names
  names="$(_kubectl --context "$E2E_HUB_CONTEXT" -n "$E2E_RESULT_EVENT_NAMESPACE" get configmaps \
    -l "$selector" --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)"
  [[ -z "$names" ]] && return 0
  local total keep_from stale name
  total="$(printf '%s\n' "$names" | grep -c . || true)"
  (( total <= E2E_RESULT_EVENT_KEEP )) && return 0
  keep_from=$(( total - E2E_RESULT_EVENT_KEEP ))
  stale="$(printf '%s\n' "$names" | head -n "$keep_from")"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    _kubectl --context "$E2E_HUB_CONTEXT" -n "$E2E_RESULT_EVENT_NAMESPACE" \
      delete configmap "$name" >/dev/null 2>&1 || true
  done <<< "$stale"
}

# Public: the SSH forced command for the dedicated M2 principal. Reads exactly
# one JSON result document on stdin, validates it, and is the ONLY writer of the
# hub e2e-result ConfigMap for remote runs. It ignores SSH_ORIGINAL_COMMAND,
# accepts no kubeconfig/namespace/manifest/kubectl args from the caller, assigns
# the hub context internally, and is idempotent per run id.
function e2e_result_publish() {
  # Pin the target cluster; an inherited KUBECONFIG must not redirect the write.
  export KUBECONFIG="$E2E_PUBLISH_KUBECONFIG"

  local payload manifest
  payload="$(mktemp -t e2e-publish-in.XXXXXX)"
  manifest="$(mktemp -t e2e-publish-cm.XXXXXX)"
  # shellcheck disable=SC2064
  trap "rm -f '$payload' '$manifest'" RETURN

  # Bounded read: cap the payload so a runaway/hostile stream cannot exhaust M4.
  head -c "$E2E_PUBLISH_MAX_BYTES" > "$payload"
  if [[ ! -s "$payload" ]]; then
    _e2e_publish_audit rejected "" "" ""
    _err "[e2e-publish] empty payload on stdin"
  fi

  local meta
  if ! meta="$(_e2e_publish_build "$payload" "$manifest")"; then
    _e2e_publish_audit rejected "" "" ""
    _err "[e2e-publish] payload rejected by schema validation"
  fi

  local run_id runner result service tier
  run_id="$(sed -n 's/.*run_id=\([^ ]*\).*/\1/p' <<<"$meta")"
  runner="$(sed -n 's/.*runner=\([^ ]*\).*/\1/p' <<<"$meta")"
  result="$(sed -n 's/.*result=\([^ ]*\).*/\1/p' <<<"$meta")"
  service="$(sed -n 's/.*service=\([^ ]*\).*/\1/p' <<<"$meta")"
  tier="$(sed -n 's/.* tier=\([^ ]*\).*/\1/p' <<<"$meta")"

  if _kubectl --context "$E2E_HUB_CONTEXT" -n "$E2E_RESULT_EVENT_NAMESPACE" \
       apply -f "$manifest" >/dev/null 2>&1; then
    _e2e_publish_audit applied "$run_id" "$runner" "$result"
    _info "[e2e-publish] applied result for run ${run_id} (runner=${runner}, result=${result})"
    _e2e_publish_prune "$service" "$tier" "$runner"
    return 0
  fi
  _e2e_publish_audit apply_failed "$run_id" "$runner" "$result"
  _err "[e2e-publish] kubectl apply failed for run ${run_id}"
}

# Install the dedicated, restricted authorized_keys entry for the M2 publisher
# principal. Forces e2e_result_publish, disables pty/forwarding/shell, and is
# idempotent via a marker comment. Never installs a personal/admin key.
function e2e_result_publisher_install() {
  local pubkey="${1:-}"
  [[ -n "$pubkey" && -r "$pubkey" ]] || _err "usage: e2e_result_publisher_install <path-to-m2-publisher.pub>"

  local keyline marker dispatcher authfile
  keyline="$(tr -d '\n' < "$pubkey")"
  [[ "$keyline" =~ ^(ssh-|ecdsa-|sk-) ]] || _err "[e2e-publish] '${pubkey}' does not look like an SSH public key"
  marker="e2e-m2-publisher"

  dispatcher="$(cd "${SCRIPT_DIR}" && pwd)/k3d-manager"
  authfile="${HOME}/.ssh/authorized_keys"
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  touch "$authfile"
  chmod 600 "$authfile"

  if grep -qF "$marker" "$authfile" 2>/dev/null; then
    _info "[e2e-publish] publisher principal already installed (marker ${marker})"
    return 0
  fi

  local entry publish_from="${E2E_PUBLISH_FROM:-}"
  if [[ -n "$publish_from" ]]; then
    entry="from=\"${publish_from}\",command=\"${dispatcher} e2e_result_publish\",restrict,no-pty,no-agent-forwarding,no-port-forwarding,no-X11-forwarding ${keyline} ${marker}"
  else
    entry="command=\"${dispatcher} e2e_result_publish\",restrict,no-pty,no-agent-forwarding,no-port-forwarding,no-X11-forwarding ${keyline} ${marker}"
  fi
  printf '%s\n' "$entry" >> "$authfile"
  _info "[e2e-publish] installed restricted M2 publisher principal in ${authfile}"
}

# --- Failure behavior and operations (increment 6) -------------------------

# Newest run summary the local E2E writer produced, excluding the retention
# markers. Prints the path or nothing.
function _e2e_newest_summary() {
  [[ -d "$E2E_REPORT_DIR" ]] || return 0
  # Filenames are our own run_ids (safe charset); -t needs a time sort a glob
  # cannot provide, so ls|grep is intentional here.
  # shellcheck disable=SC2010
  ls -1t "$E2E_REPORT_DIR"/*.json 2>/dev/null \
    | grep -vE '\.(publication_pending|published)\.json$' | head -n1
}

# Build a minimal, schema-valid failed summary for a run that produced none
# (a crash before the E2E writer ran). Prints the file path on success.
function _e2e_synth_summary() {
  local rc="${1:-1}" file
  file="${E2E_REPORT_DIR}/synth-$(date -u +%Y%m%dT%H%M%SZ).json"
  E2E_SYNTH_FILE="$file" \
  E2E_SYNTH_RC="$rc" \
  E2E_SYNTH_RUNNER="${E2E_RUNNER:-local-m4}" \
  E2E_SYNTH_SERVICE="${E2E_SERVICE_UNDER_TEST:-shopping-cart}" \
  python3 <<'PY' || return 1
import datetime, json, os
rc = int(os.environ.get("E2E_SYNTH_RC") or "1")
rc = rc if 0 <= rc <= 255 else 1
now = datetime.datetime.now(datetime.timezone.utc)
summary = {
    "run_id": "synth-" + now.strftime("%Y%m%dT%H%M%SZ"),
    "tier": "vcluster",
    "runner": os.environ.get("E2E_SYNTH_RUNNER") or "local-m4",
    "service": os.environ.get("E2E_SYNTH_SERVICE") or "shopping-cart",
    "candidate_digest": None, "project": "api+flows",
    "passed": None, "total": None, "failed": None, "duration_seconds": None,
    "timestamp": now.isoformat(), "commit": "unknown",
    "exit_code": rc, "phase": "dispatch-crash", "result": "fail",
}
with open(os.environ["E2E_SYNTH_FILE"], "w", encoding="utf-8") as fh:
    json.dump(summary, fh)
PY
  printf '%s' "$file"
}

# Push one local result file to the M4 forced-command publisher over the
# dedicated key. Non-zero when no target is configured or the hop fails.
function _e2e_publish_back_push() {
  local file="$1"
  [[ -n "$E2E_PUBLISH_BACK_HOST" ]] || return 1
  local -a opts
  mapfile -t opts < <(_e2e_remote_ssh_opts)
  # Force IPv4 because the source pin is an IPv4 subnet and mDNS may resolve M4 to IPv6.
  ssh -i "$E2E_PUBLISH_BACK_KEY" -o AddressFamily=inet "${opts[@]}" -- "$E2E_PUBLISH_BACK_HOST" < "$file"
}

# Public (runs ON the runner): after an E2E run, push the result to the M4 hub.
# Synthesizes a failed summary when the run left none, and — when no M4 target is
# reachable/configured — retains the result as publication_pending for a bounded
# replay. Always returns 0 so it can never mask the E2E exit code.
function e2e_runner_publish_back() {
  local rc="${1:-1}" summary
  mkdir -p "$E2E_REPORT_DIR"
  summary="$(_e2e_newest_summary)"
  [[ -n "$summary" ]] || summary="$(_e2e_synth_summary "$rc")"
  [[ -n "$summary" && -s "$summary" ]] || { _warn "[e2e-remote] no result to publish back"; return 0; }

  if _e2e_publish_back_push "$summary"; then
    _info "[e2e-remote] result ${summary##*/} published to M4 hub"
    return 0
  fi
  local pending="${summary%.json}.publication_pending.json"
  cp -f "$summary" "$pending" 2>/dev/null || true
  _warn "[e2e-remote] M4 publication unavailable; retained ${pending##*/} for replay"
  return 0
}

# Public (runs ON the runner): bounded replay of retained publication_pending
# results. Publishes only already-retained local files; a published marker is
# renamed so a re-run is idempotent. Never creates new results.
function e2e_runner_publish_replay() {
  local f done=0 pending=0
  [[ -d "$E2E_REPORT_DIR" ]] || { _info "[e2e-remote] no report dir; nothing to replay"; return 0; }
  shopt -s nullglob
  for f in "$E2E_REPORT_DIR"/*.publication_pending.json; do
    if _e2e_publish_back_push "$f"; then
      mv -f "$f" "${f%.publication_pending.json}.published.json" 2>/dev/null || true
      done=$((done + 1))
    else
      pending=$((pending + 1))
    fi
  done
  shopt -u nullglob
  _info "[e2e-remote] replay complete: published=${done} still_pending=${pending}"
  [[ "$pending" -eq 0 ]]
}

# Public (M4): explicit, bounded replay of a remote runner's retained results.
# Never runs automatically.
function e2e_runner_replay() {
  local runner="${1:-}"
  [[ -n "$runner" ]] || _err "usage: e2e_runner_replay <runner>"
  _e2e_runner_allowed "$runner" || _err "[e2e-remote] runner '${runner}' not in allowlist (${E2E_RUNNER_ALLOWLIST})"
  if ! _e2e_remote_ssh "true"; then
    _err "[e2e-remote] runner ${runner} unreachable; cannot replay"
  fi
  local backenv=""
  if [[ -n "$E2E_M2_PUBLISH_BACK_HOST" ]]; then
    backenv="export E2E_PUBLISH_BACK_HOST=${E2E_M2_PUBLISH_BACK_HOST} E2E_PUBLISH_BACK_KEY=${E2E_M2_PUBLISH_BACK_KEY}; "
  fi
  _e2e_remote_ssh "export E2E_REPORT_DIR=${E2E_M2_REMOTE_REPORT_DIR}; ${backenv}cd ${E2E_M2_REPO} && ./scripts/k3d-manager e2e_runner_publish_replay"
}

# Public (M4): clear a STALE runner lock with bounded age + no-live-run checks.
# Never automatic; refuses a fresh lock or one whose runner still has an E2E
# process running.
function e2e_runner_unlock() {
  local runner="${1:-}"
  [[ -n "$runner" ]] || _err "usage: e2e_runner_unlock <runner>"
  _e2e_runner_allowed "$runner" || _err "[e2e-remote] runner '${runner}' not in allowlist (${E2E_RUNNER_ALLOWLIST})"

  local info age running
  info="$(_e2e_remote_ssh "if [ -e \"${E2E_M2_LOCK}\" ]; then now=\$(date -u +%s); mt=\$(stat -f %m \"${E2E_M2_LOCK}\" 2>/dev/null || stat -c %Y \"${E2E_M2_LOCK}\" 2>/dev/null || echo \$now); echo age=\$((now-mt)); if pgrep -f e2e_verify_vcluster >/dev/null 2>&1; then echo running=1; else echo running=0; fi; else echo age=-1; fi" || true)"
  age="$(_e2e_kv "$info" age)"
  running="$(_e2e_kv "$info" running)"

  if [[ "${age:--1}" == "-1" ]]; then
    _info "[e2e-remote] no lock present on ${runner}; nothing to clear"
    return 0
  fi
  if [[ "$running" == "1" ]]; then
    _err "[e2e-remote] refusing to unlock ${runner}: an E2E run is still active"
  fi
  if _e2e_num_lt "$age" "$E2E_M2_LOCK_MAX_AGE"; then
    _err "[e2e-remote] refusing to unlock ${runner}: lock age ${age}s < ${E2E_M2_LOCK_MAX_AGE}s (not yet stale)"
  fi
  _e2e_remote_ssh "rm -rf \"${E2E_M2_LOCK}\""
  _info "[e2e-remote] cleared stale lock on ${runner} (age ${age}s)"
}

# Public (M4): report hub health and runner availability as DISTINCT lines so an
# operator (and `make status`) can tell a hub outage from a runner outage. A
# runner that is merely unavailable is a warning (exit 0) unless an E2E run was
# explicitly requested (E2E_RUN_REQUESTED=1) or an E2E freshness alert is firing
# (E2E_FRESHNESS_ALERT=1). A hub outage is always significant (non-zero).
function e2e_runner_health() {
  local hub="ok" hub_rc=0
  if ! _kubectl --context "$E2E_HUB_CONTEXT" cluster-info >/dev/null 2>&1; then
    hub="unreachable"
    hub_rc=1
  fi
  printf 'hub_context=%s\nhub=%s\n' "$E2E_HUB_CONTEXT" "$hub"

  local pf runner_status
  pf="$(e2e_runner_status 2>/dev/null || true)"
  runner_status="$(_e2e_kv "$pf" status)"
  [[ -n "$runner_status" ]] || runner_status="unreachable"
  printf 'runner=%s\nrunner_status=%s\n' "${E2E_M2_SSH_HOST}" "$runner_status"

  if [[ "$hub_rc" -ne 0 ]]; then
    printf 'severity=critical\n'
    return 1
  fi
  if [[ "$runner_status" == "available" ]]; then
    printf 'severity=ok\n'
    return 0
  fi
  if [[ "${E2E_RUN_REQUESTED:-0}" == "1" || "${E2E_FRESHNESS_ALERT:-0}" == "1" ]]; then
    printf 'severity=critical\n'
    return 1
  fi
  printf 'severity=warning\n'
  return 0
}
