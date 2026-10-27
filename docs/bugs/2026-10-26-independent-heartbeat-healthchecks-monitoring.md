# P2 enhancement: independent outbound heartbeat monitoring for m4, webhook, Hermes, cloud-bridge, and Hostinger

**Filed:** 2026-10-26, operator request after webhook became unresponsive while operator was away from home
**Status:** VERIFIED — optional implementation landed; provider enrollment and live alert verification pending
**Fix commit:** `233a4b1117645b1ea8506fb183fcd963756cd926`
**Priority:** P2
**Severity:** medium — an unavailable local control plane can prevent remote diagnosis and obscure component/host failures
**Branch:** `k3d-manager-v1.43.9`
**Release:** v1.43.9 (enhancement bug; no new release-plan slot)
**Approval:** original filing 2026-10-26; explicit implementation/verification selection in operator Luna batch 2026-10-27
**Dispatch:** go — model `gpt-6-luna`; task `independent-heartbeats-luna`
**Component:** m4 local webhook, Hermes, cloud-bridge; Hostinger heartbeat; independent external failure alerting
**Affected:** local m4 management plane, offsite operational visibility; optional m2 expansion

## Problem

On 2026-10-26 the operator reported that the webhook server became unresponsive while they were away from home. Its cause and process state have **not** been established. The existing cloud-bridge/webhook management path cannot be relied upon to diagnose or recover itself during a webhook outage. Hostinger has no inbound management path to m4/m2; adding one would violate the current outbound-only security model. A watchdog colocated with the webhook can restart a failed process, but cannot independently report an m4 host or network outage. Hostinger itself can fail or reboot, so it must not be the sole external observer.

This issue requests a small, independent, outbound-only heartbeat and alert path through Healthchecks.io or equivalent, using the provider's free-tier capacity where feasible. Verify limits before provisioning; do not assume service availability, delivery SLA, or recovery capability.

## Proposed behavior

1. Implement independently scheduled m4 heartbeat probes, preferably through a minimal launchd-managed script that does not depend on the webhook, Hermes, cloud-bridge, Kubernetes, or Hostinger. Emit a positive heartbeat only after the local check actually succeeds. Report explicit failures when appropriate.
2. Distinguish **m4 host/scheduler alive**, **Hermes responding**, **webhook request handling**, and **cloud-bridge polling freshness**. A process-exists check is insufficient for webhook health. If a service cannot be measured independently without circular dependency, document the limitation and keep the heartbeat appropriately labeled.
3. Hostinger sends its own outbound heartbeat directly to the external service; missing Hostinger reports must alert independently of m4. The m4 heartbeat also goes directly to the external service, not through Hostinger.
4. Configure documented schedule/grace/alert thresholds with missed-heartbeat and explicit-failure scenarios. Proposed initial checks: m4 host (1 min), Hermes (1 min), functional webhook (1 min), cloud-bridge (2 min), Hostinger (2 min). Avoid treating scheduled/paused jobs or intermittent network timeouts as definitive host failure.
5. Keep automatic **local** webhook restart as a separately gated, bounded mechanism (rate limit, cooldown, logging, lock, dependency safeguards). No remote reboot, automated infrastructure mutation, or unaudited remediation is authorized by this filing.
6. Use secrets supplied by a secure local secret source, never checked-in ping URLs/tokens or unredacted logs. HTTPS only, short timeouts, backoff on provider errors; report check identity without exposing endpoints.
7. Provide operator runbook for enrollment, secret provisioning, configuration on m4 and Hostinger, alert destination verification, silent/probe-failure investigation, and disabling checks when hosts/services are intentionally offline. Include documentation of external-provider outage and the residual inability to restore a powered-off m4.
8. Scope initial rollout to the five checks above. m2, Vault, ArgoCD, backup, ingestion and runner checks are later optional expansion; do not consume the entire free allowance by default.
9. Ensure health checks do not report false success simply because the reporter script runs, avoid duplicated pings masking a failure, and classify reachability loss as **unknown host vs network** until separately confirmed.

## Files

