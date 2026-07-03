#!/usr/bin/env bats

DOC="${BATS_TEST_DIRNAME}/../../../docs/howto/slack-slash-commands.md"
WORKER="${BATS_TEST_DIRNAME}/../../../workers/slack-relay/index.js"

@test "slack commands doc lists the cluster-status slash commands" {
  run grep -F -- '/cluster-status' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '/cluster-diagnose' "${DOC}"
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

  run grep -F -- '"command": "/cluster-diagnose"' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"command": "/cluster-refresh"' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"command": "/cluster-resume"' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"command": "/hostinger-status"' "${DOC}"
  [ "${status}" -eq 0 ]
}

@test "slack relay allowlist includes cluster-status and hostinger-status" {
  run grep -F -- "const ALLOWED_COMMANDS = new Set(['/cluster-up', '/cluster-down', '/cluster-status', '/cluster-diagnose', '/cluster-refresh', '/cluster-resume', '/hostinger-status', '/ask', '/claude', '/gemini', '/codex', '/argocd-upgrade'])" "${WORKER}"
  [ "${status}" -eq 0 ]
}

@test "slack relay assigns remote-operator roles to cluster commands" {
  run grep -F -- "const COMMAND_ROLES     = Object.freeze({" "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -F -- "'/cluster-status': 'reader'" "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -F -- "'/cluster-diagnose': 'reader'" "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -F -- "'/cluster-refresh': 'operator'" "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -F -- "'/cluster-up': 'admin'" "${WORKER}"
  [ "${status}" -eq 0 ]
}

@test "slack relay forwards remote-operator metadata headers" {
  run grep -F -- "'X-K3DM-Role': meta.role || 'reader'" "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -F -- "'X-K3DM-Actor': meta.actor || 'slack:unknown'" "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -F -- "'X-K3DM-Source-Command': meta.sourceCommand || 'unknown'" "${WORKER}"
  [ "${status}" -eq 0 ]
}

@test "slack relay parses cluster-diagnose payloads" {
  run grep -F -- "function parseClusterDiagnose(text) {" "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -F -- "return { payload: { provider: target, action: 'get-pods', namespace } }" "${WORKER}"
  [ "${status}" -eq 0 ]

  run grep -F -- "await relay('/api/v1/diagnostics', payload, meta)" "${WORKER}"
  [ "${status}" -eq 0 ]
}
