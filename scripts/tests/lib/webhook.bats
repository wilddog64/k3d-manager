#!/usr/bin/env bats
# shellcheck shell=bash
# scripts/tests/lib/webhook.bats — k3dm-webhook unit and live e2e tests
#
# Guard env vars:
#   K3DM_WEBHOOK_LIVE=1    enable Level 1 (localhost, no cluster)
#   K3DM_WEBHOOK_LEVEL2=1  enable Level 2 (idempotency, cluster required)
#   K3DM_WEBHOOK_LEVEL3=1  enable Level 3 (Cloudflare tunnel required)
#   K3DM_WEBHOOK_LEVEL3_TOKEN   real Bearer token for Level 3 POST test

_WEBHOOK_PORT=17443
_WEBHOOK_URL="http://127.0.0.1:${_WEBHOOK_PORT}"
_TUNNEL_URL="https://webhook.3ai-talk.org"

setup_file() {
    export K3DM_WEBHOOK_TOKEN
    K3DM_WEBHOOK_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
    export K3DM_WEBHOOK_PORT="${_WEBHOOK_PORT}"

    # Stub the analysis binary so queued /analyze and /diagnostics jobs cannot
    # spawn the real agy CLI (which launches Chrome via ACG browser automation).
    export K3DM_GEMINI_BIN="/usr/bin/true"

    # Stub make so queued /cluster jobs cannot run the real make up/down, which
    # for the aws/gcp providers drives acg_extend_playwright -> Chromium (Chrome).
    # _posix_spawn_job runs `bash -c "cd REPO && make ..."`, resolving make from
    # PATH, so a no-op stub on PATH neutralizes every live cluster job.
    export _BATS_STUB_BIN
    _BATS_STUB_BIN="$(mktemp -d)"
    printf '#!/bin/sh\nexit 0\n' > "${_BATS_STUB_BIN}/make"
    chmod +x "${_BATS_STUB_BIN}/make"
    # Stub kubectl so the queued /cluster "up" success path's _record_acg_state
    # (kubectl create configmap | kubectl apply) returns instantly. On CI runners
    # kubectl exists but no cluster is reachable, so the real apply blocks up to
    # the 15s _posix_spawn_capture timeout, holding the job "running" and 409ing
    # the next /cluster test.
    printf '#!/bin/sh\nexit 0\n' > "${_BATS_STUB_BIN}/kubectl"
    chmod +x "${_BATS_STUB_BIN}/kubectl"
    export PATH="${_BATS_STUB_BIN}:${PATH}"

    # Isolate job/run dirs so queued /cluster jobs never write into the live
    # :7443 instance's dir. Without this, a job left "running" when teardown_file
    # kills the webhook is orphaned in the live dir and fires a false Slack
    # "cluster-<action> orphaned" alert on the next live webhook restart.
    export K3DM_JOB_DIR K3DM_RUN_DIR
    K3DM_JOB_DIR="$(mktemp -d)"
    K3DM_RUN_DIR="$(mktemp -d)"

    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    python3 "${REPO_ROOT}/bin/k3dm-webhook" &
    export _BATS_WEBHOOK_PID=$!

    local i=0
    while (( i < 10 )); do
        curl -s -o /dev/null "http://127.0.0.1:${_WEBHOOK_PORT}/" && break
        sleep 0.3
        (( i++ )) || true
    done
}

teardown_file() {
    [[ -n "${_BATS_WEBHOOK_PID:-}" ]] && kill "${_BATS_WEBHOOK_PID}" 2>/dev/null || true
    [[ -n "${_BATS_STUB_BIN:-}" ]] && rm -rf "${_BATS_STUB_BIN}" || true
    [[ -n "${K3DM_JOB_DIR:-}" ]] && rm -rf "${K3DM_JOB_DIR}" || true
    [[ -n "${K3DM_RUN_DIR:-}" ]] && rm -rf "${K3DM_RUN_DIR}" || true
}

