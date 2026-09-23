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
  export E2E_VCLUSTER_READY_REFRESH_INTERVAL=0
  export E2E_STRIPE_SECRET_KEY=test-stripe-key

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

@test "e2e_verify_sandbox is a public function (no leading underscore)" {
  run declare -f e2e_verify_sandbox
  [ "$status" -eq 0 ]
  [[ "$BATS_TEST_DESCRIPTION" != _* ]]
}

@test "sandbox verification never invokes register_app_cluster" {
  local marker="$BATS_TEST_TMPDIR/register-app-cluster-called"
  acg_extend_playwright() { :; }
  shopping_cart_create_vault_bridge() { :; }
  _e2e_sandbox_kc() { :; }
  _e2e_sandbox_wait_job() { :; }
  _e2e_sandbox_job_manifest() { :; }
  _e2e_write_summary() { :; }
  _e2e_write_result_event() { :; }
  register_app_cluster() { : > "$marker"; return 1; }
  local rc=0
  ( e2e_verify_sandbox ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
  [ ! -e "$marker" ]
}

@test "sandbox job manifest exports OAuth2 and Stripe mode before Job creation" {
  run _e2e_sandbox_job_manifest "sandbox-run-123" "ghcr.io/wilddog64/shopping-cart-e2e-tests:latest"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'name: OAUTH2_ENABLED\n              value: "true"'* ]]
  [[ "$output" == *$'name: STRIPE_E2E\n              value: "true"'* ]]
  [[ "$output" == *"KEYCLOAK_URL"*"https://keycloak.3ai-talk.org/realms/shopping-cart"* ]]
  [[ "$output" == *"stripe-checkout-orchestrator.spec.ts"* ]]
}

@test "sandbox Job uses the real Tier 2 Service hostnames" {
  run _e2e_sandbox_job_manifest "sandbox-run-123" "ghcr.io/wilddog64/shopping-cart-e2e-tests:latest"
  [ "$status" -eq 0 ]
  [[ "$output" == *"http://basket-service.shopping-cart-apps.svc:8083"* ]]
  [[ "$output" == *"http://order-service.shopping-cart-apps.svc:8081"* ]]
  [[ "$output" == *"http://payment-service.shopping-cart-payment.svc:8084"* ]]
  [[ "$output" != *"http://basket.shopping-cart-apps.svc:"* ]]
  [[ "$output" != *"http://order.shopping-cart-apps.svc:"* ]]
  [[ "$output" != *"http://payment.shopping-cart-payment.svc:"* ]]
}

@test "sandbox Job preserves all four service ports" {
  run _e2e_sandbox_job_manifest "sandbox-run-123" "ghcr.io/wilddog64/shopping-cart-e2e-tests:latest"
  [ "$status" -eq 0 ]
  [[ "$output" == *"product-catalog.shopping-cart-apps.svc:8082"* ]]
  [[ "$output" == *"basket-service.shopping-cart-apps.svc:8083"* ]]
  [[ "$output" == *"order-service.shopping-cart-apps.svc:8081"* ]]
  [[ "$output" == *"payment-service.shopping-cart-payment.svc:8084"* ]]
}

@test "sandbox Job command emits result markers and preserves Playwright status" {
  run _e2e_sandbox_job_manifest "sandbox-run-123" "ghcr.io/wilddog64/shopping-cart-e2e-tests:latest"
  [ "$status" -eq 0 ]
  [[ "$output" == *"__E2E_RESULTS_BEGIN__"* ]]
  [[ "$output" == *"__E2E_RESULTS_END__"* ]]
  [[ "$output" == *'rc=$?'* ]]
  [[ "$output" == *'exit $rc'* ]]
}

