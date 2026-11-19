# Plan dashboard counts each child spec file as its own release plan

**Status:** OPEN — captured 2026-11-19 by Claude from an operator screenshot
**Priority:** P3
**Introduced by:** pre-existing (the plan scan never knew child specs; exposed by the 2026-11-18 splits of plans 1, 3 and 4)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-19
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

## Fix direction (captured before the spec)

Treat a file whose `**Release:**` line says `plan N part ...` or which carries `**Parent plan:**` as a child: fold it under
its parent row (or a child count) and leave it out of the per-release plan count. Readers to check: the Release Plans panel,
Hermes plan cards, `/release-groom` counts.

## Change (`bin/k3dm-vectordb-metrics` only)

In `_plan_metrics` (`:371`), right after the `_PLAN_FILE_RE` match (`:377-380`) and before anything is parsed:

1. **Child test.** A file is a child spec when its text matches either
   `(?mi)^\*\*Release:\*\*\s*v\d+\.\d+\.\d+\s+plan\s+\d+\s+part\b` or `(?m)^\*\*Parent plan:\*\*`.
   An umbrella line such as `**Release:** v1.45.0 plan 1 (branch ...)` or `plan 3 (displaced ...)` has no `part` and is
   not a child.
2. **Children are not plans.** A child adds no `k3dm_plan_info` row and does not contribute to `counts` (so no
   `k3dm_plan_release_docs` count), `by_stem`, waves, overlaps or blockers. It is **not** counted in `skipped`.
3. **Child count metric.** For each release with at least one child, emit
   `k3dm_plan_child_docs{repo="<repo>",release="<release>"} <n>`, sorted by release, next to the
   `k3dm_plan_release_docs` lines. Release comes from the file name, as for plans.
4. A plan whose `**Depends on:**` names a child path keeps that stem in `depends_on` as an unresolved name (current
   behaviour for any stem not in `by_stem`); no new handling.

Expected on today's `k3d-manager-v1.45.0` tree: five v1.45.0 `k3dm_plan_info` rows (remote-promote-approval,
service-password-travel-bundle, multi-project-records, web-console-ssh-behind-cloudflare-access,
dispatch-stall-recovery) and `k3dm_plan_child_docs{repo="k3d-manager",release="v1.45.0"} 10`.

## Tests (`scripts/tests/bin/test_vectordb_bug_metrics.py`)

New `test_plan_child_specs_fold_out_of_plan_rows` using `texts=` and `tmp_path` like `test_plan_approval_and_plan_metrics`
(`:122`, assert `tmp_path` is not the repo root first):

- `v1.58.0-umbrella.md`: `**Status:** PROPOSED`, `**Release:** v1.58.0 plan 1 (branch k3d-manager-v1.58.0)` → one row.
- `v1.58.0-umbrella-a.md`: `**Release:** v1.58.0 plan 1 part A of A/B (umbrella ...)` → no row.
- `v1.58.0-umbrella-2b.md`: `**Release:** v1.58.0 plan 1 part 2b (umbrella ...)` → no row.
- `v1.58.0-child-m2.md`: `**Parent plan:** \`docs/plans/v1.58.0-other.md\`` and no Release line → no row.
- `v1.58.0-other.md` (positive control): `**Release:** v1.58.0 plan 2 (displaced foo, operator)` → one row.
- `v1.58.0-partial.md` (positive control): title contains the word "part" in its heading (`# Partner part split`) and
  `**Release:** v1.58.0 plan 3 (branch ...)` → one row (the word must be on the Release line after `plan N`).
- Assert exactly three `k3dm_plan_info{` rows, `k3dm_plan_child_docs{repo="k3d-manager",release="v1.58.0"} 3`,
  `k3dm_plan_info_skipped{repo="k3d-manager"} 0`, and that the summed `k3dm_plan_release_docs` values for v1.58.0 equal 3.
- Red on pre-fix code: the new test fails on `ac732cdb`; paste the failing lines in the report.

Existing tests keep passing unchanged.

## Files

- `bin/k3dm-vectordb-metrics`
- `scripts/tests/bin/test_vectordb_bug_metrics.py`

## Contract readers

Writer: `bin/k3dm-vectordb-metrics:548-555` (`k3dm_plan_info`, `k3dm_plan_release_docs`, `k3dm_plan_info_skipped`;
new `k3dm_plan_child_docs`). Readers (`git grep`, 2026-11-19):

- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml:64-65` release dropdown from `k3dm_plan_release_docs`
  labels: unchanged (umbrellas keep every release present).
- `grafana-dashboard-bugs.yaml:1913,1961,2000,2048,2092` stat tiles sum `k3dm_plan_release_docs`; `:2140` counts and
  `:2193` lists `k3dm_plan_info`: these now count plans only, which is the fix. No YAML change.
- `scripts/tests/plugins/grafana_dashboard_bugs.bats:267` asserts the dropdown query string: unaffected.
- No reader of `k3dm_plan_child_docs` yet; it is informational.

## What NOT to Do

- Do not touch `_PLAN_FILE_RE`, the dashboard YAML, plan docs, or `_plan_state`.
- Do not count children in `k3dm_plan_info_skipped`.
- Do not update `memory-bank/`, create a PR, or skip hooks (`--no-verify`).
- Do not modify files outside `## Files`.

## Acceptance

```yaml
must:
  - id: M1
    text: a docs/plans file whose Release line says "plan N part ..." or which has a Parent plan header emits no k3dm_plan_info row and adds nothing to k3dm_plan_release_docs
  - id: M2
    text: umbrella and standalone plans (Release line "plan N (...)" or no Release line) still emit one row each
  - id: M3
    text: k3dm_plan_child_docs reports the number of child files per release; k3dm_plan_info_skipped does not include them
must_not:
  - id: N1
    text: "a child spec file appears as its own plan row — red today (v1.45.0 shows 14 rows on the branch head)"
  - id: N2
    text: "a Parent plan child is counted in k3dm_plan_release_docs — red today"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    command: "python3 -m pytest -q scripts/tests/bin/test_vectordb_bug_metrics.py (new test red on ac732cdb, green after) plus bats scripts/tests/plugins/grafana_dashboard_bugs.bats"
    intent: The release plans table shows each plan once; split-out part specs no longer inflate the count past five.
  - id: E2
    proves: [M1, M2, M3]
    kind: live
    command: "Claude, after the operator's next hub promote: the v1.45.0 Release Plans panel lists exactly five plans and Pushgateway has k3dm_plan_child_docs{release=\"v1.45.0\"} 10"
    intent: The dashboard you screenshotted shows five v1.45.0 plans again, even after the plan 1 and plan 4 part specs reach the hub.
interface:
  - "new metric k3dm_plan_child_docs{repo,release}"
  - "k3dm_plan_info and k3dm_plan_release_docs exclude child spec files"
```

**Intent approved:** operator, 2026-11-19
**Intent approval note:** "go ahad to file a bug and dispatch to flash to have this fix" (approving the fix proposed in chat: child specs fold under their parent and leave the per-release plan count)
