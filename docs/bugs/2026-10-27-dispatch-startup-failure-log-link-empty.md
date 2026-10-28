# Bug: failed startup Log link opens an empty Loki view

**Status:** VERIFIED — Luna implementation independently tested and pushed; operator live verification pending
**Fix commit:** 61e1d9944ed19048975dc470d28e57f866a85e1e
**Priority:** P3
**Filed:** 2026-10-27
**Branch:** `k3d-manager-v1.43.9`
**Related:** `docs/bugs/2026-10-25-dispatch-run-log-not-viewable-from-grafana.md`

Failed startup rows with codex_exit.exit evidence offer a Grafana Log link, but
the shipper deliberately ships only landing-test logs. The local codex.log
contains the startup error while the linked Loki view is empty. Historical
exit127 rows are valid; their later retry2 succeeded and landed.

[Verbatim evidence and source analysis](../issues/2026-10-27-dispatch-startup-exit127-empty-grafana-log.md).

A scoped fix should show unsupported evidence as local-only/unavailable with
a clear explanation, preserving the existing prohibition on shipping codex.log.
Do not rewrite failed historical attempts as successful or ship transcripts.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`

## Authorized bounded task

Operator asked to investigate the three open screenshot bugs and dispatch
accordingly. Implement this P3 in an isolated GPT-6-Luna worktree. Preserve
historical failure outcome/exit127 and local codex.log evidence path; label
unsupported startup evidence clearly local-only/not shipped. Offer usable
Loki links only for evidence supported by the existing landing-test shipper.
Do not ship/read worker transcripts, alter bin/k3dm-dispatch-logs, rewrite
ledger/history, claim recovery or add a new log-export pipeline. Preserve
supported land-test/land_refused logs and dashboard fields. Keep metric labels
bounded and safe; unknown/legacy/no-test evidence must be truthful.

Add meaningful offline metric/dashboard regressions for failed startup exit127
(no empty-view promise, local path retained), successful supported landing
log (working link retained), unknown/legacy evidence. Demonstrate new relevant
regression red on original behavior. Run focused test_dispatch_metrics pytest,
agent_dispatch_dashboard BATS, Python syntax/Ruff, YAML/embeddedJSON validation
and diff check. Existing unrelated legacy >8if functions must not be refactored
or allowlisted silently; report a conflict. New/refactored functions <=8ifs.

Read repository instructions/memory-bank first. Edit only Files; no spec or
memory edits, stage/commit/push/PR, cluster/provider/Keychain/network/live
checks, credentials, or service restart. Coordinator stages/reviews/gates/
lands/pushes and schedules operator dashboard live verification. No new plans.

## Independent implementation review

Luna implementation landed and pushed after review follow-up. [Full test output, corrected fixture/gate failures and live limits](../issues/2026-10-27-three-open-bugs-investigation-and-luna.md). Operator live check pending; no production deployment/restart by coordinator.
