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

- [x] Lifecycle cleanup foundation — registration metadata plus dry-run/confirm `cleanup-stale-clusters`,
  provider/grace/retain guards, generated-Application-only deletion, and JSONL audit (`f90c8e0d`, pushed on
  `k3d-manager-v1.26.0`). Live expired-sandbox validation remains pending.
- [ ] E2E promotion-gate integration with durable success/failure artifacts.
- [ ] Verify unknown/out-of-sync handling without mutating unrelated live Applications.
- [ ] Keep all new work within the five-plan milestone limit.
- [x] k3s-aws SSM registration fallback — recorded live account `218085830935` Default Host Management
  Role failure in `docs/issues/2026-08-20-k3s-aws-ssm-fallback.md`; provider now falls back to SSH
  (`fef71219`, pushed on `k3d-manager-v1.26.0`). BATS provider suite 11/11 and shellcheck passed.
- [x] Lifecycle cleanup and ArgoCD data-layer DNS recovery — help documents both stale-cleanup targets,
  `make down CLEANUP_STALE=1` runs guarded cleanup, and `make up` repairs Hub CoreDNS before registration
  (`316f26d2`, pushed on `k3d-manager-v1.26.0`). Focused BATS 12/12, `bash -n`, shellcheck, and
  `_agent_audit` passed. Bug evidence is recorded in
  `docs/issues/2026-08-20-make-up-data-layer-argocd-host-dns.md`.
- [x] Added the explicit `make down CLEANUP_STALE=1` example to `make help` (`20a13862`, pushed on
  `k3d-manager-v1.26.0`); Makefile BATS 2/2 passed.
- [x] Added unified `cleanup-stale-resources` dispatch and wired it into confirmed `make down`
  cleanup (`f24c0c96`, pushed on `k3d-manager-v1.26.0`); Makefile BATS 3/3 passed.

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
