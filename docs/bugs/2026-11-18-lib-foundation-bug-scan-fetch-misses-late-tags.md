# vectordb bug metrics: lib-foundation fetch misses a tag pushed after its commit was fetched

**Status:** OPEN — captured 2026-11-18 from the M2 spec review (Argon)
**Priority:** P3 — a lib-foundation bug's release label can lag or stay `unassigned` until some later fetch brings the tag
**Triage:** carry → v1.47.0 — triage 2026-11-25, operator ("go with your recommendation"); was: next-minor → v1.47.0 candidate at the next /release-groom (operator, 2026-11-25); Argon blind classification, Claude verified
**Branch:** `k3d-manager-v1.47.0`
**Introduced by:** pre-existing (`_publish_lib_foundation_bugs`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Metrics label lag where `git fetch` without `--tags` misses tags pushed onto already-fetched lib-foundation commits until a subsequent fetch.)
**Waiting on:** dispatch — since 2026-11-25
**Prior art:** none above threshold (exact-slug check only; `make find-similar-docs` not run)
**Filed:** 2026-11-18

## Symptom

`bin/k3dm-vectordb-metrics:1091` runs `git fetch --quiet origin main` in the lib-foundation clone. Without `--tags`, git
auto-follows only tags that point into newly fetched history, so a release tag pushed onto an already-fetched merge commit
(the normal lib-foundation release flow: merge, then tag) is never fetched. Argon reproduced it with a scratch bare origin:
after the tag push, `git fetch --quiet origin main` leaves `git tag --list` empty. `_tally` then resolves the release through
tag ancestry in that clone and misses it.

## Fix (proposed)

Add `--tags` to that fetch, as the M2 spec does for registry projects
(`docs/plans/v1.45.0-multi-project-m2-bug-metrics.md`), with a late-tag test.
