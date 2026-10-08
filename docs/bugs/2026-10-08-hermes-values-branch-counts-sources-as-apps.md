# Hermes values-branch warning counts source references as applications

**Filed:** 2026-10-08
**Branch:** k3d-manager-v1.42.0
**Status:** OPEN
**Severity:** Low — misleading scope in an operator warning
**Component:** scripts/lib/hermes/sensors.py:values_branch

## Finding

Screenshot shows "15 apps not on k3d-manager-v1.42.0" with examples including
hub-platform-ops@k3d-manager-v1.41.0 and hub-vectordb at the previous branch.
The sensor appends one stale record PER SOURCE and labels len(stale) as apps.
A multi-source app can be counted twice. The exact unique-app count in the screenshot is unknown.

An isolated execution of the current sensor against one fixture app with two stale sources yields:

```text
Fixture contains 1 application with 2 stale k3d-manager sources
Sensor message: 2 apps not on k3d-manager-v1.42.0: one-app@k3d-manager-v1.41.0, one-app@k3d-manager-v1.41.0
Confirmed: reported count is source references, not unique applications
```

Fixture transport/record/debounce helpers were stubbed; source iteration/counting was real.
No live authentication, app deployment or sensor-state mutation in the reproduction.

## Acceptance

Either say "15 stale source references across N applications", or deduplicate the displayed
application count while retaining every source/revision in structured evidence.
Use stable namespace/name identity where available. Keep source coverage, HEAD exclusion,
debouncing and unknown/unavailable behavior unchanged.
Tests cover two stale refs in one app, mixed current/stale refs, multiple apps and HEAD.
Do not fix the text by dropping a source from the branch-drift check.

Branch mismatch itself is relative to Hermes's configured/checkout expectation, not proof of
a failed deployment. Evaluate intended deployed baseline before reapplying live ApplicationSets.
See the associated investigation issue for live evidence and follow-up. No runtime fix yet.