@test "sandbox summary parser extracts marked Playwright results" {
  local run_id="sandbox-marked-summary"
  cat > "$E2E_REPORT_DIR/${run_id}.log" <<'EOF'
__E2E_RESULTS_BEGIN__
{"stats":{"expected":4,"unexpected":1,"flaky":0,"skipped":0,"duration":1250}}
__E2E_RESULTS_END__
EOF
  run _e2e_write_summary "$run_id" "" 1 "running-playwright"
  [ "$status" -eq 0 ]
  run python3 - "$E2E_REPORT_DIR/${run_id}.json" <<'PY'
import json, sys
summary = json.load(open(sys.argv[1]))
assert summary["passed"] == 4, summary
assert summary["total"] == 5, summary
assert summary["failed"] == 1, summary
print("marked parser ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"marked parser ok"* ]]
}

@test "sandbox preflight creates both Secrets before completion" {
  local calls="$BATS_TEST_TMPDIR/sandbox-preflight-calls"
  : > "$calls"
  _e2e_sandbox_kc() {
    printf '%s\n' "$*" >> "$calls"
    case "$*" in
      *"create namespace"*) printf 'namespace-manifest\n' ;;
      *"create secret docker-registry"*) printf 'ghcr-manifest\n' ;;
      *"create secret generic stripe-e2e"*) cat >/dev/null; printf 'stripe-manifest\n' ;;
      *"apply -f -"*) cat >/dev/null ;;
    esac
  }
  run _e2e_sandbox_provision_secrets
  [ "$status" -eq 0 ]
  run awk '/create secret docker-registry ghcr-pull-secret/{ghcr=NR} /create secret generic stripe-e2e/{stripe=NR} END{exit !(ghcr && stripe && ghcr < stripe)}' "$calls"
  [ "$status" -eq 0 ]
}

@test "sandbox preflight is idempotent" {
  _e2e_sandbox_kc() {
    case "$*" in
      *"create namespace"*|*"create secret docker-registry"*|*"create secret generic stripe-e2e"*)
        [[ "$*" == *"--dry-run=client -o yaml"* ]] || return 1
        ;;
    esac
    case "$*" in
      *"create secret generic stripe-e2e"*) cat >/dev/null; printf 'stripe-manifest\n' ;;
      *"apply -f -"*) cat >/dev/null ;;
    esac
  }
  run _e2e_sandbox_provision_secrets
  [ "$status" -eq 0 ]
  run _e2e_sandbox_provision_secrets
  [ "$status" -eq 0 ]
}

@test "sandbox preflight rejects a missing Stripe Keychain item" {
  unset E2E_STRIPE_SECRET_KEY
  security() { return 1; }
  _warn() { printf '%s\n' "$*"; }
  run _e2e_sandbox_provision_secrets
  [ "$status" -ne 0 ]
  [[ "$output" == *"k3dm-stripe-sk-test is missing"* ]]
}

@test "sandbox preflight never places the Stripe key in kubectl argv" {
  local calls="$BATS_TEST_TMPDIR/sandbox-secret-argv"
  : > "$calls"
  _e2e_sandbox_kc() {
    printf '%s\n' "$*" >> "$calls"
    case "$*" in
      *"create secret generic stripe-e2e"*) cat >/dev/null; printf 'stripe-manifest\n' ;;
      *"apply -f -"*) cat >/dev/null ;;
    esac
  }
  run _e2e_sandbox_provision_secrets
  [ "$status" -eq 0 ]
  run grep -F -- "test-stripe-key" "$calls"
  [ "$status" -ne 0 ]
}

@test "sandbox rendered overrides contain the three substrate changes" {
  run _e2e_sandbox_render_overrides
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: order-service-config"*"BASKET_URL: http://basket-service.shopping-cart-apps:8083"* ]]
  [[ "$output" == *"PAYMENT_URL: http://payment-service.shopping-cart-payment:8084"* ]]
  [[ "$output" == *"payment.gateway.default: stripe"*"mock.gateway.enabled: \"false\""* ]]
  [[ "$output" == *"oauth2.jwk-set-uri: https://keycloak.3ai-talk.org/realms/shopping-cart/protocol/openid-connect/certs"* ]]
}

