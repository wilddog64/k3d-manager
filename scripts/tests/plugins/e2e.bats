#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/e2e.sh"

  RUN_LOG="$BATS_TEST_TMPDIR/run.log"
  VC_LOG="$BATS_TEST_TMPDIR/vcluster.log"
  : > "$RUN_LOG"
  : > "$VC_LOG"
  RUN_EXIT_CODES=()

  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
  mkdir -p "$E2E_REPORT_DIR"
  export E2E_JOB_TIMEOUT=5
  export E2E_ROLLOUT_TIMEOUT=5
  export E2E_VCLUSTER_READY_INTERVAL=0

  _run_command() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--soft|--quiet|--prefer-sudo|--require-sudo|--interactive-sudo) shift ;;
        --probe) shift 2 ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    echo "$*" >> "$RUN_LOG"
    local rc=0
    if ((${#RUN_EXIT_CODES[@]})); then
      rc=${RUN_EXIT_CODES[0]}
      RUN_EXIT_CODES=("${RUN_EXIT_CODES[@]:1}")
    fi
    return "$rc"
  }

  # Stub sibling-plugin dependencies so _e2e_load_deps does not source the real files.
  vcluster_create() { echo "vcluster_create $*" >> "$VC_LOG"; }
  vcluster_destroy() { echo "vcluster_destroy $*" >> "$VC_LOG"; }
  _vcluster_kubeconfig_path() { echo "$BATS_TEST_TMPDIR/${1}.kubeconfig"; }
  shopping_cart_resolve_ghcr_pat() { _github_user="test-user"; _ghcr_pat="test-pat"; }
}

@test "e2e_verify_vcluster is a public function (no leading underscore)" {
  run declare -f e2e_verify_vcluster
  [ "$status" -eq 0 ]
  [[ "$BATS_TEST_DESCRIPTION" != _* ]]
}

@test "e2e.sh sources cleanly under set -euo pipefail" {
  run bash -c '
    set -euo pipefail
    SCRIPT_DIR=scripts
    _err(){ return 1; }; _info(){ :; }; _warn(){ :; }; _run_command(){ :; }
    source scripts/plugins/e2e.sh
    declare -f e2e_verify_vcluster >/dev/null
  '
  [ "$status" -eq 0 ]
}

@test "job manifest sets exactly the three ClusterIP service URLs and OAUTH2 disabled" {
  run _e2e_job_manifest "e2e-run-123" "ghcr.io/wilddog64/shopping-cart-e2e-tests:latest"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRODUCT_CATALOG_URL"* ]]
  [[ "$output" == *"http://product-catalog.shopping-cart-apps.svc:8000"* ]]
  [[ "$output" == *"http://basket.shopping-cart-apps.svc:8083"* ]]
  [[ "$output" == *"http://order.shopping-cart-apps.svc:8080"* ]]
  [[ "$output" == *"OAUTH2_ENABLED"* ]]
  [[ "$output" == *'value: "false"'* ]]
  [[ "$output" == *"restartPolicy: Never"* ]]
  [[ "$output" == *"backoffLimit: 0"* ]]
  [[ "$output" == *"name: ghcr-pull-secret"* ]]
}

@test "substrate bundle is applied via kustomize (-k scripts/etc/e2e)" {
  _e2e_wait_job() { return 0; }
  local rc=0
  ( e2e_verify_vcluster ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
  run grep -F -- "apply -k" "$RUN_LOG"
  [ "$status" -eq 0 ]
  run grep -F -- "etc/e2e" "$RUN_LOG"
  [ "$status" -eq 0 ]
}

@test "successful job -> exit 0 and vcluster torn down" {
  _e2e_wait_job() { return 0; }
  local rc=0
  ( e2e_verify_vcluster ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
  run grep -F -- "vcluster_destroy e2e-" "$VC_LOG"
  [ "$status" -eq 0 ]
}

@test "failed job -> non-zero exit but vcluster still torn down (teardown on failure)" {
  _e2e_wait_job() { return 1; }
  local rc=0
  ( e2e_verify_vcluster ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
  run grep -F -- "vcluster_destroy e2e-" "$VC_LOG"
  [ "$status" -eq 0 ]
}

@test "a JSON summary with the gate-consumable keys is written" {
  _e2e_wait_job() { return 0; }
  local rc=0
  ( e2e_verify_vcluster ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
  run bash -c 'ls "$E2E_REPORT_DIR"/*.json'
  [ "$status" -eq 0 ]
  local summary
  summary="$(ls "$E2E_REPORT_DIR"/*.json | head -1)"
  run grep -F -- '"tier": "vcluster"' "$summary"
  [ "$status" -eq 0 ]
  run grep -F -- '"result": "pass"' "$summary"
  [ "$status" -eq 0 ]
  run grep -F -- '"exit_code": 0' "$summary"
  [ "$status" -eq 0 ]
  run grep -F -- '"run_id"' "$summary"
  [ "$status" -eq 0 ]
}

@test "failed job summary is exit-code-faithful (result fail, non-zero exit_code)" {
  _e2e_wait_job() { return 1; }
  local rc=0
  ( e2e_verify_vcluster ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
  local summary
  summary="$(ls "$E2E_REPORT_DIR"/*.json | head -1)"
  run grep -F -- '"result": "fail"' "$summary"
  [ "$status" -eq 0 ]
}

@test "vCluster readiness gate probes /readyz before applying the substrate" {
  _e2e_wait_job() { return 0; }
  local rc=0
  ( e2e_verify_vcluster ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
  local readyz_line apply_line
  readyz_line="$(grep -nF -- "get --raw=/readyz" "$RUN_LOG" | head -1 | cut -d: -f1)"
  apply_line="$(grep -nF -- "apply -k" "$RUN_LOG" | head -1 | cut -d: -f1)"
  [ -n "$readyz_line" ]
  [ -n "$apply_line" ]
  [ "$readyz_line" -lt "$apply_line" ]
}

@test "readiness gate honours E2E_VCLUSTER_READY_TIMEOUT and fails when never ready" {
  export E2E_VCLUSTER_READY_TIMEOUT=1
  _run_command() { echo "$*" >> "$RUN_LOG"; return 1; }
  local rc=0
  ( _e2e_wait_vcluster_ready "$BATS_TEST_TMPDIR/kc" ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
  run grep -F -- "get --raw=/readyz" "$RUN_LOG"
  [ "$status" -eq 0 ]
}

@test "readiness gate refreshes the proxy connection between failed probes" {
  export E2E_VCLUSTER_READY_TIMEOUT=1
  _run_command() { echo "$*" >> "$RUN_LOG"; return 1; }
  local refresh_log="$BATS_TEST_TMPDIR/refresh.log"
  _vcluster_refresh_connection() { echo "refresh $*" >> "$refresh_log"; }
  local rc=0
  ( _e2e_wait_vcluster_ready "$BATS_TEST_TMPDIR/kc" "e2e-demo" ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
  run grep -F -- "refresh e2e-demo" "$refresh_log"
  [ "$status" -eq 0 ]
}

@test "result event ConfigMap carries the e2e-result labels and a boolean passed field" {
  if ! command -v python3 >/dev/null 2>&1; then skip "python3 not installed"; fi
  mkdir -p "$E2E_REPORT_DIR"
  cat > "$E2E_REPORT_DIR/testrun.json" <<'JSON'
{"run_id":"testrun","tier":"vcluster","service":"product-catalog","project":"api+flows","candidate_digest":null,"passed":6,"total":6,"failed":0,"duration_seconds":12.3,"timestamp":"2026-08-16T00:00:00+00:00","commit":"abc123","exit_code":0,"result":"pass"}
JSON
  local capture="$BATS_TEST_TMPDIR/event-manifest.json"
  _kubectl() {
    if [[ "$1" == "create" && "$2" == "-f" ]]; then cp "$3" "$capture"; return 0; fi
    return 0
  }
  run _e2e_write_result_event "testrun"
  [ "$status" -eq 0 ]
  [ -f "$capture" ]
  run python3 - "$capture" <<'PY'
import sys, json
m = json.load(open(sys.argv[1]))
assert m["kind"] == "ConfigMap"
assert m["metadata"]["generateName"] == "e2e-result-"
assert m["metadata"]["namespace"] == "platform-ops"
labels = m["metadata"]["labels"]
assert labels["k3dm.k3d.io/e2e-result"] == "true"
assert labels["k3dm.k3d.io/e2e-service"] == "product-catalog"
assert labels["k3dm.k3d.io/e2e-tier"] == "vcluster"
event = json.loads(m["data"]["event.json"])
assert event["passed"] == "true", event["passed"]
assert event["service"] == "product-catalog"
assert event["tier"] == "vcluster"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "failed run publishes passed=false in the result event" {
  if ! command -v python3 >/dev/null 2>&1; then skip "python3 not installed"; fi
  mkdir -p "$E2E_REPORT_DIR"
  cat > "$E2E_REPORT_DIR/failrun.json" <<'JSON'
{"run_id":"failrun","tier":"vcluster","service":"product-catalog","project":"api+flows","candidate_digest":null,"passed":4,"total":6,"failed":2,"duration_seconds":9.0,"timestamp":"2026-08-16T00:00:00+00:00","commit":"def456","exit_code":1,"result":"fail"}
JSON
  local capture="$BATS_TEST_TMPDIR/fail-manifest.json"
  _kubectl() {
    if [[ "$1" == "create" && "$2" == "-f" ]]; then cp "$3" "$capture"; return 0; fi
    return 0
  }
  run _e2e_write_result_event "failrun"
  [ "$status" -eq 0 ]
  run python3 - "$capture" <<'PY'
import sys, json
m = json.load(open(sys.argv[1]))
assert json.loads(m["data"]["event.json"])["passed"] == "false"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "missing summary -> writer is a no-op that does not fail the run" {
  run _e2e_write_result_event "does-not-exist"
  [ "$status" -eq 0 ]
}

@test "e2e.sh passes shellcheck at warning severity" {
  if ! command -v shellcheck >/dev/null 2>&1; then
    skip "shellcheck not installed"
  fi
  run shellcheck -S warning -x "${BATS_TEST_DIRNAME}/../../plugins/e2e.sh"
  [ "$status" -eq 0 ]
}
