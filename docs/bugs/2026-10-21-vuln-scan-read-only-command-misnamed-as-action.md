# Bug: read-only vuln-scan command name implies an active vulnerability scan

**Filed:** 2026-10-21
**Status:** OPEN — source-level naming mismatch confirmed; rename not implemented
**Priority:** P3 — command clarity and safe operator expectations
**Severity:** low
**Approval:** operator approved filing on 2026-10-21 and implementation dispatch on 2026-10-22
**Release:** v1.43.5 (bug; exempt from plan cap)
**Branch:** `k3d-manager-v1.43.5`
**Found by:** operator reviewing `/k3dm targets` command help
**Component:** `Makefile`, `scripts/lib/webhook/make_targets.py`, `scripts/lib/webhook/cloud_actions.py`, Slack/cloud-bridge documentation and tests
**Related:** `docs/plans/v1.34.0-slack-k3dm-make-command.md`, `docs/plans/v1.40.0-cloud-bridge-test-targets.md`, `docs/howto/slack-slash-commands.md`

## Problem

`/k3dm targets` currently lists:

```text
vuln-scan — VulnerabilityReport summary (reader)
```

But the target is **read-only**: it reports already-existing Kubernetes/Trivy
`VulnerabilityReport` resources; it does not start a scan. The word `scan`
is an action verb and suggests that calling it launches a vulnerability scan.
This is confusing when the system separately supports an actual scan trigger.

## Source evidence on v1.43.5

`Makefile` defines two aliases for the same read-only renderer:

```make
## Print VulnerabilityReport summary for both clusters
vuln-scan trivy-scan-report:
    ./scripts/k3d-manager trivy_scan_report
```

`scripts/lib/webhook/make_targets.py` exposes:

```python
"vuln-scan": {"min_role": "reader", "summary": "VulnerabilityReport summary"},
```

`scripts/lib/webhook/cloud_actions.py` exposes
`make-vuln-scan` mapped to Make target `vuln-scan`.
The separate `app-cve-scan` target invokes
`app_cve_scan_trigger`, actually triggers a CVE scan CronJob, and
requires the operator role.

No evidence suggests `vuln-scan` currently performs a destructive scan.
This is a naming/contract usability bug rather than a vulnerability scanning failure.

## Expected behavior

The canonical report-only target and Slack command should be
`vuln-scan-report`, described clearly as **read existing VulnerabilityReports,
no scan triggered**. Preserve `vuln-scan` as a deprecated read-only compatibility
alias during migration to prevent breaking existing scripts or cloud-bridge callers.
Preserve `app-cve-scan` as the distinct operator-only active scan trigger.

## Proposed fix

1. Add `vuln-scan-report` as the primary Make target, retaining `vuln-scan`
   (and `trivy-scan-report`) as backward-compatible read-only aliases.
2. Update `scripts/lib/webhook/make_targets.py` to make
   `/k3dm vuln-scan-report` available at reader role and display it
   in `/k3dm targets`. Clearly mark the old name as an alias/deprecated,
   rather than accidentally presenting it as a second independent scan.
3. Update `scripts/lib/webhook/cloud_actions.py` with a
   `make-vuln-scan-report` reader action. Retain `make-vuln-scan`
   for compatibility without widening permissions.
4. Update `Makefile` help, `docs/howto/slack-slash-commands.md`,
   `docs/howto/cloud-session-requests.md`, other canonical docs and
   focused tests that assert the allowlist, help text, and alias behavior.
5. Keep the actual scan trigger `app-cve-scan` operator-only; do not
   rename it to `vuln-scan-report` or permit reader-triggered scans.

## Acceptance

```yaml
must:
  - id: M1
    text: make vuln-scan-report invokes the existing read-only trivy_scan_report function, without triggering a Kubernetes Job or CronJob.
  - id: M2
    text: /k3dm vuln-scan-report is available to the reader role and its help description explicitly states that it displays existing reports.
  - id: M3
    text: The cloud-bridge reader action make-vuln-scan-report routes to the same read-only operation with current validation and authorization boundaries.
  - id: M4
    text: Existing make vuln-scan, make trivy-scan-report, /k3dm vuln-scan, and make-vuln-scan callers remain compatible during deprecation.
  - id: M5
    text: Documentation/help consistently distinguish report retrieval from app-cve-scan's actual scan trigger.
must_not:
  - id: N1
    text: Reader access must not trigger a vulnerability scan, create a Job, or acquire operator permissions.
  - id: N2
    text: The rename must not silently remove existing aliases or change scan scheduling/report data.
  - id: N3
    text: Cloud-bridge restrictions must not be widened beyond its existing reader-tier surface.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, M5, N1, N2, N3]
    text: Make dry-run and stubbed Slack/webhook/bridge regression checks compare new canonical and old alias routes; fail a mutation that points reader target at app_cve_scan_trigger.
  - id: E2
    kind: live
    proves: [M2, M3, M4, M5]
    text: After separate approval and rollout, compare Slack help/reader command output and cloud-bridge reader request results; verify that no new scan CronJob was created.
interface:
  - Makefile
  - scripts/lib/webhook/make_targets.py
  - scripts/lib/webhook/cloud_actions.py
  - docs/howto/slack-slash-commands.md
  - docs/howto/cloud-session-requests.md
  - associated command/role/cloud-bridge tests

## Files

- `Makefile`
- `scripts/lib/webhook/make_targets.py`
- `scripts/lib/webhook/cloud_actions.py`
- `scripts/tests/bin/webhook_make_targets.py`
- `scripts/tests/bin/makefile_webhook_slack.bats`
- `scripts/tests/bin/test_cloud_bridge.py`
- `docs/howto/slack-slash-commands.md`
- `docs/howto/cloud-session-requests.md`
```

## Definition of Done

- [ ] Canonical `vuln-scan-report` implemented and advertised in help.
- [ ] Old read-only aliases remain functional, with explicit deprecation policy.
- [ ] Slack and cloud-bridge authorization/dispatch tests pass.
- [ ] Operator verifies E2 and records the deployed version, output and fix SHA.
- [ ] Status updated to FIXED or LIVE-VERIFIED only with corresponding evidence.

## What NOT to Do

- Do NOT create a PR or merge to `main` for this bug filing.
- Do NOT change implementation code, roles or production infrastructure during filing.
- Do NOT make `vuln-scan-report` initiate new vulnerability scans.
- Do NOT remove old client-facing names without a migration plan.