# Wait until no cluster up/down job is still marked "running" in JOB_DIR.
# A queued "up" job stays "running" until _run_cluster's success path finishes
# _record_acg_state and _finish; on a fast host consecutive /cluster tests can
# fire before the prior job clears, and the handler answers 409 (cluster job
# already running) instead of 202 queued. Waiting here makes the sequence
# deterministic regardless of that timing (mirrors _running_cluster_job).
_wait_cluster_idle() {
    local i=0 s
    while (( i < 100 )); do
        local running=0
        for s in "${K3DM_JOB_DIR}"/*/status; do
            [[ -f "$s" ]] || continue
            if [[ "$(cat "$s" 2>/dev/null)" == "running" && -f "${s%/status}/action" ]]; then
                running=1
                break
            fi
        done
        (( running == 0 )) && return 0
        sleep 0.1
        (( i++ )) || true
    done
    return 0
}

setup() {
    _wait_cluster_idle
}

# ── Unit / black-box HTTP tests ────────────────────────────────────────────────

@test "POST with wrong token returns 401" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer wrongtoken" \
        -H "Content-Type: application/json" \
        -d '{"chart_version":"7.8.2","stage":"acg"}' \
        "${_WEBHOOK_URL}/api/v1/argocd-upgrade"
    [ "$status" -eq 0 ]
    [ "$output" = "401" ]
}

@test "POST with no auth header returns 401" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d '{"chart_version":"7.8.2","stage":"acg"}' \
        "${_WEBHOOK_URL}/api/v1/argocd-upgrade"
    [ "$status" -eq 0 ]
    [ "$output" = "401" ]
}

@test "POST with correct token returns 202 and job_id" {
    run curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"chart_version":"7.8.2","stage":"infra"}' \
        "${_WEBHOOK_URL}/api/v1/argocd-upgrade"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"queued"'* ]]
    [[ "$output" == *'"job_id"'* ]]
}

@test "POST body over 4KB returns 413" {
    local big_body
    big_body="$(python3 -c 'print("{\"chart_version\":\"" + "x"*5000 + "\",\"stage\":\"acg\"}")')"
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${big_body}" \
        "${_WEBHOOK_URL}/api/v1/argocd-upgrade"
    [ "$status" -eq 0 ]
    [ "$output" = "413" ]
}

@test "GET /status with invalid job_id (not hex8) returns 400" {
    run curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        "${_WEBHOOK_URL}/api/v1/status/notahex8"
    [ "$status" -eq 0 ]
    [ "$output" = "400" ]
}

@test "GET /status with invalid job_id containing special chars returns 400" {
    run curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        "${_WEBHOOK_URL}/api/v1/status/../../etc"
    [ "$status" -eq 0 ]
    [ "$output" = "400" ]
}

@test "GET /status with valid hex8 job_id that does not exist returns 404" {
    run curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        "${_WEBHOOK_URL}/api/v1/status/deadbeef"
    [ "$status" -eq 0 ]
    [ "$output" = "404" ]
}

@test "GET unknown path returns 404" {
    run curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        "${_WEBHOOK_URL}/api/v1/unknown"
    [ "$status" -eq 0 ]
    [ "$output" = "404" ]
}

@test "POST with missing stage field returns 400" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"chart_version":"7.8.2"}' \
        "${_WEBHOOK_URL}/api/v1/argocd-upgrade"
    [ "$status" -eq 0 ]
    [ "$output" = "400" ]
}

@test "POST with invalid stage value returns 400" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"chart_version":"7.8.2","stage":"prod"}' \
        "${_WEBHOOK_URL}/api/v1/argocd-upgrade"
    [ "$status" -eq 0 ]
    [ "$output" = "400" ]
}

@test "POST with JSON-injection attempt in chart_version queues job safely" {
    run curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        --data-raw '{"chart_version":"7.8.2\",\"injected\":\"val","stage":"infra"}' \
        "${_WEBHOOK_URL}/api/v1/argocd-upgrade"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"queued"'* ]]
}

@test "POST /cluster with provider=gcp returns 202 and job_id" {
    run curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"action":"up","provider":"gcp"}' \
        "${_WEBHOOK_URL}/api/v1/cluster"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"queued"'* ]]
    [[ "$output" == *'"job_id"'* ]]
}

@test "POST /cluster with unknown provider defaults to aws (202)" {
    run curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"action":"up","provider":"unknown"}' \
        "${_WEBHOOK_URL}/api/v1/cluster"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"queued"'* ]]
}

@test "POST /cluster-status with correct token returns 202 and job_id" {
    run curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"response_url":""}' \
        "${_WEBHOOK_URL}/api/v1/cluster-status"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"queued"'* ]]
    [[ "$output" == *'"job_id"'* ]]
}

@test "webhook hostinger status handler accepts provider dispatch" {
    run grep -F -- 'def _run_hostinger_status(job_id, response_url, thread_ts=None, provider=None):' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]

    run grep -F -- 'target=_run_hostinger_status if provider == "hostinger" else _run_cluster_status,' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]

    run grep -F -- 'kwargs={"thread_ts": thread_ts, "provider": provider}' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]
}

@test "POST /cluster-status with wrong token returns 401" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer wrongtoken" \
        -H "Content-Type: application/json" \
        -d '{}' \
        "${_WEBHOOK_URL}/api/v1/cluster-status"
    [ "$status" -eq 0 ]
    [ "$output" = "401" ]
}

@test "POST /cluster-status with reader role returns 202" {
    run curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "X-K3DM-Role: reader" \
        -H "X-K3DM-Actor: slack:test-user:U123" \
        -H "X-K3DM-Source-Command: /cluster-status" \
        -H "Content-Type: application/json" \
        -d '{"provider":"hostinger"}' \
        "${_WEBHOOK_URL}/api/v1/cluster-status"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"queued"'* ]]
}

@test "POST /diagnostics with reader role returns 202" {
    run curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "X-K3DM-Role: reader" \
        -H "X-K3DM-Actor: slack:test-user:U123" \
        -H "X-K3DM-Source-Command: /cluster-diagnose" \
        -H "Content-Type: application/json" \
        -d '{"provider":"hostinger","action":"get-pods","namespace":"shopping-cart-apps"}' \
        "${_WEBHOOK_URL}/api/v1/diagnostics"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"queued"'* ]]
}

@test "POST /diagnostics rejects non-approved namespaces" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "X-K3DM-Role: reader" \
        -H "X-K3DM-Actor: slack:test-user:U123" \
        -H "X-K3DM-Source-Command: /cluster-diagnose" \
        -H "Content-Type: application/json" \
        -d '{"provider":"hostinger","action":"get-pods","namespace":"default"}' \
        "${_WEBHOOK_URL}/api/v1/diagnostics"
    [ "$status" -eq 0 ]
    [ "$output" = "400" ]
}

@test "POST /diagnostics ArgoCD requests must target hub" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "X-K3DM-Role: reader" \
        -H "X-K3DM-Actor: slack:test-user:U123" \
        -H "X-K3DM-Source-Command: /cluster-diagnose" \
        -H "Content-Type: application/json" \
        -d '{"provider":"hostinger","action":"get-apps"}' \
        "${_WEBHOOK_URL}/api/v1/diagnostics"
    [ "$status" -eq 0 ]
    [ "$output" = "400" ]
}

@test "POST /cluster-refresh with reader role returns 403" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "X-K3DM-Role: reader" \
        -H "X-K3DM-Actor: slack:test-user:U123" \
        -H "X-K3DM-Source-Command: /cluster-refresh" \
        -H "Content-Type: application/json" \
        -d '{"provider":"hostinger"}' \
        "${_WEBHOOK_URL}/api/v1/cluster-refresh"
    [ "$status" -eq 0 ]
    [ "$output" = "403" ]
}

@test "POST /cluster-refresh with operator role returns 202" {
    run curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "X-K3DM-Role: operator" \
        -H "X-K3DM-Actor: slack:test-user:U123" \
        -H "X-K3DM-Source-Command: /cluster-refresh" \
        -H "Content-Type: application/json" \
        -d '{"provider":"hostinger"}' \
        "${_WEBHOOK_URL}/api/v1/cluster-refresh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"queued"'* ]]
}

@test "POST /cluster up with operator role returns 403" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "X-K3DM-Role: operator" \
        -H "X-K3DM-Actor: slack:test-user:U123" \
        -H "X-K3DM-Source-Command: /cluster-up" \
        -H "Content-Type: application/json" \
        -d '{"action":"up","provider":"hostinger"}' \
        "${_WEBHOOK_URL}/api/v1/cluster"
    [ "$status" -eq 0 ]
    [ "$output" = "403" ]
}

@test "webhook remote operator access defines policy and audit log" {
    run grep -F -- '_ROLE_LEVELS = {"reader": 1, "operator": 2, "admin": 3}' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]

    run grep -F -- 'AUDIT_DIR = Path.home() / ".local" / "share" / "k3d-manager" / "audit"' "${BATS_TEST_DIRNAME}/../../../scripts/lib/webhook/config.py"
    [ "$status" -eq 0 ]

    run grep -F -- '"/api/v1/cluster-refresh": {"name": "cluster-refresh", "min_role": "operator"}' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]

    run grep -F -- 'return {"name": f"cluster-{action}", "min_role": "admin"}' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]
}

@test "webhook diagnostics endpoint is reader-scoped and namespace-guarded" {
    run grep -F -- '"/api/v1/diagnostics": {"name": "diagnostics", "min_role": "reader"}' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]

    run grep -F -- '"shopping-cart-apps",' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]

    run grep -F -- 'allowed_actions = {"get-pods", "describe-pod", "logs", "get-apps", "describe-app", "get-appsets"}' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]
}

@test "webhook analysis defaults to agy CLI instead of gemini" {
    run grep -F -- 'os.environ.get("K3DM_GEMINI_BIN", "agy")' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]

    run grep -F -- 'return "agy CLI not found — skipping AI analysis"' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]
}

@test "webhook cluster status classifies absent ACG sandboxes explicitly" {
    run grep -F -- 'def _acg_stack_probe(provider):' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]

    run grep -F -- '"status_line": "*ACG sandbox:* absent — sandbox likely expired or was torn down",' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]

    run grep -F -- 'ACG sandbox appears absent/expired. `/cluster-refresh` will not recreate it; reprovision the cluster instead.' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]

    run grep -F -- '"refresh_line": "\n⚠️ *Refresh completed* — credentials refreshed, but the ACG sandbox is still absent and must be reprovisioned",' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]
}

@test "webhook ask subprocess captures transcripts in the k3d-manager run dir" {
    run grep -F -- 'RUN_DIR = Path(os.environ.get("K3DM_RUN_DIR", Path.home() / ".local/share/k3d-manager/run"))' "${BATS_TEST_DIRNAME}/../../../scripts/lib/webhook/config.py"
    [ "$status" -eq 0 ]

    run grep -F -- 'prefix="k3dm-ask-", suffix=".out", delete=False, mode="w", dir=str(RUN_DIR)' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]
}

@test "webhook ask subprocess ensures the run dir exists before capturing" {
    run grep -F -- 'RUN_DIR.mkdir(parents=True, exist_ok=True)' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "$status" -eq 0 ]
}

@test "POST /analyze with correct token returns 202 and job_id" {
    run curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"alerts":[]}' \
        "${_WEBHOOK_URL}/api/v1/analyze"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"queued"'* ]]
    [[ "$output" == *'"job_id"'* ]]
}

@test "POST /analyze with wrong token returns 401" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer wrongtoken" \
        -H "Content-Type: application/json" \
        -d '{"alerts":[]}' \
        "${_WEBHOOK_URL}/api/v1/analyze"
    [ "$status" -eq 0 ]
    [ "$output" = "401" ]
}

@test "POST /cluster with response_url stored in job dir" {
    local response job_id job_file
    response="$(curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"action":"up","provider":"aws","response_url":"https://hooks.slack.com/test"}' \
        "${_WEBHOOK_URL}/api/v1/cluster")"
    job_id="$(echo "$response" | python3 -c 'import sys,json; print(json.load(sys.stdin)["job_id"])')"
    [[ -n "$job_id" ]]
    job_file="${K3DM_JOB_DIR}/${job_id}/response_url"
    [ -f "$job_file" ]
    [ "$(cat "$job_file")" = "https://hooks.slack.com/test" ]
}

@test "POST /cluster with wrong token returns 401" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer wrongtoken" \
        -H "Content-Type: application/json" \
        -d '{"action":"up"}' \
        "${_WEBHOOK_URL}/api/v1/cluster"
    [ "$status" -eq 0 ]
    [ "$output" = "401" ]
}

@test "POST /cluster with action=up returns 202 and job_id" {
    run curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"action":"up"}' \
        "${_WEBHOOK_URL}/api/v1/cluster"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"queued"'* ]]
    [[ "$output" == *'"job_id"'* ]]
}

@test "POST /cluster with action=down returns 202 and job_id" {
    run curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"action":"down"}' \
        "${_WEBHOOK_URL}/api/v1/cluster"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"queued"'* ]]
    [[ "$output" == *'"job_id"'* ]]
}

@test "POST /cluster with invalid action returns 400" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"action":"restart"}' \
        "${_WEBHOOK_URL}/api/v1/cluster"
    [ "$status" -eq 0 ]
    [ "$output" = "400" ]
}

@test "POST /cluster with missing action returns 400" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{}' \
        "${_WEBHOOK_URL}/api/v1/cluster"
    [ "$status" -eq 0 ]
    [ "$output" = "400" ]
}

# ── Level 1: localhost smoke — no cluster needed ───────────────────────────────

@test "Level 1: POST queues job and GET /status returns job output" {
    [[ "${K3DM_WEBHOOK_LIVE:-0}" == "1" ]] || skip "set K3DM_WEBHOOK_LIVE=1 to enable"

    local response job_id poll status_val
    response="$(curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"chart_version":"0.0.1-test","stage":"infra"}' \
        "${_WEBHOOK_URL}/api/v1/argocd-upgrade")"
    job_id="$(echo "$response" | python3 -c 'import sys,json; print(json.load(sys.stdin)["job_id"])')"
    [[ -n "$job_id" ]]

    for _ in $(seq 1 10); do
        poll="$(curl -s \
            -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
            "${_WEBHOOK_URL}/api/v1/status/${job_id}")"
        status_val="$(echo "$poll" | python3 -c 'import sys,json; print(json.load(sys.stdin)["status"])')"
        [[ "$status_val" != "queued" && "$status_val" != "running" ]] && break
        sleep 1
    done

    [[ "$status_val" == "success" || "$status_val" == "failed" ]]
}

@test "Level 1: GET /status output field is non-empty after job completes" {
    [[ "${K3DM_WEBHOOK_LIVE:-0}" == "1" ]] || skip "set K3DM_WEBHOOK_LIVE=1 to enable"

    local response job_id poll output_val status_val
    response="$(curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"chart_version":"0.0.1-test","stage":"infra"}' \
        "${_WEBHOOK_URL}/api/v1/argocd-upgrade")"
    job_id="$(echo "$response" | python3 -c 'import sys,json; print(json.load(sys.stdin)["job_id"])')"

    for _ in $(seq 1 10); do
        poll="$(curl -s \
            -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
            "${_WEBHOOK_URL}/api/v1/status/${job_id}")"
        status_val="$(echo "$poll" | python3 -c 'import sys,json; print(json.load(sys.stdin)["status"])')"
        [[ "$status_val" != "queued" && "$status_val" != "running" ]] && break
        sleep 1
    done

    output_val="$(echo "$poll" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("output",""))')"
    [[ -n "$output_val" ]]
}

# ── Level 2: idempotency — requires live cluster ───────────────────────────────

@test "Level 2: POST current chart version returns success without running make up" {
    [[ "${K3DM_WEBHOOK_LEVEL2:-0}" == "1" ]] || skip "set K3DM_WEBHOOK_LEVEL2=1 to enable (requires cluster)"

    local current response job_id poll status_val output_val
    current="$(kubectl get secrets -n cicd \
        -l 'argocd.argoproj.io/secret-type=cluster,environment=infra' \
        -o jsonpath='{.items[0].metadata.labels.argocd-chart-version}' 2>/dev/null || true)"
    [[ -n "$current" ]] || skip "no cluster secret found in cicd namespace"

    response="$(curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"chart_version\":\"${current}\",\"stage\":\"infra\"}" \
        "${_WEBHOOK_URL}/api/v1/argocd-upgrade")"
    job_id="$(echo "$response" | python3 -c 'import sys,json; print(json.load(sys.stdin)["job_id"])')"

    for _ in $(seq 1 15); do
        poll="$(curl -s \
            -H "Authorization: Bearer ${K3DM_WEBHOOK_TOKEN}" \
            "${_WEBHOOK_URL}/api/v1/status/${job_id}")"
        status_val="$(echo "$poll" | python3 -c 'import sys,json; print(json.load(sys.stdin)["status"])')"
        [[ "$status_val" != "queued" && "$status_val" != "running" ]] && break
        sleep 1
    done

    [ "$status_val" = "success" ]
    output_val="$(echo "$poll" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("output",""))')"
    [[ "$output_val" == *"no-op"* ]]
}

# ── Level 3: Cloudflare tunnel ─────────────────────────────────────────────────

@test "Level 3: tunnel rejects wrong token with 401" {
    [[ "${K3DM_WEBHOOK_LEVEL3:-0}" == "1" ]] || skip "set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)"

    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer wrongtoken" \
        -H "Content-Type: application/json" \
        -d '{"chart_version":"7.8.2","stage":"infra"}' \
        "${_TUNNEL_URL}/api/v1/argocd-upgrade"
    [ "$status" -eq 0 ]
    [ "$output" = "401" ]
}

@test "Level 3: tunnel unknown path returns 404 (auth passes, routing fails)" {
    [[ "${K3DM_WEBHOOK_LEVEL3:-0}" == "1" ]] || skip "set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)"
    [[ -n "${K3DM_WEBHOOK_LEVEL3_TOKEN:-}" ]] || skip "set K3DM_WEBHOOK_LEVEL3_TOKEN to real token"

    run curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_LEVEL3_TOKEN}" \
        "${_TUNNEL_URL}/api/v1/unknown"
    [ "$status" -eq 0 ]
    [ "$output" = "404" ]
}

@test "Level 3: tunnel POST with real token queues job and returns 202" {
    [[ "${K3DM_WEBHOOK_LEVEL3:-0}" == "1" ]] || skip "set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)"
    [[ -n "${K3DM_WEBHOOK_LEVEL3_TOKEN:-}" ]] || skip "set K3DM_WEBHOOK_LEVEL3_TOKEN to real token"

    run curl -s -X POST \
        -H "Authorization: Bearer ${K3DM_WEBHOOK_LEVEL3_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"chart_version":"0.0.1-tunnel-test","stage":"infra"}' \
        "${_TUNNEL_URL}/api/v1/argocd-upgrade"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"queued"'* ]]
    [[ "$output" == *'"job_id"'* ]]
}
