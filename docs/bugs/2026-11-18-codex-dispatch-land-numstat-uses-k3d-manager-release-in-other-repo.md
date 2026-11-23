# `codex-dispatch land` change stats compare against the k3d-manager release branch in another repo

**Status:** OPEN — captured 2026-11-18 from Argon's blind review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — metrics only
**Introduced by:** pre-existing (cross-repo dispatch; the same line is on `main` at `bin/k3dm-codex-dispatch:1380`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Metrics-only defect where `codex-dispatch land` computes diff line counts against the k3d-manager release ref in cross-repo tasks while landing succeeds.)
**Waiting on:** operator decision
**Prior art:** docs/bugs/2026-10-09-codex-dispatch-has-no-throughput-or-cost-metrics.md (keyword) — read, different scope (adds the metric; does not cover the base ref). Exact slug: no match. `make find-similar-docs` not run (vector store unreachable).
**Filed:** 2026-11-18

## Symptom

`land` records line counts with `git diff --numstat` against `$rel`, the k3d-manager release branch
(`bin/k3dm-codex-dispatch:1496`). For a task in another repo (dirused, lib-foundation) that ref does not exist there,
so the count is empty or wrong.

## Impact

The metrics row for a cross-repo land is wrong; the land itself is correct.

## Fix sketch

Use the task's own target branch (`$run/target`) as the base. Test: a cross-repo fixture with a two-line change
records `+2`; a k3d-manager task is unchanged (control).
