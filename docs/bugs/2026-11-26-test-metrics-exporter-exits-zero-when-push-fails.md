# Bug: `bin/k3dm-test-metrics` exits 0 and returns the URL when every push attempt fails

**Status:** OPEN — captured, not triaged
**Priority:** P3
**Introduced by:** `3a254484` (2026-09-27, "metrics push skipped (non-fatal)")
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-26
**Classified:** pending (Argon, from this doc alone; batched at grooming 2026-11-29)
**Prior art:** exact-slug glob: none; `docs/bugs/2026-10-05-nightly-test-metrics-push-failure-is-silent.md` read — FIXED by a staleness alert, not by a failure signal from the exporter (related, different fix layer); `make find-similar-docs` not run
**Severity:** low — the staleness alerts still fire after hours; but no caller can tell "published" from "push failed" except by grepping stdout
**Filed:** 2026-11-26, found in the blind reviews of v1.46.0 plan 3 (Fable subagent; Neon dispatch `v1460-plan3-review-neon`), Claude confirmed in code; operator: "File as bugs (Recommended)"
**Component:** `bin/k3dm-test-metrics` (`push_metrics`, `main`)

## Symptom (from code)

`push_metrics` returns `url` both after a successful PUT (`bin/k3dm-test-metrics:259-260`) and after the last retry fails
(`:266-267`); `main` returns 0 in every path (`:287`, `:300`). The only signal is the printed text, which
`bin/k3dm-webhook:1825` and `scripts/lib/webhook/lifecycle.py:216` grep for.

## Fix options (for triage)

1. A distinct exit code (for example 3) when publication fails, with every caller (`Makefile` test-all recipe, webhook,
   launchd test-metrics job) checked so a push failure does not turn a green suite red.
2. Pin the stdout strings as the contract and test them.

v1.46.0 plan 3 child A treats this as a known-failing contract: its "publication failure is distinct" scenario asserts the
stdout text and records the exit-code gap as `known_failing`, never as passed.
