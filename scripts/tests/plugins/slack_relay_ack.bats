#!/usr/bin/env bats

WORKER="${BATS_TEST_DIRNAME}/../../../workers/slack-relay/index.js"

@test "slack relay uses waitUntil for slash command dispatch" {
  run grep -F -- "event.respondWith(handle(event.request, event))" "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -F -- "event.waitUntil((async () => {" "${WORKER}"
  [ "${status}" -eq 0 ]
}

@test "slack relay cluster-status acks before webhook completes" {
  run grep -F -- "return jsonReply(\`🔍 Checking \${_where} cluster status…\`, threadTs, true)" "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -F -- "const { ok } = await relay('/api/v1/cluster-status', payload)" "${WORKER}"
  [ "${status}" -eq 0 ]
}

@test "slack relay can post a fallback response_url error" {
  run grep -F -- "async function postResponseUrl(url, text, ephemeral = true)" "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -F -- "await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')" "${WORKER}"
  [ "${status}" -eq 0 ]
}
