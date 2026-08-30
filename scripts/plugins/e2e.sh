#!/usr/bin/env bash
set -euo pipefail

E2E_IMAGE="${E2E_IMAGE:-ghcr.io/wilddog64/shopping-cart-e2e-tests}"
E2E_IMAGE_TAG="${E2E_IMAGE_TAG:-latest}"
E2E_NAMESPACE="${E2E_NAMESPACE:-shopping-cart-apps}"
E2E_JOB_TIMEOUT="${E2E_JOB_TIMEOUT:-1200}"
E2E_REPORT_DIR="${E2E_REPORT_DIR:-${HOME}/.k3dm/e2e}"
E2E_SERVICE_UNDER_TEST="${E2E_SERVICE_UNDER_TEST:-product-catalog}"
E2E_ROLLOUT_TIMEOUT="${E2E_ROLLOUT_TIMEOUT:-300}"
E2E_VCLUSTER_READY_TIMEOUT="${E2E_VCLUSTER_READY_TIMEOUT:-600}"
E2E_VCLUSTER_READY_INTERVAL="${E2E_VCLUSTER_READY_INTERVAL:-5}"
E2E_VCLUSTER_READY_REFRESH_INTERVAL="${E2E_VCLUSTER_READY_REFRESH_INTERVAL:-30}"
E2E_RESULT_EVENT_NAMESPACE="${E2E_RESULT_EVENT_NAMESPACE:-platform-ops}"
E2E_RESULT_EVENT_KEEP="${E2E_RESULT_EVENT_KEEP:-20}"
export E2E_IMAGE E2E_IMAGE_TAG E2E_NAMESPACE E2E_JOB_TIMEOUT E2E_REPORT_DIR
export E2E_SERVICE_UNDER_TEST E2E_ROLLOUT_TIMEOUT E2E_VCLUSTER_READY_TIMEOUT
export E2E_VCLUSTER_READY_INTERVAL E2E_VCLUSTER_READY_REFRESH_INTERVAL
export E2E_RESULT_EVENT_NAMESPACE E2E_RESULT_EVENT_KEEP

function _e2e_load_deps() {
  local plugin
  if ! declare -f vcluster_create >/dev/null 2>&1; then
    plugin="${SCRIPT_DIR}/plugins/vcluster.sh"
    [[ -r "$plugin" ]] || _err "e2e: required plugin not found: ${plugin}"
    # shellcheck source=/dev/null
    source "$plugin"
  fi
  if ! declare -f shopping_cart_resolve_ghcr_pat >/dev/null 2>&1; then
    plugin="${SCRIPT_DIR}/plugins/shopping_cart.sh"
    [[ -r "$plugin" ]] || _err "e2e: required plugin not found: ${plugin}"
    # shellcheck source=/dev/null
    source "$plugin"
  fi
}

function _e2e_kc() {
  local kubeconfig="$1"
  shift

  local stdin_cmd=0 arg
  for arg in "$@"; do
    if [[ "$arg" == "-" ]]; then
      stdin_cmd=1
      break
    fi
  done

  if (( stdin_cmd )); then
    KUBECONFIG="$kubeconfig" _run_command -- kubectl "$@"
    return
  fi

  local attempts="${E2E_KC_MAX_ATTEMPTS:-4}"
  local interval="${E2E_KC_RETRY_INTERVAL:-5}"
  local i=1
  while :; do
    if KUBECONFIG="$kubeconfig" _run_command --no-exit -- kubectl "$@"; then
      return 0
    fi
    if (( i < attempts )) \
      && ! KUBECONFIG="$kubeconfig" _run_command --no-exit --quiet -- \
        kubectl --request-timeout=5s get --raw=/readyz >/dev/null 2>&1; then
      _warn "[e2e] vCluster API unreachable (attempt ${i}/${attempts}); refreshing proxy and retrying"
      if [[ -n "${_E2E_ACTIVE_NAME:-}" ]] && declare -f _vcluster_refresh_connection >/dev/null 2>&1; then
        _vcluster_refresh_connection "${_E2E_ACTIVE_NAME}"
      fi
      i=$((i + 1))
      sleep "$interval"
      continue
    fi
    _err "e2e: kubectl $* failed"
  done
}

