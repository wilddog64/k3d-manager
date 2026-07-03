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

  run grep -F -- '"usage_hint": "[aws|gcp|az|hostinger]  e.g. hostinger"' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"usage_hint": "[hostinger|aws|gcp|az|hub] ...  e.g. hostinger pods shopping-cart-apps"' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"usage_hint": "<chart_version> [acg|infra]  e.g. 9.5.15 infra"' "${DOC}"
  [ "${status}" -eq 0 ]
}

@test "slack commands doc gives a concrete example for each command" {
  run grep -F -- '| `/cluster-up [aws\|gcp\|az\|hostinger]` | Provision cluster | `/cluster-up hostinger` |' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| `/cluster-down [aws\|gcp\|az\|hostinger]` | Tear down cluster | `/cluster-down hostinger` |' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| `/cluster-status [aws\|gcp\|az\|hostinger]` | Check cluster health | `/cluster-status hostinger` |' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| `/cluster-diagnose [hostinger\|aws\|gcp\|az\|hub] ...` | Run read-only diagnostics | `/cluster-diagnose hostinger pods shopping-cart-apps` |' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| `/cluster-refresh [aws\|gcp\|az\|hostinger]` | Restore tunnel + credentials | `/cluster-refresh hostinger` |' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| `/cluster-resume <aws\|gcp\|az>` | Resume provision from last checkpoint | `/cluster-resume aws` |' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| `/hostinger-status` | Check Hostinger app cluster status | `/hostinger-status` |' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| `/claude <question>` | Multi-agent cluster troubleshooting | `/claude why is frontend degraded?` |' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| `/gemini <question>` | Multi-agent cluster troubleshooting | `/gemini why is data-layer out of sync?` |' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| `/codex <question>` | Multi-agent cluster troubleshooting | `/codex explain this ArgoCD drift` |' "${DOC}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| `/argocd-upgrade` | Upgrade ArgoCD platform-ops | `/argocd-upgrade 9.5.15 infra` |' "${DOC}"
  [ "${status}" -eq 0 ]
}

@test "slack commands doc fix mode names the real FIX_CONTEXT override" {
  run grep -F -- '`FIX_CONTEXT` defaults to `ubuntu-k3s`. Override with `make fix-restart APP=x NS=y FIX_CONTEXT=k3d-k3d-cluster`.' "${DOC}"
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