- `bin/k3dm-heartbeat`
- `bin/k3dm-heartbeat-setup`
- `bin/k3dm-hermes`
- `bin/k3dm-cloud-bridge`
- `scripts/etc/launchd/com.k3d-manager.heartbeat.plist.tmpl`
- `scripts/etc/systemd/k3dm-heartbeat.service.tmpl`
- `scripts/etc/systemd/k3dm-heartbeat.timer.tmpl`
- `scripts/etc/heartbeat/checks.example.json`
- `scripts/tests/bin/test_heartbeat.py`
- `scripts/tests/bin/heartbeat.bats`
- `scripts/tests/bin/test_cloud_bridge.py`
- `scripts/tests/bin/test_retrieval_probe.py`
- `docs/howto/independent-heartbeats.md`
- `docs/tests/heartbeat.md`
- `CHANGELOG.md`

## Bounded implementation decisions

- Use standard-library Python for a standalone sender and setup renderer. Do not
  add a daemon framework, web dependency, cloud account, or runtime package install.
- Default disabled/unconfigured. Rendering or --dry-run must not read secrets,
  install jobs, probe services or send pings. Installation/enabling is an explicit
  later operator action, and tests use only fixture roots/fake local/provider I/O.
- Five identities only: m4-host, m4-hermes, m4-webhook, m4-cloud-bridge, hostinger.
  m4 sends its four checks directly; Hostinger runs the same standalone sender
  locally for its one host check. No m4 SSH/remote calls and no proxy via Hostinger.
- Healthchecks.io UUID HTTPS URLs are supplied via named Keychain items on m4
  or protected owner-only files on Hostinger. No URL/key in argv, templates,
  example values, logs, metrics or exceptions. Reject insecure file permissions,
  malformed/non-HTTPS configuration and redirects leaking credentials.
- Provider period/grace and destination enrollment are documented manual setup.
  Do not auto-provision or modify accounts. Success and /fail follow the official
  HTTPS ping API; rate limit retries and timeouts, avoid overlapping/duplicate runs.
- Host means scheduler/outbound path observed, not proof a missing host is powered
  off. Test clock-based freshness, failure/recovery/provider errors and maintenance
  suppression; never simulate external alert delivery as real evidence.
- Hermes currently runs every 300s and may take minutes. Add an advisory completed-
  cycle timestamp to its existing private state, without changing index/SSH behavior.
  Bridge gets a private atomic last-successful-poll marker under its existing
  STATE_DIR only after successful ticks. Both marker writes are advisory, never
  fatal to the original services, and do not call the heartbeat sender.
- Sender reads those markers with documented configurable freshness bounds (allow
  normal poll/jitter/run duration), rejects future/malformed/stale values, and
  labels its result as last-completed-cycle/poll freshness. No process-only success.
- The existing reader-authenticated loopback /api/v1/health?quick=1 can establish
  bounded request/JSON handling. Retrieve the reader credential in memory using
  the existing secure source; do not accept 401/403 as success or expose bodies.
  Distinguish handler response from downstream all_ok; document that this health
  route probes dependencies and timeout cannot identify host vs network cause.
- Provide launchd and systemd timer/service templates and an explicit setup tool
  with --dry-run; no implicit sudo, remote setup or execution on import. Setup must
  preserve existing jobs/config and validate credentials before enabling.
- No automatic restart/watchdog remediation is included. Recovery uses the
  separate operator-run incident procedure; M5 is satisfied by this explicit
  boundary and documented provider/power-loss limitations.