function e2e_verify_vcluster() {
  local candidate_digest="${1:-}"
  local run_id name kubeconfig rc

  _e2e_load_deps

  run_id="$(date +%s)-${RANDOM}"
  name="e2e-${run_id}"
  kubeconfig="$(_vcluster_kubeconfig_path "$name")"

  # Persist enough context to diagnose failures that occur before the vCluster
  # is ready. The old trap only tore down the vCluster, so set -e failures in
  # setup lost the phase, exit code, and result event.
  _E2E_RUN_ID="$run_id"
  _E2E_CANDIDATE_DIGEST="$candidate_digest"
  _E2E_REPORT_DIR="$E2E_REPORT_DIR"
  _E2E_ACTIVE_PHASE="creating-vcluster"
  _E2E_SUMMARY_WRITTEN=0
  mkdir -p "$E2E_REPORT_DIR"

  # Hoist the name to a global so the EXIT trap can reference it safely even
  # after this function's locals go out of scope (set -u would otherwise fault).
  _E2E_ACTIVE_NAME="$name"
  trap '_e2e_exit_trap' EXIT

  vcluster_create "$name"
  _E2E_ACTIVE_PHASE="waiting-vcluster"
  _e2e_wait_vcluster_ready "$kubeconfig" "$name"
  _E2E_ACTIVE_PHASE="deploying-substrate"
  _e2e_deploy_substrate "$kubeconfig" "$candidate_digest"
  _E2E_ACTIVE_PHASE="running-playwright"
  _e2e_run_job "$kubeconfig" "$run_id" "$candidate_digest"
  rc="${_E2E_EXIT:-1}"

  _E2E_ACTIVE_PHASE="recording-result"
  _e2e_write_summary "$run_id" "$candidate_digest" "$rc" "${_E2E_ACTIVE_PHASE}"
  _E2E_SUMMARY_WRITTEN=1
  _e2e_write_result_event "$run_id"
  return "$rc"
}

function _e2e_exit_trap() {
  local rc=$?
  set +e
  if [[ -n "${_E2E_RUN_ID:-}" ]] && [[ "${_E2E_SUMMARY_WRITTEN:-0}" -eq 0 ]]; then
    _e2e_write_summary "${_E2E_RUN_ID}" "${_E2E_CANDIDATE_DIGEST:-}" "$rc" "${_E2E_ACTIVE_PHASE:-unknown}" || true
    _e2e_write_result_event "${_E2E_RUN_ID}" || true
  fi
  _e2e_teardown "${_E2E_ACTIVE_NAME:-}" || true
  trap - EXIT
  exit "$rc"
}

function _e2e_teardown() {
  local name="${1:-}"
  [[ -z "$name" ]] && return 0
  vcluster_destroy "$name" || _warn "e2e: teardown of ${name} failed (manual cleanup may be needed)"

  # Keep cleanup idempotent even when the vCluster API is already gone. In
  # that case vcluster_destroy can return before removing its proxy and
  # kubeconfig, leaving local processes and credentials behind after a failed
  # run. These best-effort removals are safe when destroy already completed.
  local kubeconfig=""
  if declare -f _vcluster_kubeconfig_path >/dev/null 2>&1; then
    kubeconfig="$(_vcluster_kubeconfig_path "$name" 2>/dev/null || true)"
  fi
  if [[ -n "$kubeconfig" && -f "$kubeconfig" ]]; then
    _run_command -- rm -f "$kubeconfig" || true
  fi
  if declare -f _vcluster_remove_proxy >/dev/null 2>&1; then
    _vcluster_remove_proxy "$name" || true
  fi

  # JSON summaries are the durable audit record; per-run logs are transient
  # and can otherwise accumulate indefinitely on the host.
  if [[ -n "${_E2E_RUN_ID:-}" && -n "${E2E_REPORT_DIR:-}" ]]; then
    _run_command -- rm -f "${E2E_REPORT_DIR}/${_E2E_RUN_ID}.log" || true
  fi
}

