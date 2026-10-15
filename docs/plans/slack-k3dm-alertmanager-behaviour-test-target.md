# Enhancement: expose test-alertmanager-behaviour through /k3dm

**Status:** PROPOSED — not implemented
**Priority:** P3 enhancement
**Requested:** 2026-10-14, operator
**Release:** unscheduled P3 backlog (triage 2026-10-15)
**Component:** Slack /k3dm allowlist, offline observability tests
**Approval:** specification only, no permission to alter execution policy or runtime

## Evidence

- `Makefile` defines `test-alertmanager-behaviour` as `python3 -m pytest scripts/tests/observability/test_alertmanager_notify_behaviour.py scripts/tests/observability/test_kine_compaction_stalled.py -v` (around line 1343).
- `scripts/lib/webhook/make_targets.py` includes `test`, `test-bin`, `test-pytest`, `test-python-unit`, `test-python`, and `test-all`, but **does not include** `test-alertmanager-behaviour`.
- `test-all` does not invoke the dedicated Alertmanager behavior target.
- Unlike most offline test Make targets, this target currently does not run under `scripts/tests/tripwire.sh`. Before remote exposure, verify test dependencies and isolation; do not assume these tests cannot access host tools, Docker, network or live clusters.

## Requested behavior

An authorized operator can run `/k3dm test-alertmanager-behaviour` or `k3dm test-alertmanager-behaviour` in Slack, receive a queued job ID, follow status/logs, and receive a truthful terminal result.

## Design and security requirements

1. Audit each invoked pytest module for host commands, external Docker and network dependencies, and any potentially destructive fixture behavior; specify exact offline versus live execution contract.
2. Only once safe, add an explicit entry to `MAKE_TARGETS` with a least-privilege role chosen based on actual execution (do not reflexively grant `reader` if it may run live host-tool commands), a bounded timeout, zero positional args, and no arbitrary command injection.
3. If external tools are required to complete behavioral tests, define a dedicated controlled environment/runner or restrict the target as appropriate. Never weaken `tripwire.sh`, bypass its safeguards, or convert failed assertions into success.
4. Ensure Slack help lists the new target and its required role. Support both slash command and existing thread-based `k3dm` routing.
5. Capture output, job ID and exit status using the existing async Make dispatcher; preserve the test exit code. Log retrieval must honor authorization and the existing explicit-job-ID fix.
6. Preserve existing test target meaning. Do not quietly add these specialized external tests to `make test-all` unless separately approved and their contract verified.

## Acceptance criteria

- [ ] Risk review records whether the target is safe to expose, including its external dependencies and role rationale.
- [ ] Allowed Slack user can queue the test without executing unapproved infrastructure mutations.
- [ ] Unsupported/unauthorized users receive an explicit rejection; help accurately reflects availability.
- [ ] A test failure returns failed terminal status and retains redacted logs; no false green.
- [ ] Timeout, busy-lock, cancellation and missing optional dependencies are reported distinctly.
- [ ] Regression tests cover target allowlist parsing, role, bounded invocation, slash route, thread route and job correlation.
- [ ] One controlled live Slack execution verifies acknowledgment, job identification and terminal outcome.

No source or runtime changes in this proposal.