Official sources checked 2026-10-27: [ping API](https://healthchecks.io/docs/http_api/),
[states and grace](https://healthchecks.io/docs/), and
[account limits](https://healthchecks.io/docs/autoprovisioning/). Current docs say
20 checks on the free account, sufficient for five; operator must verify their
actual account and alert channel at enrollment. Never enable auto-provisioning
(create=1) or assume external alert delivery from a successful ping.

## Acceptance

```yaml
must:
  - id: M1
    text: Independent outbound scheduled reports distinguish m4 host heartbeat, Hermes health, functional webhook health, and cloud-bridge freshness without calling the webhook to report its own health.
  - id: M2
    text: Hostinger reports its heartbeat directly to an external receiver, independently of m4 and its tunnel.
  - id: M3
    text: Missed heartbeat and explicit failing probe produce configured external alerts after a documented grace interval; restored probes recover the check state.
  - id: M4
    text: Configuration, secure credentials, operator runbook, enrollment and intentional-maintenance suppression are documented and tested.
  - id: M5
    text: Watchdog recovery, if implemented, is locally bounded and independently observable; provider outages and m4 power loss are explicitly classified as residual risks.
must_not:
  - id: N1
    text: Do not add inbound connectivity, SSH, firewall exceptions or Hostinger-to-m4/m2 calls.
  - id: N2
    text: No checked-in heartbeat URLs or API secrets; never disclose tokens in logs, metrics or alerts.
  - id: N3
    text: Do not claim m4 failure merely because its external heartbeat is missing, or mark process existence as functional webhook health.
  - id: N4
    text: No unauthorised host reboot, destructive action, production deployment or automatic remote recovery.
  - id: N5
    text: Do not couple the independent sender to the webhook, cloud-bridge or Hermes execution path.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N2, N3, N5]
    text: Unit/integration tests with mocked local probe and remote receiver verify separate success/failure paths, authentication redaction, request timeouts and network failures.
  - id: E2
    kind: offline
    proves: [M3, M5, N3, N4]
    text: Fake clock and fault injection establish missed-heartbeat grace, failure/recovery transitions, cooldown and prevention of unbounded restarts or forbidden remote mutations.
  - id: E3
    kind: live
    proves: [M1, M2, M3, M4]
    text: Operator-approved validation of m4, webhook, Hermes, bridge and Hostinger independent checks including stopped probe, restored probe, delivered alert and documented maintenance suppression; redact all secret material.
interface:
  - External provider HTTPS ping/fail endpoints (URLs supplied only by local secret configuration)
  - Outbound-only launchd or existing host scheduler on m4
  - Independent outbound Hostinger scheduler
  - Existing webhook functional health and cloud-bridge polling status interfaces (confirm paths before implementation)
```

## Definition of Done

- [ ] Inspect established launchd/service deployment, heartbeat providers, test conventions and alert channels before implementing.
- [ ] Implement five isolated checks with secure configuration and focused regression tests.
- [ ] Verify failure, recovery, provider outage, maintenance windows and no-inbound-path invariants offline.
- [ ] Provide operator runbook with provider enrollment and independent alert-path checks.
- [ ] Record operator-approved live failure and recovery evidence for E3; only then mark LIVE-VERIFIED.
- [ ] Update project changelog and relevant operations documentation when implementation lands.

## What NOT to Do

- Do NOT create a PR or commit to `main`; work on `k3d-manager-v1.43.9`.
- Do NOT present the original 2026-10-26 webhook failure as diagnosed, fixed or live-verified.
- Do NOT provision third-party accounts, configure secrets, or alter live m4/m2/Hostinger services while filing this enhancement.

## Dispatch rules — operator batch 2026-10-27

The operator explicitly selected this existing bug for implementation by
GPT-6-Luna, independent offline review, and operator live verification one fix
at a time. This is implementation authorization; no worker may deploy, restart
services, contact live clusters/registries/providers, create accounts, rotate
credentials, or run live tests. Work only in the isolated task worktree and the
Files allowlist. Do not edit this spec, memory-bank, or source plan statuses.
Do not stage, commit, push, or create PRs. Preserve DO NOT REMOVE comments.
Add meaningful regressions and show them red on the original behavior before
reporting green. Run focused tests, syntax/lint, and git diff --check; report
actual outputs and any unmet acceptance honestly. Use <=8 if blocks in new or
refactored functions. Report legacy budget conflicts instead of raising limits.
The coordinator will run audit/lint on staged changes before committing.

Focused gates: new heartbeat pytest/BATS plus existing retrieval_probe and
cloud_bridge pytest; Python syntax/Ruff and rendered plist/systemd contract checks.
No webhook/Hermes/bridge restart, Hostinger install, provider ping or account/secret
provisioning is authorized for the worker. Prepare commands for later operator
verification one check at a time.

## Independent verification — 2026-10-27

Focused offline gates passed and dispatcher landing reran them after rebase.
Full outputs, review corrections, image compatibility and remaining live steps:
`docs/issues/2026-10-27-six-bug-luna-batch.md`. No live rollout or enrollment was performed.

Live-check follow-up: corrected the heartbeat default/example URL from9000 to the production default7443 in `2b93434e893ff0417946c550deecbecb1443021d`; configured custom URLs remain supported. Default-route regression passed. Monitoring enrollment and failure/recovery delivery are still unverified. See docs/issues/2026-10-27-webhook-doctor-live-port-mismatch.md.