function _e2e_wait_vcluster_ready() {
  local kubeconfig="${1:-}"
  local name="${2:-}"
  [[ -z "$kubeconfig" ]] && _err "e2e: _e2e_wait_vcluster_ready requires a kubeconfig"

  local now deadline next_refresh
  now=$(date +%s)
  deadline=$(( now + E2E_VCLUSTER_READY_TIMEOUT ))
  next_refresh=$(( now + E2E_VCLUSTER_READY_REFRESH_INTERVAL ))
  _info "[e2e] Waiting for vCluster API to be ready (timeout ${E2E_VCLUSTER_READY_TIMEOUT}s)"
  while now=$(date +%s); (( now < deadline )); do
    # Soft probe: a failed /readyz must RETURN non-zero, never exit. A bare
    # _run_command calls _err -> exit on failure, which (bypassing this if)
    # would kill the whole harness on the first not-ready probe.
    if KUBECONFIG="$kubeconfig" _run_command --no-exit --quiet -- \
        kubectl get --raw='/readyz' >/dev/null 2>&1; then
      _info "[e2e] vCluster API is ready"
      return 0
    fi
    # vcluster 0.36.x's background-proxy port-forward dies on the syncer's
    # startup restart and never reconnects; recreate it so the pinned-port
    # kubeconfig can reach the current pod on the next probe. Refresh on its
    # own (slower) cadence so we do not hammer a still-starting syncer.
    if [[ -n "$name" ]] && (( now >= next_refresh )) \
        && declare -f _vcluster_refresh_connection >/dev/null 2>&1; then
      _vcluster_refresh_connection "$name"
      next_refresh=$(( now + E2E_VCLUSTER_READY_REFRESH_INTERVAL ))
    fi
    sleep "$E2E_VCLUSTER_READY_INTERVAL"
  done
  _err "e2e: vCluster API not ready within ${E2E_VCLUSTER_READY_TIMEOUT}s"
}

function _e2e_deploy_substrate() {
  local kubeconfig="${1:-}"
  local candidate_digest="${2:-}"
  [[ -z "$kubeconfig" ]] && _err "e2e: _e2e_deploy_substrate requires a kubeconfig"

  _e2e_provision_pull_secret "$kubeconfig"

  _info "[e2e] Applying substrate bundle (scripts/etc/e2e) into ${E2E_NAMESPACE}"
  _e2e_kc "$kubeconfig" apply -k "${SCRIPT_DIR}/etc/e2e"

  if [[ -n "$candidate_digest" ]]; then
    _info "[e2e] Overriding ${E2E_SERVICE_UNDER_TEST} image with candidate ${candidate_digest}"
    _e2e_kc "$kubeconfig" -n "$E2E_NAMESPACE" set image \
      "deployment/${E2E_SERVICE_UNDER_TEST}" "${E2E_SERVICE_UNDER_TEST}=${candidate_digest}"
  fi

  local rollout
  for rollout in postgres redis product-catalog basket order; do
    _info "[e2e] Waiting for rollout: ${rollout}"
    _e2e_kc "$kubeconfig" -n "$E2E_NAMESPACE" rollout status \
      "deployment/${rollout}" --timeout="${E2E_ROLLOUT_TIMEOUT}s"
  done

  _info "[e2e] Waiting for seed job to complete"
  _e2e_kc "$kubeconfig" -n "$E2E_NAMESPACE" wait \
    --for=condition=complete "job/product-catalog-seed" --timeout="${E2E_ROLLOUT_TIMEOUT}s"
}

