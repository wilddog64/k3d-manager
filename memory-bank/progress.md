# Progress — k3d-manager

> Compressed 2026-08-20. Detailed historical entries are preserved in
> `memory-bank/archive/progress-2026-08-19.md` and release notes.

## Releases

| Version | State |
|---|---|
| v1.25.0 | RELEASED — PR #116 `d48e465f`, tag/release published, protection restored |
| v1.24.1 | RELEASED — PR #115, tag and GitHub release published |
| v1.24.0 | RELEASED — PR #113, tag and GitHub release published |
| v1.23.0 and earlier | RELEASED — see `CHANGELOG.md` |

## v1.26.0 queue

- [ ] Sandbox registration lifecycle cleanup and stale Application removal.
- [ ] E2E promotion-gate integration with durable success/failure artifacts.
- [ ] Verify unknown/out-of-sync handling without mutating unrelated live Applications.
- [ ] Keep all new work within the five-plan milestone limit.

## Verification record

- v1.25.0 release validation: E2E BATS 16/16; webhook BATS 54/54; Python/shell syntax and shellcheck
  gates passed; Copilot findings resolved before merge.
- Node-health watchdog and E2E diagnostics hardening are included in the released branch.
- Prometheus/Grafana recovery, status retry behavior, remediation table cleanup, and Slack status/thread
  fixes are shipped; remaining live follow-ups are listed in `activeContext.md`.

## Process

- Every implementation updates this file and `activeContext.md` with the real commit/PR SHA.
- Unexpected live failures get a dated `docs/issues/YYYY-MM-DD-*.md` record with verbatim evidence.
- Historical specs/issues are archived only when superseded or unreferenced; files are never deleted.
