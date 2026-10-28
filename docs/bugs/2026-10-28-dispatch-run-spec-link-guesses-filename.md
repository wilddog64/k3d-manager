# Bug: Per run evidence task-name link guesses a nonexistent spec filename

**Status:** LIVE-VERIFIED — operator task-name click opens the recorded issue document
**Live evidence:** 2026-10-28 · run 1 · env local-grafana-v1.43.9 · scenario vectordb-retrieval-key-cache-slug-github-navigation · commit fbb52f67 · proves fix
**Fix commit:** fbb52f67
**Priority:** P3
**Filed:** 2026-10-28
**Branch:** k3d-manager-v1.43.9

Operator reported GitHub404 for docs/plans/v1.43.9-vectordb-retrieval-key-cache.md.
This is the task-name/spec link, not the Log link. Per-run PromQL derives a
filename from release/slug, but dispatch permits independent slugs. Recorded
spec for key-cache, retry and retry2 is instead
`docs/issues/2026-10-26-v1439-retrieval-dashboard-no-data.md`; GitHub API confirms
that file exists on k3d-manager-v1.43.9. Guessing a plans/bugs path is wrong.

Communicated correction before editing: use recorded dispatch spec for
existing task-name links, including issues-based tasks. Missing/invalid legacy
paths fall back to release branch, never an invented filename. Preserve table
layout, Log action, outcomes, evidence and tokens. No new table/panel or ledger
rewrite. Only validate/use existing spec metadata, no raw worker transcript.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`

## Acceptance

Run1startup failure and resumed runs link to recorded plans/bugs/issues spec
independent of slug. Invalid/absent paths use a safe branch URL with no user-
supplied URL host, traversal or injection. Keep existing global spec/type
validation elsewhere unchanged; this link fix must not silently alter bug
cost/verification policies. URL field stays available after organize and is
hidden with custom.hidden rather than removed. Regression exact reported
case red on old code, full metrics pytest/dashboard BATS/Ruff/PromQL and
staged gates. No layout changes; existing Log tests remain. Deployment and
operator click verification separate. No screenshot export.

## Operator live result

Operator confirmed make dispatch-metrics completed, applied the Agent Dispatch
ConfigMap, then supplied a GitHub destination screenshot showing the expected
breadcrumb docs/issues/2026-10-26-v1439-retrieval-dashboard-no-data.md and rendered
heading “VectorDB retrieval dashboard stays empty during probe.” No 404.
This verifies the task-name link only; the underlying retrieval issue's status
is unchanged. No screenshot copied/exported. Full textual record in
[verification evidence](../issues/2026-10-28-dispatch-run-spec-link-verification.md).