function _e2e_provision_pull_secret() {
  local kubeconfig="${1:-}"
  local _github_user="" _ghcr_pat=""
  shopping_cart_resolve_ghcr_pat

  _e2e_kc "$kubeconfig" create namespace "$E2E_NAMESPACE" \
    --dry-run=client -o yaml | _e2e_kc "$kubeconfig" apply -f -

  _e2e_provision_datastore_secret "$kubeconfig"

  _e2e_kc "$kubeconfig" create secret docker-registry ghcr-pull-secret \
    --docker-server=ghcr.io \
    --docker-username="${_github_user}" \
    --docker-password="${_ghcr_pat}" \
    -n "$E2E_NAMESPACE" \
    --dry-run=client -o yaml | _e2e_kc "$kubeconfig" apply -f -

  _e2e_kc "$kubeconfig" -n "$E2E_NAMESPACE" patch serviceaccount default \
    -p '{"imagePullSecrets": [{"name": "ghcr-pull-secret"}]}'
}

function _e2e_provision_datastore_secret() {
  local kubeconfig="${1:-}" postgres_password redis_password
  postgres_password="${E2E_POSTGRES_PASSWORD:-$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')}"
  redis_password="${E2E_REDIS_PASSWORD:-$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')}"
  _e2e_kc "$kubeconfig" create secret generic e2e-datastore-credentials \
    --from-literal=postgres-password="${postgres_password}" \
    --from-literal=redis-password="${redis_password}" \
    -n "$E2E_NAMESPACE" --dry-run=client -o yaml | _e2e_kc "$kubeconfig" apply -f -
}

function _e2e_job_manifest() {
  local job_name="${1:-}"
  local image="${2:-}"
  cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: ${E2E_NAMESPACE}
  labels:
    app.kubernetes.io/name: e2e-runner
    app.kubernetes.io/part-of: shopping-cart-e2e
spec:
  backoffLimit: 0
  activeDeadlineSeconds: ${E2E_JOB_TIMEOUT}
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: e2e-runner
        app.kubernetes.io/part-of: shopping-cart-e2e
    spec:
      restartPolicy: Never
      imagePullSecrets:
      - name: ghcr-pull-secret
      containers:
      - name: e2e
        image: ${image}
        imagePullPolicy: IfNotPresent
        command:
        - sh
        - -c
        - 'npx playwright test --project=api --project=flows; rc=\$?; echo "__E2E_RESULTS_BEGIN__"; cat test-results/results.json 2>/dev/null || true; echo "__E2E_RESULTS_END__"; exit \$rc'
        env:
        - name: PRODUCT_CATALOG_URL
          value: http://product-catalog.${E2E_NAMESPACE}.svc:8000
        - name: BASKET_URL
          value: http://basket.${E2E_NAMESPACE}.svc:8083
        - name: ORDER_URL
          value: http://order.${E2E_NAMESPACE}.svc:8080
        - name: OAUTH2_ENABLED
          value: "false"
        - name: CI
          value: "true"
EOF
}

function _e2e_run_job() {
  local kubeconfig="${1:-}"
  local run_id="${2:-}"
  local job_name="e2e-run-${run_id}"
  local image="${E2E_IMAGE}:${E2E_IMAGE_TAG}"
  _E2E_EXIT=1

  _info "[e2e] Launching Playwright Job ${job_name} (image ${image})"
  local manifest_file
  manifest_file="$(mktemp -t e2e-job.XXXXXX)"
  _e2e_job_manifest "$job_name" "$image" > "$manifest_file"
  _e2e_kc "$kubeconfig" apply -f "$manifest_file"
  _run_command -- rm -f "$manifest_file"

  local job_rc=0
  _e2e_wait_job "$kubeconfig" "$job_name" || job_rc="$?"

  _run_command -- mkdir -p "$E2E_REPORT_DIR"
  _e2e_kc "$kubeconfig" -n "$E2E_NAMESPACE" logs "job/${job_name}" \
    > "${E2E_REPORT_DIR}/${run_id}.log" 2>/dev/null || true

  _E2E_EXIT="$job_rc"
  return 0
}

