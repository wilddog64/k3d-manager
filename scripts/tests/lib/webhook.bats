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

@test "POST /cluster-status with wrong token returns 401" {
    run curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer wrongtoken" \
        -H "Content-Type: application/json" \
        -d '{}' \
        "${_WEBHOOK_URL}/api/v1/cluster-status"
    [ "$status" -eq 0 ]
    [ "$output" = "401" ]
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
    job_file="${HOME}/.local/share/k3d-manager/webhook-jobs/${job_id}/response_url"
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
