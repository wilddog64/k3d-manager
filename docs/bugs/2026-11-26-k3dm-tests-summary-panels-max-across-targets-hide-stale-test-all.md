# Bug: k3dm Tests "last run" and "since last success" panels take max() across targets, so a fresh `test` hides a stale `test-all`

**Status:** OPEN — captured, not triaged
**Priority:** P3
**Introduced by:** `cc88386c` (2026-10-09, dashboard panels 1-2) with the unlabeled timestamps in `bin/k3dm-test-metrics`
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-26
**Classified:** pending (Argon, from this doc alone; batched at grooming 2026-11-29)
**Prior art:** exact-slug glob: none; `docs/bugs/2026-10-06-k3dm-tests-dashboard-no-data.md` (different symptom); `make find-similar-docs` not run
**Severity:** low — the panels can look current while the nightly `test-all` is days old; the OfflineSuiteStale alert annotation prints an empty target
**Filed:** 2026-11-26, found in the blind reviews of v1.46.0 plan 3 (Fable subagent; Neon dispatch `v1460-plan3-review-neon`), Claude confirmed in code; operator: "File as bugs (Recommended)"
**Component:** `scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml` (panels 1-2), `bin/k3dm-test-metrics`, `scripts/etc/prometheus/rules-acg/k3dm-tests.yaml`

## Symptom (from code)

- Panel 1 is `max(k3dm_test_last_timestamp_seconds) * 1000` and panel 2 is
  `time() - max(k3dm_test_last_success_timestamp_seconds)` (`k3dm-tests-configmap.yaml:26`, `:37`).
- Both metrics are written without a `target` label (`bin/k3dm-test-metrics:195`, `:214`, `:239`); the series are
  separated only by the Pushgateway grouping key `instance=<target>-<origin>` (`:246`).
- The `OfflineSuiteStale` annotation uses `{{ $labels.target }}` on `k3dm_test_last_success_timestamp_seconds`
  (`scripts/etc/prometheus/rules-acg/k3dm-tests.yaml`, alert OfflineSuiteStale), so the summary reads "for  in >7d".

## Fix options (for triage)

1. Add `target` to both timestamps and make panels 1-2 per target (or `max by (target)`).
2. Keep "across targets" as the intended scope, say so in the panel descriptions, and fix the annotation to use `instance`.

v1.46.0 plan 3 child A asserts the current scope and records the gap as `known_failing`.