function _e2e_wait_job() {
  local kubeconfig="${1:-}"
  local job_name="${2:-}"
  local deadline succeeded failed now
  deadline=$(( $(date +%s) + E2E_JOB_TIMEOUT ))

  while :; do
    succeeded="$(_e2e_kc "$kubeconfig" -n "$E2E_NAMESPACE" get "job/${job_name}" \
      -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
    failed="$(_e2e_kc "$kubeconfig" -n "$E2E_NAMESPACE" get "job/${job_name}" \
      -o jsonpath='{.status.failed}' 2>/dev/null || true)"
    if [[ "${succeeded:-0}" -ge 1 ]] 2>/dev/null; then
      return 0
    fi
    if [[ "${failed:-0}" -ge 1 ]] 2>/dev/null; then
      return 1
    fi
    now="$(date +%s)"
    if (( now >= deadline )); then
      _warn "[e2e] Job ${job_name} did not finish within ${E2E_JOB_TIMEOUT}s"
      return 1
    fi
    sleep 5
  done
}

function _e2e_write_summary() {
  local run_id="${1:-}"
  local candidate_digest="${2:-}"
  local rc="${3:-1}"
  local phase="${4:-unknown}"
  local log_file="${E2E_REPORT_DIR}/${run_id}.log"
  local summary_file="${E2E_REPORT_DIR}/${run_id}.json"

  _run_command -- mkdir -p "$E2E_REPORT_DIR"

  local commit
  commit="$(git -C "${SCRIPT_DIR}/.." rev-parse HEAD 2>/dev/null || echo unknown)"

  E2E_RUN_ID="$run_id" \
  E2E_SERVICE="$E2E_SERVICE_UNDER_TEST" \
  E2E_CANDIDATE="$candidate_digest" \
  E2E_RC="$rc" \
  E2E_PHASE="$phase" \
  E2E_COMMIT="$commit" \
  E2E_LOG="$log_file" \
  E2E_RUNNER="${E2E_RUNNER:-local-m4}" \
  python3 - "$summary_file" <<'PY'
import json, os, re, sys

summary_path = sys.argv[1]
run_id = os.environ["E2E_RUN_ID"]
service = os.environ["E2E_SERVICE"]
candidate = os.environ.get("E2E_CANDIDATE") or None
rc = int(os.environ["E2E_RC"])
phase = os.environ.get("E2E_PHASE", "unknown")
commit = os.environ["E2E_COMMIT"]
log_path = os.environ["E2E_LOG"]
runner = os.environ.get("E2E_RUNNER") or "local-m4"

passed = total = failed = duration = None
try:
    with open(log_path, "r", encoding="utf-8", errors="replace") as fh:
        raw = fh.read()
    m = re.search(r"__E2E_RESULTS_BEGIN__(.*)__E2E_RESULTS_END__", raw, re.S)
    if m:
        data = json.loads(m.group(1).strip())
        stats = data.get("stats", {})
        expected = stats.get("expected", 0)
        unexpected = stats.get("unexpected", 0)
        flaky = stats.get("flaky", 0)
        skipped = stats.get("skipped", 0)
        passed = expected
        failed = unexpected
        total = expected + unexpected + flaky + skipped
        if "duration" in stats:
            duration = round(stats["duration"] / 1000.0, 3)
except Exception:
    pass

summary = {
    "run_id": run_id,
    "tier": "vcluster",
    "runner": runner,
    "service": service,
    "candidate_digest": candidate,
    "project": "api+flows",
    "passed": passed,
    "total": total,
    "failed": failed,
    "duration_seconds": duration,
    "timestamp": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat(),
    "commit": commit,
    "exit_code": rc,
    "phase": phase,
    "result": "pass" if rc == 0 else "fail",
}
with open(summary_path, "w", encoding="utf-8") as fh:
    json.dump(summary, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

  _info "[e2e] Summary written to ${summary_file} (exit_code=${rc})"
}

# Publish the run's result to the hub cluster's platform-ops namespace as a durable
# event ConfigMap. The long-lived vulnerability-inventory-exporter reads these
# (labelSelector k3dm.k3d.io/e2e-result=true) and emits e2e_* gauges for Grafana.
# Best-effort: a run must not fail because the hub is unreachable. Uses _kubectl
# (hub/ambient context), NOT _e2e_kc (the ephemeral vCluster is already gone by now).
function _e2e_write_result_event() {
  local run_id="${1:-}"
  local summary_file="${E2E_REPORT_DIR}/${run_id}.json"
  [[ -r "$summary_file" ]] || { _warn "[e2e] no summary to publish for ${run_id}"; return 0; }

  local manifest_file
  manifest_file="$(mktemp -t e2e-event.XXXXXX)"

  if ! E2E_SUMMARY_FILE="$summary_file" \
       E2E_EVENT_NS="$E2E_RESULT_EVENT_NAMESPACE" \
       python3 - "$manifest_file" <<'PY'
import datetime, json, os, sys

manifest_path = sys.argv[1]
ns = os.environ["E2E_EVENT_NS"]
with open(os.environ["E2E_SUMMARY_FILE"], encoding="utf-8") as fh:
    s = json.load(fh)

created_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
service = s.get("service") or "unknown"
tier = s.get("tier") or "unknown"
runner = s.get("runner") or "local-m4"
event = {
    "run_id": str(s.get("run_id", "")),
    "tier": tier,
    "runner": runner,
    "service": service,
    "project": s.get("project") or "",
    "candidate_digest": s.get("candidate_digest") or "",
    "passed": "true" if s.get("result") == "pass" else "false",
    "total": str(s.get("total") if s.get("total") is not None else ""),
    "failed": str(s.get("failed") if s.get("failed") is not None else ""),
    "duration_seconds": str(s.get("duration_seconds") if s.get("duration_seconds") is not None else ""),
    "timestamp": s.get("timestamp") or created_at,
    "commit": s.get("commit") or "",
}

manifest = {
    "apiVersion": "v1",
    "kind": "ConfigMap",
    "metadata": {
        "generateName": "e2e-result-",
        "namespace": ns,
        "labels": {
            "k3dm.k3d.io/e2e-result": "true",
            "k3dm.k3d.io/e2e-service": service,
            "k3dm.k3d.io/e2e-tier": tier,
            "k3dm.k3d.io/e2e-runner": runner,
        },
    },
    "data": {
        "created_at": created_at,
        "event.json": json.dumps(event),
    },
}
with open(manifest_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh)
PY
  then
    _warn "[e2e] could not build result event for ${run_id}"
    _run_command -- rm -f "$manifest_file"
    return 0
  fi

  if _kubectl create -f "$manifest_file" >/dev/null 2>&1; then
    _info "[e2e] Published result event to ${E2E_RESULT_EVENT_NAMESPACE} for run ${run_id}"
    _e2e_prune_result_events
  else
    _warn "[e2e] could not publish result event (hub ${E2E_RESULT_EVENT_NAMESPACE} unreachable?) — dashboards unaffected"
  fi
  _run_command -- rm -f "$manifest_file"
}

# Writer-side bound: keep only the most recent E2E_RESULT_EVENT_KEEP event
# ConfigMaps per (service,tier,runner) so etcd does not accumulate and runners do
# not evict each other's events. The exporter read is separately capped, so this
# is defence in depth. Best-effort.
function _e2e_prune_result_events() {
  local svc="$E2E_SERVICE_UNDER_TEST"
  local runner="${E2E_RUNNER:-local-m4}"
  local selector="k3dm.k3d.io/e2e-result=true,k3dm.k3d.io/e2e-service=${svc},k3dm.k3d.io/e2e-tier=vcluster,k3dm.k3d.io/e2e-runner=${runner}"
  local names
  names="$(_kubectl -n "$E2E_RESULT_EVENT_NAMESPACE" get configmaps \
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
    _kubectl -n "$E2E_RESULT_EVENT_NAMESPACE" delete configmap "$name" >/dev/null 2>&1 || true
  done <<< "$stale"
}

# Extract the concrete "newName:newTag" image references pinned in a kustomize
# overlay. Only images with BOTH a newName and a newTag are emitted — those are
# the real registry refs the substrate pulls. Pure text parsing (no docker), so
# it is unit-testable.
function _e2e_kustomization_images() {
  local file="$1"
  [[ -r "$file" ]] || return 0
  awk '
    /^[[:space:]]*newName:[[:space:]]/ { name = $2; next }
    /^[[:space:]]*newTag:[[:space:]]/  {
      if (name != "") { print name ":" $2; name = "" }
    }
  ' "$file"
}

# Every concrete image the E2E substrate pulls: the kustomize newName:newTag
# overrides (the app images) unioned with the already-tagged images referenced
# literally in the manifests (postgres, redis, alpine, python, ...). Bare
# kustomize placeholder names (no ':') are skipped — they are remapped by the
# override block above. Pure text parsing, unit-testable.
function _e2e_substrate_images() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  _e2e_kustomization_images "${dir}/kustomization.yaml"
  awk '$1 == "image:" && $2 ~ /:/ { print $2 }' "${dir}"/*.yaml 2>/dev/null
}

# Convert a `docker images` .CreatedAt string ("2026-08-17 10:23:45 -0700 PDT")
# to a Unix epoch. Tries BSD date (macOS) first, then GNU date (Linux/CI).
# Prints nothing and returns 1 when the timestamp cannot be parsed. Pure logic.
function _e2e_image_epoch() {
  local ts="$1"
  local dt="${ts%% [-+]*}"
  date -j -f "%Y-%m-%d %H:%M:%S" "$dt" +%s 2>/dev/null && return 0
  date -d "$dt" +%s 2>/dev/null && return 0
  return 1
}

# Return 0 if ref matches any of the remaining glob patterns. With no patterns
# it returns 1 (matches nothing). Pattern side is intentionally unquoted so
# globs like "*/vcluster-pro" work. Pure logic, unit-testable.
function _e2e_ref_matches_globs() {
  local ref="$1"
  shift
  local glob
  for glob in "$@"; do
    # shellcheck disable=SC2053
    [[ "$ref" == $glob ]] && return 0
  done
  return 1
}

function _e2e_prune_images_usage() {
  cat >&2 <<'USAGE'
Usage: e2e_prune_images [--days N] [--apply]

Prune local Docker images older than N days that are NOT part of the E2E
working set. Dry-run by default — prints what WOULD be removed and changes
nothing until you pass --apply.

Protected (never removed), regardless of age:
  - every image the E2E substrate (scripts/etc/e2e) pulls: the kustomize
    newName:newTag app images plus the tagged infra images referenced in the
    manifests (postgres, redis, alpine, python, ...)
  - the E2E test-runner image (E2E_IMAGE:E2E_IMAGE_TAG)
  - any image currently backing a container (running or stopped)
  - any repo:tag matching a pattern in E2E_IMAGE_PRUNE_KEEP (space-separated globs)

Options:
  --days N     age threshold in days (default: E2E_IMAGE_PRUNE_DAYS or 30)
  --apply      actually remove candidates (omit for a dry run)
  --dry-run    force dry run (default)
  -h, --help   show this help

Removal uses `docker image rm` (not -f): an image still referenced elsewhere is
skipped, not force-deleted. Dangling (<none>:<none>) images are left for
`docker image prune`.
USAGE
}

function e2e_prune_images() {
  local days="${E2E_IMAGE_PRUNE_DAYS:-30}"
  local apply=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days) days="${2:-}"; shift 2 ;;
      --days=*) days="${1#*=}"; shift ;;
      --apply|--force) apply=1; shift ;;
      --dry-run) apply=0; shift ;;
      -h|--help) _e2e_prune_images_usage; return 0 ;;
      *) _e2e_prune_images_usage; _err "e2e_prune_images: unknown argument: $1" ;;
    esac
  done

  [[ "$days" =~ ^[0-9]+$ ]] || _err "e2e_prune_images: --days must be a non-negative integer (got: ${days})"
  command -v docker >/dev/null 2>&1 || _err "e2e_prune_images: docker not found on PATH"

  local substrate_dir="${SCRIPT_DIR}/etc/e2e"

  local -a protect_refs=("${E2E_IMAGE}:${E2E_IMAGE_TAG}")
  local ref
  while IFS= read -r ref; do
    [[ -n "$ref" ]] && protect_refs+=("$ref")
  done < <(_e2e_substrate_images "$substrate_dir")

  local -A protect_ids=()
  local id
  for ref in "${protect_refs[@]}"; do
    id="$(_run_command --quiet -- docker image inspect -f '{{.Id}}' "$ref" 2>/dev/null || true)"
    [[ -n "$id" ]] && protect_ids["$id"]=1
  done

  local cid
  while IFS= read -r cid; do
    [[ -z "$cid" ]] && continue
    id="$(_run_command --quiet -- docker inspect -f '{{.Image}}' "$cid" 2>/dev/null || true)"
    [[ -n "$id" ]] && protect_ids["$id"]=1
  done < <(_run_command --quiet -- docker ps -aq 2>/dev/null || true)

  local -a keep_globs=()
  if [[ -n "${E2E_IMAGE_PRUNE_KEEP:-}" ]]; then
    read -r -a keep_globs <<< "${E2E_IMAGE_PRUNE_KEEP}"
  fi

  local now cutoff
  now="$(date +%s)"
  cutoff=$(( now - days * 86400 ))

  local removed=0 kept=0 img_id repo_tag created_at created_epoch
  _info "[e2e-prune] mode=$([[ $apply -eq 1 ]] && echo APPLY || echo DRY-RUN) threshold=${days}d protected-refs=${#protect_refs[@]}"

  while IFS='|' read -r img_id repo_tag created_at; do
    [[ -z "$img_id" ]] && continue
    [[ "$repo_tag" == "<none>:<none>" ]] && continue

    if [[ -n "${protect_ids[$img_id]:-}" ]]; then
      kept=$((kept + 1)); continue
    fi

    if _e2e_ref_matches_globs "$repo_tag" "${keep_globs[@]}"; then
      kept=$((kept + 1)); continue
    fi

    if ! created_epoch="$(_e2e_image_epoch "$created_at")"; then
      kept=$((kept + 1)); continue
    fi
    if (( created_epoch >= cutoff )); then
      kept=$((kept + 1)); continue
    fi

    if (( apply )); then
      if _run_command --quiet -- docker image rm "$img_id" >/dev/null 2>&1; then
        _info "[e2e-prune] removed ${repo_tag} (${created_at})"
        removed=$((removed + 1))
      else
        _warn "[e2e-prune] still referenced, skipped: ${repo_tag}"
        kept=$((kept + 1))
      fi
    else
      printf 'WOULD REMOVE  %-64s %s\n' "$repo_tag" "$created_at" >&2
      removed=$((removed + 1))
    fi
  done < <(_run_command --quiet -- docker images --no-trunc --format '{{.ID}}|{{.Repository}}:{{.Tag}}|{{.CreatedAt}}' 2>/dev/null || true)

  if (( apply )); then
    _info "[e2e-prune] done: removed ${removed}, kept ${kept}"
  else
    _info "[e2e-prune] dry run: ${removed} would be removed, ${kept} kept. Re-run with --apply to delete."
  fi
}
