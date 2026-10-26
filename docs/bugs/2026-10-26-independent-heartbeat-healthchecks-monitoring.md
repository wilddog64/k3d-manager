# P2 enhancement: independent outbound heartbeat monitoring for m4, webhook, Hermes, cloud-bridge, and Hostinger

**Filed:** 2026-10-26, operator request after webhook became unresponsive while operator was away from home
**Status:** OPEN — PROPOSED; not implemented or live-verified
**Priority:** P2
**Severity:** medium — an unavailable local control plane can prevent remote diagnosis and obscure component/host failures
**Branch:** `k3d-manager-v1.43.9`
**Release:** v1.43.9 (enhancement bug; no new release-plan slot)
**Approval:** operator on 2026-10-26: "go ahead to do that. please follow docs/bugs format, and push to current active branch"
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

- `docs/bugs/2026-10-26-independent-heartbeat-healthchecks-monitoring.md`
- Implementation paths to be selected only after inspecting actual m4 launchd, Hermes, webhook, cloud-bridge, Hostinger deployment, test and documentation layouts; do not invent a new service dependency.
- Add focused automated tests and an operator runbook at the repository's established locations during implementation.

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
