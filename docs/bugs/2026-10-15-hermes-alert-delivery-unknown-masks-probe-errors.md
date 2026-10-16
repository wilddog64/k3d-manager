# P3 — Hermes alert_delivery unknown masks probe cause and offline sandbox scope

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.44.0` (follows the canonical doc)
**Priority:** P3 — monitoring diagnostic fidelity
**Status:** DUPLICATE 2026-10-15 — merged into `docs/bugs/2026-10-13-hermes-alert-delivery-probe-unknown-hides-error.md` (operator-approved); track and fix there
**Approval:** operator explicitly requested P3 bug filing; implementation not authorized

## Observed behavior

Hermes dashboard row: sensor `alert_delivery`, message `alert delivery probe unavailable`, status `unknown`, source `hermes`. This was observed following AWS ACG sandbox bring-up and teardown, but the screenshot contains no failing command output or Kubernetes context. Do not infer that actual alert notifications failed.

## Confirmed code path

`scripts/lib/hermes/sensors.py` runs `bin/k3dm-alert-delivery-status --json` and requires exit code zero, `available: true`, and a nonempty `clusters` array. Any exception—including nonzero exit, invalid/empty output or malformed entries—is caught using bare `except Exception` and reduced to the same `unknown` message. Underlying reason, affected context, and executable exit code are lost.

`bin/k3dm-alert-delivery-status` enumerates the hub plus contexts from `scripts/etc/argocd/app-clusters.tsv`, filters them by locally configured kubecontexts (not proven live cluster readiness), then queries `monitoring` Alertmanager CRs and generated Secrets. A configured but intentionally destroyed `ubuntu-k3s` sandbox could therefore cause a nonzero result for the entire probe. This remains a hypothesis pending real command output. The script may also return `available:true` with zero usable clusters, which Hermes treats as unknown without explanation.

The current check inspects configuration-level routing blackouts (missing `configSecret` or null-root receiver with no child routes); it does **not** perform a synthetic end-to-end email/Slack delivery test. Preserve that scope distinction in names and descriptions.

## Investigation / remediation requirements

1. Obtain a read-only reproduction: run `bin/k3dm-alert-delivery-status --json` on the monitoring host and capture exit code, sanitized stderr, and context-by-context outcomes. Identify whether hub, persistent Hostinger, or deliberately offline AWS context triggered `unknown`; do not infer this from the timing alone.
2. Return structured per-context statuses including `healthy`, `degraded`, `skipped_expected_offline`, or `unknown`, with bounded non-sensitive error categories. Retain the exact distinction between unreachable API, absent Alertmanager CR, missing generated Secret, failed parse, zero monitored clusters, and actual null-sink route configuration.
3. Derive expected-on/offline state from a trusted lifecycle/registration signal, not merely the presence of a kubeconfig context. An intentionally stopped ephemeral sandbox must not mask a persistent cluster with a functional Alertmanager. Do not silently exempt an active sandbox that ought to be reachable.
4. Avoid global failure on a single context; return partial evidence for other monitored contexts and aggregate accurately. Missing evidence for a required cluster stays `unknown`, not `healthy`.
5. Log/report sanitized, concise failure reason and context from Hermes instead of bare `alert delivery probe unavailable`; never expose Kubernetes Secret contents, tokens, or credentials.
6. Make clear this is *Alertmanager routing configuration inspection*, not proof that Slack/email recipients received a notification. Document any separately required synthetic delivery probe rather than claiming its verification.
7. Add deterministic mocked regression tests for intentionally offline sandbox, unavailable persistent cluster, missing/generated Secrets, invalid JSON, no clusters, partial successes, and actual blackhole/null-route detection. Confirm one failure doesn't erase unrelated good evidence.

## Acceptance criteria

- A deliberately inactive AWS sandbox does not automatically produce an unexplained global `unknown` when persistent targets are observable.
- Unexpected outages in required clusters remain visible and actionable.
- Hermes reports context and safe reason with correct `verified/degraded/unknown` semantics, without misleading end-to-end delivery claims.
- Existing route-blackout checks continue to identify absent configuration references or dead-end root routes.
- No live cluster changes, new paid dependencies, or privileged automation are introduced.

**Implementation:** Not started. Bug documentation only.
