# Bug: Hermes `data_layer` unknown status has no visible cause

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30
**Status:** OPEN
**Severity:** medium — an unknown data-layer result is fail-closed, but the operator cannot tell
whether the webhook was unavailable, the check was absent, or the payload was ungradeable.

## Evidence

The Hermes status-history panel showed:

```text
data_layer (unknown) 2
```

The `2` is the status enum for `unknown`, not a count. The historical series does not include the
sensor evidence, and the current findings table may no longer contain the older snapshot. This makes
it impossible to determine what happened during that poll from Grafana alone.

## Current semantics

The `data_layer` sensor reads only the webhook's `Data layer` check. It returns `unknown` when the
webhook credential/source is unavailable, when the check is absent, or when the payload cannot be
graded. A real `ok: false` result is debounced before becoming `degraded`; `unknown` is not proof
that the data layer itself failed.

## Root cause

Hermes publishes the status and short evidence in the current snapshot, but the historical metric
does not retain a timestamped, queryable cause for each `unknown` transition. Grafana therefore
shows only the numeric status and status label.

## Proposed fix

Publish and display a bounded, redacted `data_layer` cause for each status transition, or provide a
linked Hermes history view that retains the evidence. At minimum, distinguish:

- webhook credential/source unavailable;
- `Data layer` check absent;
- payload ungradeable;
- actual `ok: false` degradation.

Keep the existing fail-closed behavior and do not classify `unknown` as a service failure.

## Acceptance

For every historical `data_layer (unknown)` point, the dashboard or linked Hermes history identifies
which source condition produced it, without exposing credentials or requiring access to the M4's
local state files.
