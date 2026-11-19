# Plan dashboard counts each child spec file as its own release plan

**Status:** OPEN — captured 2026-11-19 by Claude from an operator screenshot
**Priority:** P3
**Introduced by:** pre-existing (the plan scan never knew child specs; exposed by the 2026-11-18 splits of plans 1, 3 and 4)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-19
**Prior art:** docs/bugs/2026-11-18-plan-dashboard-ready-on-your-go-ignores-draft-status.md (not scored) — read, different root cause; `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing), exact-slug glob found nothing

## Symptom

Operator, 2026-11-19: "release tracking dashboard seems to have more than 5 plans". v1.45.0 has five plans (1 remote
promote, 2 travel bundle, 3 multi-project records, 4 web console, 5 dispatch stall), within the X.Y.0 cap.

## Cause (read from code and refs, Claude, 2026-11-19)

`bin/k3dm-vectordb-metrics:30` `_PLAN_FILE_RE` matches every `docs/plans/vX.Y.Z-<slug>.md`, and `_plan_metrics`
(`:370`) emits one plan row per matching file. Child specs share the release prefix:

- `origin/deploy/hub` today: 6 rows (`v1.45.0-multi-project-m2-bug-metrics.md` is plan 3's M2 child).
- `k3d-manager-v1.45.0` HEAD: 14 rows (plan 1 parts `-1`, `-2a`..`-2d`; plan 4 parts `-a`, `-b`, `-c`; plan 3 M2), so the
  next promote makes it worse.

Children already say so in their header: `**Release:** v1.45.0 plan 1 part 2a (umbrella ...)`, `plan 4 part A of A/B/C`,
or `**Parent plan:**` (M2).

## Fix direction (for triage, not a spec)

Treat a file whose `**Release:**` line says `plan N part ...` or which carries `**Parent plan:**` as a child: fold it under
its parent row (or a child count) and leave it out of the per-release plan count. Readers to check: the Release Plans panel,
Hermes plan cards, `/release-groom` counts.