@test "sandbox summary carries the sandbox tier and Stripe project" {
  local run_id="sandbox-summary"
  printf 'no Playwright results here\n' > "$E2E_REPORT_DIR/${run_id}.log"
  export E2E_TIER=sandbox E2E_PROJECT=stripe
  run _e2e_write_summary "$run_id" "" 0 "recording-result"
  [ "$status" -eq 0 ]
  run python3 - "$E2E_REPORT_DIR/${run_id}.json" <<'PY'
import json, sys
summary = json.load(open(sys.argv[1]))
assert summary["tier"] == "sandbox", summary
assert summary["project"] == "stripe", summary
assert summary["exit_code"] == 0, summary
print("sandbox summary ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"sandbox summary ok"* ]]
}

@test "Tier 1 summary defaults remain vcluster and api+flows" {
  local run_id="tier1-summary"
  unset E2E_TIER E2E_PROJECT
  printf 'no Playwright results here\n' > "$E2E_REPORT_DIR/${run_id}.log"
  run _e2e_write_summary "$run_id" "" 0 "recording-result"
  [ "$status" -eq 0 ]
  run python3 - "$E2E_REPORT_DIR/${run_id}.json" <<'PY'
import json, sys
summary = json.load(open(sys.argv[1]))
assert summary["tier"] == "vcluster", summary
assert summary["project"] == "api+flows", summary
print("Tier 1 summary unchanged")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"Tier 1 summary unchanged"* ]]
}

@test "sandbox port attribution covers order 8081 and product-catalog 8082" {
  local run_id="sandbox-ports"
  cat > "$E2E_REPORT_DIR/${run_id}.log" <<'EOF'
__E2E_RESULTS_BEGIN__
{"stats":{"expected":0,"unexpected":2,"flaky":0,"skipped":0},"suites":[{"file":"flows/stripe.spec.ts","specs":[{"title":"order :8081 ECONNREFUSED","tests":[{"results":[{"status":"failed","error":"connect ECONNREFUSED 10.0.0.1:8081"}]}]},{"title":"product :8082 ECONNREFUSED","tests":[{"results":[{"status":"failed","error":"connect ECONNREFUSED 10.0.0.2:8082"}]}]}]}]}
__E2E_RESULTS_END__
EOF
  run _e2e_write_summary "$run_id" "" 1 "running-playwright"
  [ "$status" -eq 0 ]
  run python3 - "$E2E_REPORT_DIR/${run_id}.json" <<'PY'
import json, sys
summary = json.load(open(sys.argv[1]))
groups = {(item["kind"], item["target"]) for item in summary["failure_groups"]}
assert ("service-unreachable", "order") in groups, groups
assert ("service-unreachable", "product-catalog") in groups, groups
print("port attribution ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"port attribution ok"* ]]
}

@test "failure groups carry routed services" {
  local run_id="routed-services"
  cat > "$E2E_REPORT_DIR/${run_id}.log" <<'EOF'
__E2E_RESULTS_BEGIN__
{"stats":{"expected":0,"unexpected":2,"flaky":0,"skipped":0},"suites":[{"file":"api/cart.spec.ts","specs":[{"title":"cart contract","tests":[{"results":[{"status":"failed","error":"Received: undefined"}]}]}]},{"file":"api/orders.spec.ts","specs":[{"title":"order contract","tests":[{"results":[{"status":"failed","error":"Received: undefined"}]}]}]}]}
__E2E_RESULTS_END__
EOF
  run _e2e_write_summary "$run_id" "" 1 "running-playwright"
  [ "$status" -eq 0 ]
  run python3 - "$E2E_REPORT_DIR/${run_id}.json" <<'PY'
import json, sys
summary = json.load(open(sys.argv[1]))
services = {item["target"]: item["service"] for item in summary["failure_groups"]}
assert services == {"api-cart": "basket", "api-orders": "order"}, services
print("routed services ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"routed services ok"* ]]
}

@test "failure details are redacted in summary and failures file" {
  local run_id="redacted-summary"
  cat > "$E2E_REPORT_DIR/${run_id}.log" <<'EOF'
__E2E_RESULTS_BEGIN__
{"stats":{"expected":0,"unexpected":1,"flaky":0,"skipped":0},"suites":[{"file":"api/payments.spec.ts","specs":[{"title":"auth Bearer sk_test_FAKEFAKEFAKE","tests":[{"results":[{"status":"failed","error":"Authorization: Bearer sk_test_FAKEFAKEFAKE"}]}]}]}]}
__E2E_RESULTS_END__
EOF
  run _e2e_write_summary "$run_id" "" 1 "running-playwright"
  [ "$status" -eq 0 ]
  run grep -E '(<redacted>|sk_test_FAKEFAKEFAKE)' "$E2E_REPORT_DIR/${run_id}.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<redacted>"* ]]
  [[ "$output" != *"sk_test_FAKEFAKEFAKE"* ]]
  run grep -E '(<redacted>|sk_test_FAKEFAKEFAKE)' "$E2E_REPORT_DIR/${run_id}.failures.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<redacted>"* ]]
  [[ "$output" != *"sk_test_FAKEFAKEFAKE"* ]]
}

