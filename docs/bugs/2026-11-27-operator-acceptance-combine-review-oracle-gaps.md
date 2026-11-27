# Bug: operator acceptance harness (v1.46.0 plan 3) — combine-review oracle-strength findings batch

**Status:** OPEN — captured, not triaged
**Priority:** P3
**Introduced by:** v1.46.0 plan 3 (`bc5cfbe8`, `155f15e1`, `0e500bcb`, `42063f90`; unreleased)
**Should have been caught by:** review
**Introducing change reviewed:** yes (Neon combine review, 2026-11-26, verdict FAIL; safety items fixed in p3d)
**Waiting on:** operator decision — since 2026-11-27
**Classified:** pending (Argon, from this doc alone; batched at grooming 2026-11-29)
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run
**Severity:** low — scenarios that pass or stay known_failing for the wrong reason; no isolation or secret exposure
**Filed:** 2026-11-27, Claude (operator: "Safety now, rest P3 (Recommended)")

1. **M5 oracles that do not exercise behaviour.** `scenarios/k3dm_tests.py` `panels-promql` evaluates hand-written
   series with `target` labels the exporter never emits on the timestamp metrics, and skips empty-state and panel 9
   `noValue` checks; `panels-multi-target` declares `promtool` but only greps the dashboard for `max(...)`;
   `scenarios/cleanup.py` `cleanup-vocabulary` greps source strings instead of driving the thread parser, so it stays
   known_failing even after a fix (or flips on a rename); `metrics_sequence` lacks a positive control that the failure
   group existed at t1/t2. Fix: derive series from the exporter payloads, evaluate panels 1-2 with promtool, drive the
   parser in an isolated child.
2. **M6 promtool discovery.** `runner.py` checks only `shutil.which("promtool")`, ignoring `PROMTOOL` and
   `~/.local/bin/promtool` (`scripts/tests/promtool.bash`); `test_operator_acceptance.py` asserts `passed` with no skip
   when promtool is missing, so `make test-pytest` fails on a host without it. Fix: shared `find_promtool()`; skip only
   promtool-backed inconclusive scenarios.
3. **M8 guard port policy.** `guard.validate_url` blocks only 9091/19094/7443, so any other loopback service
   (Grafana 3001, Vault 8200) is allowed; `guard.run` does not check `*_URL` in explicit env; the A-N1 test unit-tests
   the function only. Fix: allow only ports registered by `FakePushgateway`; end-to-end refusal test.
4. **MINORs** — duplicated helpers across p3a/p3b (redaction, run-root resolution), guide/Makefile mismatches,
   scenario-order coupling on `stub.log`, git stub flag handling, untested size retention, narrow `prior_art`
   exception handling (details in the Neon report, dispatch run `v1460-plan3-combine-neon`).
