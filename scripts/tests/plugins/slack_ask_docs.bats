#!/usr/bin/env bats

WORKER="${BATS_TEST_DIRNAME}/../../..//workers/slack-relay/index.js"
WEBHOOK="${BATS_TEST_DIRNAME}/../../..//bin/k3dm-webhook"
POLICY="${BATS_TEST_DIRNAME}/../../..//scripts/lib/webhook/policy.py"

@test "ask-docs relay is allowed and reader-scoped" {
  run grep -F -- "'/ask-docs'" "${WORKER}"
  [ "${status}" -eq 0 ]
  run grep -F -- "'/ask-docs': 'reader'" "${WORKER}"
  [ "${status}" -eq 0 ]
}

@test "ask-docs relay validates text and sends its own endpoint" {
  run grep -F -- "Usage: /ask-docs [--sources] <question>" "${WORKER}"
  [ "${status}" -eq 0 ]
  run grep -F -- "relay('/api/v1/ask-docs', payload, meta)" "${WORKER}"
  [ "${status}" -eq 0 ]
  run grep -F -- "📚 Searching the docs…" "${WORKER}"
  [ "${status}" -eq 0 ]
}

@test "ask-docs webhook route and policy are reader-scoped" {
  run grep -F -- '"/api/v1/ask-docs": {"handler": "ask_docs", "min_role": "reader"' "${WEBHOOK}"
  [ "${status}" -eq 0 ]
  run grep -F -- '"/api/v1/ask-docs": {"name": "ask-docs", "min_role": "reader"}' "${POLICY}"
  [ "${status}" -eq 0 ]
}

@test "ask-docs does not alter the ask endpoint" {
  run grep -F -- "relay('/api/v1/ask', payload, meta)" "${WORKER}"
  [ "${status}" -eq 0 ]
}