@test "auth classification survives the bash summary path" {
  local run_id="auth-summary"
  cat > "$E2E_REPORT_DIR/${run_id}.log" <<'EOF'
__E2E_RESULTS_BEGIN__
{"stats":{"expected":0,"unexpected":1,"flaky":0,"skipped":0},"suites":[{"file":"api/payments.spec.ts","specs":[{"title":"payment auth","tests":[{"results":[{"status":"failed","error":"expect(received).toBe(expected) / Expected: 200 / Received: 401"}]}]}]}]}
__E2E_RESULTS_END__
EOF
  run _e2e_write_summary "$run_id" "" 1 "running-playwright"
  [ "$status" -eq 0 ]
  run grep -E '"kind": "auth"' "$E2E_REPORT_DIR/${run_id}.json"
  [ "$status" -eq 0 ]
  run grep -E '"target": "api-payments"' "$E2E_REPORT_DIR/${run_id}.json"
  [ "$status" -eq 0 ]
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

@test "job manifest sets all four ClusterIP service URLs and OAUTH2 disabled" {
  run _e2e_job_manifest "e2e-run-123" "ghcr.io/wilddog64/shopping-cart-e2e-tests:latest"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRODUCT_CATALOG_URL"* ]]
  [[ "$output" == *"http://product-catalog.shopping-cart-apps.svc:8000"* ]]
  [[ "$output" == *"http://basket.shopping-cart-apps.svc:8083"* ]]
  [[ "$output" == *"http://order.shopping-cart-apps.svc:8080"* ]]
  [[ "$output" == *"PAYMENT_URL"* ]]
  [[ "$output" == *"http://payment.shopping-cart-apps.svc:8084"* ]]
  [[ "$output" == *"OAUTH2_ENABLED"* ]]
  [[ "$output" == *'value: "false"'* ]]
  [[ "$output" == *"restartPolicy: Never"* ]]
  [[ "$output" == *"backoffLimit: 0"* ]]
  [[ "$output" == *"name: ghcr-pull-secret"* ]]
}

@test "payment is pinned in the E2E substrate kustomization" {
  local kustomization="${BATS_TEST_DIRNAME}/../../etc/e2e/kustomization.yaml"
  run awk '$1 == "-" && $2 == "payment.yaml" { found=1 } END { exit (found ? 0 : 1) }' "$kustomization"
  [ "$status" -eq 0 ]
  run awk '
    $1 == "-" && $2 == "name:" && $3 == "shopping-cart-payment" { payment=1 }
    payment && $1 == "newName:" && $2 == "ghcr.io/wilddog64/shopping-cart-payment" { image=1 }
    payment && $1 == "newTag:" && $2 ~ /^sha-/ { tag=1 }
    END { exit (payment && image && tag ? 0 : 1) }
  ' "$kustomization"
  [ "$status" -eq 0 ]
}

@test "substrate image inventory includes the pinned payment image" {
  run _e2e_substrate_images "${BATS_TEST_DIRNAME}/../../etc/e2e"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghcr.io/wilddog64/shopping-cart-payment:sha-"* ]]
}

@test "datastore secret includes a payment encryption key without echoing it" {
  export E2E_PAYMENT_ENCRYPTION_KEY="payment-key-not-echoed"
  run _e2e_provision_datastore_secret "$BATS_TEST_TMPDIR/kubeconfig"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$E2E_PAYMENT_ENCRYPTION_KEY"* ]]
  run awk '/payment-encryption-key=payment-key-not-echoed/ { found=1 } END { exit (found ? 0 : 1) }' "$RUN_LOG"
  [ "$status" -eq 0 ]
}

@test "substrate rollout waits for payment" {
  run _e2e_deploy_substrate "$BATS_TEST_TMPDIR/kubeconfig"
  [ "$status" -eq 0 ]
  run awk '/rollout status deployment\/payment/ { found=1 } END { exit (found ? 0 : 1) }' "$RUN_LOG"
  [ "$status" -eq 0 ]
}

@test "payment substrate renders offline" {
  if command -v kubectl >/dev/null 2>&1; then :; else skip "kubectl not installed"; fi
  run env kubectl kustomize "${BATS_TEST_DIRNAME}/../../etc/e2e"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: payment"* ]]
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

@test "teardown removes orphaned kubeconfig and transient log when destroy is incomplete" {
  local name="e2e-orphaned"
  local kubeconfig="$BATS_TEST_TMPDIR/${name}.kubeconfig"
  local run_id="orphaned-run"
  touch "$kubeconfig" "$E2E_REPORT_DIR/${run_id}.log"
  vcluster_destroy() { return 1; }
  _vcluster_remove_proxy() { echo "proxy_removed $*" >> "$VC_LOG"; }
  _run_command() {
    while [[ "$1" == --* ]]; do shift; done
    [[ "$1" == -- ]] && shift
    "$@"
  }
  export _E2E_RUN_ID="$run_id"
  run _e2e_teardown "$name"
  [ "$status" -eq 0 ]
  [ ! -f "$kubeconfig" ]
  [ ! -f "$E2E_REPORT_DIR/${run_id}.log" ]
  run grep -F -- "proxy_removed ${name}" "$VC_LOG"
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
  summary="$(ls "$E2E_REPORT_DIR"/*.json | grep -vE '\.failures\.json$' | head -1)"
  run grep -F -- '"tier": "vcluster"' "$summary"
  [ "$status" -eq 0 ]
  run grep -F -- '"result": "pass"' "$summary"
  [ "$status" -eq 0 ]
  run grep -F -- '"exit_code": 0' "$summary"
  [ "$status" -eq 0 ]
  run grep -F -- '"run_id"' "$summary"
  [ "$status" -eq 0 ]
  run grep -F -- '"runner": "local-m4"' "$summary"
  [ "$status" -eq 0 ]
}

@test "E2E_RUNNER overrides the default runner in the summary" {
  _e2e_wait_job() { return 0; }
  export E2E_RUNNER=m2
  local rc=0
  ( e2e_verify_vcluster ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
  local summary
  summary="$(ls "$E2E_REPORT_DIR"/*.json | grep -vE '\.failures\.json$' | head -1)"
  run grep -F -- '"runner": "m2"' "$summary"
  [ "$status" -eq 0 ]
}

@test "failed job summary is exit-code-faithful (result fail, non-zero exit_code)" {
  _e2e_wait_job() { return 1; }
  local rc=0
  ( e2e_verify_vcluster ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
  local summary
  summary="$(ls "$E2E_REPORT_DIR"/*.json | grep -vE '\.failures\.json$' | head -1)"
  run grep -F -- '"result": "fail"' "$summary"
  [ "$status" -eq 0 ]
}

@test "summary writes a bounded ANSI-stripped failure sidecar from nested results" {
  local run_id="123-456"
  cat > "$E2E_REPORT_DIR/${run_id}.log" <<'EOF'
__E2E_RESULTS_BEGIN__
{"stats":{"expected":1,"unexpected":3,"flaky":0,"skipped":0},"suites":[{"file":"api/cart.spec.ts","specs":[{"title":"adds cart item","tests":[{"results":[{"status":"failed","error":{"message":"\u001b[31mfirst line\u001b[0m\nsecond line\nthird line\nfourth line"}}]},{"results":[{"status":"passed"},{"status":"timedOut","error":{"message":"timeout"}}]}] }],"suites":[{"file":"api/nested.spec.ts","specs":[{"title":"nested failure","tests":[{"results":[{"status":"failed","error":{"message":"nested"}}]}]}]}]}]}
__E2E_RESULTS_END__
EOF
  run _e2e_write_summary "$run_id" "" 1 "running-playwright"
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
assert len(d)==3, d
assert [x["status"] for x in d]==["failed","timedOut","failed"], d
assert d[0]["file"]=="api/cart.spec.ts", d[0]
assert d[0]["error"]=="first line / second line / third line", d[0]
assert all(len(x["error"])<=300 for x in d), d
print("ok")' "$E2E_REPORT_DIR/${run_id}.failures.json"
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
assert set(d)=={"run_id","tier","runner","service","candidate_digest","project","passed","total","failed","duration_seconds","timestamp","commit","exit_code","phase","result","failure_groups","failure_details"}, d
print("ok")' "$E2E_REPORT_DIR/${run_id}.json"
  [ "$status" -eq 0 ]
}

@test "summary writes an empty failure sidecar when results are missing" {
  local run_id="234-567"
  printf 'no Playwright results here\n' > "$E2E_REPORT_DIR/${run_id}.log"
  run _e2e_write_summary "$run_id" "" 1 "running-playwright"
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))==[]; print("ok")' "$E2E_REPORT_DIR/${run_id}.failures.json"
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

@test "readiness gate always probes at least once even if the deadline has already passed" {
  export E2E_VCLUSTER_READY_TIMEOUT=1
  local date_state="$BATS_TEST_TMPDIR/date.calls"
  date() {
    if [[ -e "$date_state" ]]; then echo 101; else : > "$date_state"; echo 100; fi
  }
  _run_command() { echo "$*" >> "$RUN_LOG"; return 1; }
  local rc=0
  ( _e2e_wait_vcluster_ready "$BATS_TEST_TMPDIR/kc" ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
  run grep -F -- "get --raw=/readyz" "$RUN_LOG"
  [ "$status" -eq 0 ]
}

@test "readiness probe is soft (--no-exit) so a not-ready probe cannot exit the harness" {
  export E2E_VCLUSTER_READY_TIMEOUT=1
  local probe_log="$BATS_TEST_TMPDIR/probe.log"
  _run_command() {
    echo "$*" >> "$probe_log"
    local a soft=0
    for a in "$@"; do [[ "$a" == "--no-exit" || "$a" == "--soft" ]] && soft=1; done
    if (( soft )); then return 1; fi
    exit 99
  }
  local rc=0
  ( _e2e_wait_vcluster_ready "$BATS_TEST_TMPDIR/kc" "e2e-demo" ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 99 ]
  run grep -F -- "--no-exit" "$probe_log"
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
    while [[ "$1" == --* ]]; do shift; done
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
assert labels["k3dm.k3d.io/e2e-runner"] == "local-m4", labels.get("k3dm.k3d.io/e2e-runner")
event = json.loads(m["data"]["event.json"])
assert event["passed"] == "true", event["passed"]
assert event["service"] == "product-catalog"
assert event["tier"] == "vcluster"
assert event["runner"] == "local-m4", event.get("runner")
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "result event carries the runner label/field from the summary" {
  if ! command -v python3 >/dev/null 2>&1; then skip "python3 not installed"; fi
  mkdir -p "$E2E_REPORT_DIR"
  cat > "$E2E_REPORT_DIR/m2run.json" <<'JSON'
{"run_id":"m2run","tier":"vcluster","runner":"m2","service":"product-catalog","project":"api+flows","candidate_digest":null,"passed":6,"total":6,"failed":0,"duration_seconds":12.3,"timestamp":"2026-08-16T00:00:00+00:00","commit":"abc123","exit_code":0,"result":"pass"}
JSON
  local capture="$BATS_TEST_TMPDIR/m2-manifest.json"
  _kubectl() {
    while [[ "$1" == --* ]]; do shift; done
    if [[ "$1" == "create" && "$2" == "-f" ]]; then cp "$3" "$capture"; return 0; fi
    return 0
  }
  run _e2e_write_result_event "m2run"
  [ "$status" -eq 0 ]
  [ -f "$capture" ]
  run python3 - "$capture" <<'PY'
import sys, json
m = json.load(open(sys.argv[1]))
assert m["metadata"]["labels"]["k3dm.k3d.io/e2e-runner"] == "m2"
event = json.loads(m["data"]["event.json"])
assert event["runner"] == "m2", event.get("runner")
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
    while [[ "$1" == --* ]]; do shift; done
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

@test "result event publish passes --no-exit so a hub failure cannot exit the shell" {
  mkdir -p "$E2E_REPORT_DIR"
  cat > "$E2E_REPORT_DIR/flagrun.json" <<'JSON'
{"run_id":"flagrun","tier":"vcluster","service":"product-catalog","passed":1,"total":1,"failed":0,"exit_code":0,"result":"pass"}
JSON
  local seen="$BATS_TEST_TMPDIR/kubectl-flags"
  _kubectl() { printf '%s\n' "$*" > "$seen"; return 0; }
  run _e2e_write_result_event "flagrun"
  [ "$status" -eq 0 ]
  run grep -F -- "--no-exit" "$seen"
  [ "$status" -eq 0 ]
}

@test "result event prune passes --no-exit so a hub failure cannot exit the shell" {
  local seen="$BATS_TEST_TMPDIR/prune-flags"
  _kubectl() { printf '%s\n' "$*" >> "$seen"; return 0; }
  run _e2e_prune_result_events
  [ "$status" -eq 0 ]
  run grep -F -- "--no-exit" "$seen"
  [ "$status" -eq 0 ]
}

# Regression guard for the vCluster leak: the publish step talks to the hub, which is
# unreachable from the m2 runner, and _run_command ends an unguarded failure with exit 1.
# An exit there used to kill the EXIT trap before teardown, stranding the vCluster and
# wedging every later run. Teardown must therefore come first. The stub exits rather than
# returning non-zero because `|| true` cannot catch an exit — which is exactly why the
# original defect was invisible.
@test "exit trap tears down the vCluster even when the result event publish exits the shell" {
  _e2e_deploy_substrate() { exit 1; }
  _e2e_write_result_event() { exit 9; }
  local rc=0
  ( e2e_verify_vcluster ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
  run grep -F -- "vcluster_destroy e2e-" "$VC_LOG"
  [ "$status" -eq 0 ]
}

@test "exit trap writes the summary before the teardown that precedes the publish" {
  _e2e_deploy_substrate() { exit 1; }
  _e2e_write_result_event() { exit 9; }
  local rc=0
  ( e2e_verify_vcluster ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
  run bash -c 'ls "$1"/*.json' _ "$E2E_REPORT_DIR"
  [ "$status" -eq 0 ]
}
