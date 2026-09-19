#!/usr/bin/env bats

WORKER="${BATS_TEST_DIRNAME}/../../../workers/slack-relay/index.js"

@test "slack relay uses waitUntil for slash command dispatch" {
  run grep -F -- "event.respondWith(handle(event.request, event))" "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -Eq 'event\.waitUntil\(' "${WORKER}"
  [ "${status}" -eq 0 ]
}

@test "slack relay cluster-status acks before webhook completes" {
  run grep -Eq 'jsonReply\(.*cluster status' "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -E -- "await relay\\('/api/v1/cluster-status', payload" "${WORKER}"
  [ "${status}" -eq 0 ]
}

@test "slack relay can post a fallback response_url error" {
  run grep -Eq 'function postResponseUrl\(' "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -Eq 'postResponseUrl\(responseUrl, .*Webhook unreachable' "${WORKER}"
  [ "${status}" -eq 0 ]
}
