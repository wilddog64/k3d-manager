#!/usr/bin/env bats

DOC="${BATS_TEST_DIRNAME}/../../../docs/howto/slack-slash-commands.md"
WORKER="${BATS_TEST_DIRNAME}/../../../workers/slack-relay/index.js"

@test "slack commands doc lists the cluster-status slash commands" {
  run grep -F -- '/cluster-status' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '/hostinger-status' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '/cluster-refresh' "${DOC}"
  [ "${status}" -eq 0 ]
}

@test "slack commands doc manifest matches the relay command set" {
  run grep -F -- '"command": "/cluster-up"' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"command": "/cluster-down"' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"command": "/cluster-status"' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"command": "/cluster-refresh"' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"command": "/cluster-resume"' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"command": "/hostinger-status"' "${DOC}"
  [ "${status}" -eq 0 ]
}

@test "slack relay allowlist includes cluster-status and hostinger-status" {
  run grep -F -- "const ALLOWED_COMMANDS = new Set(['/cluster-up', '/cluster-down', '/cluster-status', '/cluster-refresh', '/cluster-resume', '/hostinger-status', '/ask', '/claude', '/gemini', '/codex', '/argocd-upgrade'])" "${WORKER}"
  [ "${status}" -eq 0 ]
}
