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
export E2E_IMAGE E2E_IMAGE_TAG E2E_NAMESPACE E2E_JOB_TIMEOUT E2E_REPORT_DIR
export E2E_SERVICE_UNDER_TEST E2E_ROLLOUT_TIMEOUT E2E_VCLUSTER_READY_TIMEOUT

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
  KUBECONFIG="$kubeconfig" _run_command -- kubectl "$@"
}

function e2e_verify_vcluster() {
  local candidate_digest="${1:-}"
  local run_id name kubeconfig rc

  _e2e_load_deps

  run_id="$(date +%s)-${RANDOM}"
  name="e2e-${run_id}"
  kubeconfig="$(_vcluster_kubeconfig_path "$name")"

  # Hoist the name to a global so the EXIT trap can reference it safely even
  # after this function's locals go out of scope (set -u would otherwise fault).
  _E2E_ACTIVE_NAME="$name"
  trap '_e2e_teardown "${_E2E_ACTIVE_NAME:-}"' EXIT

  vcluster_create "$name"
  _e2e_wait_vcluster_ready "$kubeconfig"
  _e2e_deploy_substrate "$kubeconfig" "$candidate_digest"
  _e2e_run_job "$kubeconfig" "$run_id" "$candidate_digest"
  rc="${_E2E_EXIT:-1}"

  _e2e_write_summary "$run_id" "$candidate_digest" "$rc"
  return "$rc"
}

function _e2e_teardown() {
  local name="${1:-}"
  [[ -z "$name" ]] && return 0
  vcluster_destroy "$name" || _warn "e2e: teardown of ${name} failed (manual cleanup may be needed)"
}

function _e2e_wait_vcluster_ready() {
  local kubeconfig="${1:-}"
  [[ -z "$kubeconfig" ]] && _err "e2e: _e2e_wait_vcluster_ready requires a kubeconfig"

  local deadline
  deadline=$(( $(date +%s) + E2E_VCLUSTER_READY_TIMEOUT ))
  _info "[e2e] Waiting for vCluster API to be ready (timeout ${E2E_VCLUSTER_READY_TIMEOUT}s)"
  while (( $(date +%s) < deadline )); do
    if _e2e_kc "$kubeconfig" get --raw='/readyz' >/dev/null 2>&1; then
      _info "[e2e] vCluster API is ready"
      return 0
    fi
    sleep 5
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

  _e2e_kc "$kubeconfig" create secret docker-registry ghcr-pull-secret \
    --docker-server=ghcr.io \
    --docker-username="${_github_user}" \
    --docker-password="${_ghcr_pat}" \
    -n "$E2E_NAMESPACE" \
    --dry-run=client -o yaml | _e2e_kc "$kubeconfig" apply -f -

  _e2e_kc "$kubeconfig" -n "$E2E_NAMESPACE" patch serviceaccount default \
    -p '{"imagePullSecrets": [{"name": "ghcr-pull-secret"}]}'
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
  local log_file="${E2E_REPORT_DIR}/${run_id}.log"
  local summary_file="${E2E_REPORT_DIR}/${run_id}.json"

  _run_command -- mkdir -p "$E2E_REPORT_DIR"

  local commit
  commit="$(git -C "${SCRIPT_DIR}/.." rev-parse HEAD 2>/dev/null || echo unknown)"

  E2E_RUN_ID="$run_id" \
  E2E_SERVICE="$E2E_SERVICE_UNDER_TEST" \
  E2E_CANDIDATE="$candidate_digest" \
  E2E_RC="$rc" \
  E2E_COMMIT="$commit" \
  E2E_LOG="$log_file" \
  python3 - "$summary_file" <<'PY'
import json, os, re, sys

summary_path = sys.argv[1]
run_id = os.environ["E2E_RUN_ID"]
service = os.environ["E2E_SERVICE"]
candidate = os.environ.get("E2E_CANDIDATE") or None
rc = int(os.environ["E2E_RC"])
commit = os.environ["E2E_COMMIT"]
log_path = os.environ["E2E_LOG"]

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
    "result": "pass" if rc == 0 else "fail",
}
with open(summary_path, "w", encoding="utf-8") as fh:
    json.dump(summary, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

  _info "[e2e] Summary written to ${summary_file} (exit_code=${rc})"
}
