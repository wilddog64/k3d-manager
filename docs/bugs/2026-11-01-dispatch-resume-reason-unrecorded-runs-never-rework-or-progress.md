# Bug: run outcomes never classify a resumed run as rework or progress, so a third of recent runs have no verdict

**Status:** VERIFIED 2026-11-07 — `2c7fc95c` and fixture fix `22110d0c`; independent verifier PASS (bats 12/12, pytest 17/17 on `22110d0c`; M1, M3, M4, M5 red on `6774f198`); live E3 pending
**Waiting on:** live check — since 2026-11-07
**Priority:** P2
**Severity:** medium — "Run outcome coverage" is 67% (7d) and 63% (v1.43.13), so the dashboard cannot support an efficiency claim; the gap recurs on every release, it is not only old data ageing out. Workaround: read the ledger by hand
**Approval:** operator, 2026-11-01 ("how could we close the gap … investigate and file bug/plan … if this a bug then prioritize it")
**Filed:** 2026-11-01
**Detected by:** Claude, replaying the exporter over the M4 ledger (`~/.local/share/k3d-manager/worktrees/ledger.jsonl`, 2026-11-01)
**Affected:** `bin/k3dm-codex-dispatch` (`_dispatch_resume`, `_dispatch_usage`), `bin/k3dm-dispatch-metrics` (`_run_outcomes`, ~lines 999-1100)
**Branch:** `k3d-manager-v1.43.14`
**Depends on:** `docs/bugs/2026-11-01-dispatch-run-outcome-unknown-lumps-missing-evidence.md` landing first (same function; this bug turns its `superseded` label into verdicts where the ledger has a reason)
**Related:** `docs/plans/v1.43.6-dispatch-verified-delivery-cost.md` (defines the outcome classes); `docs/plans/v1.44.0-claude-cost-task-attribution.md` (the cost half of the same gap)

## Observed failure

`bin/k3dm-dispatch-metrics --dry-run` on the M4, 2026-11-01: run outcome coverage 0.672 (7d), 0.632 (v1.43.13),
0.349 (30d). The 42 unclassified 7d runs, all recorded after v1.43.6 added the evidence fields:

| 7d runs | Ledger fact |
|---|---|
| 28 | exited 0, then the coordinator resumed the task (`resume` event) |
| 9 | the task has no `land` and no `abandon` (some still running) |
| 5 | both: resumed, and the task never landed |

`progress` is 0 in every window: no code path produces it.

## Root cause

1. `resume` records no reason. The plan defines `rework` as another attempt caused by "an objective test refusal,
   failed verification or documented correction", but `bin/k3dm-codex-dispatch resume` takes only `--slug` and
   `--prompt-file`. The reason exists only in a separate, optional `intervention` command: 35 resumes in 7d,
   6 `intervention` events ever.
2. `_run_outcomes` ignores even the recorded reasons. An exit-0 run followed by a launch falls through to `unknown`
   whether or not an `intervention` with `reason: correction` sits between them.
3. Nothing closes a task. A task with no `land` and no `abandon` stays unclassified forever, and no release gate lists
   such tasks before the PR.

## Fix

1. **`resume` requires `--reason continue_prompt|clarification|correction|other`.** It writes `reason` on the
   `resume` event and also appends the matching `intervention` event, so the "Human continuation prompts" panel counts
   every resume. `--reason` missing or invalid exits 2 before any ledger write or worker launch.
2. **Classify resumed runs.** For an exit-0 run with no test refusal before the next launch, take the reason from
   that next `resume` event, or else from the latest `intervention` event between the exit and the next launch:
   - `correction` → `rework`, evidence `resume.correction` (or `intervention.correction`).
   - `continue_prompt`, `clarification` → `progress`, evidence `resume.<reason>`. The coordinator recorded the reason
     when it reviewed the run, which meets the plan's rule that `progress` comes from a reviewer and never from
     the worker's self-report.
   - `other`, or no reason → keep the label from the depends-on bug (`superseded`).
   The existing `accepted`, test-refusal `rework`/`failed`, exit-code `failed` and `abandon` rules keep precedence and
   are unchanged.
3. **List open tasks.** `bin/k3dm-codex-dispatch open [--version vX.Y.Z]` prints one line per task with a `start`
   and no `land` or `abandon` (version, slug, age, last event), and exits 1 if there is any, 0 if none. The
   pre-PR gate runs it for the release version, and each task listed is landed or abandoned before the PR. After
   this lands, Claude adds that step to its `/create-pr` skill. That edit is not part of the dispatch.
4. Dashboard: the "Run outcomes" description says where `progress` and `rework` come from. No panel or layout change.

## Files

- `bin/k3dm-codex-dispatch`
- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/bin/k3dm_codex_dispatch.bats` (or the existing dispatcher suite)
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` (description text only)
- `CHANGELOG.md`

## What NOT to do

- Do not rewrite or backfill `ledger.jsonl`; old resumes without a reason stay `superseded`.
- Do not infer `progress` from the worker's output, its exit message or token counts.
- Do not change the coverage formula (`accepted`, `progress`, `rework`, `failed` over all runs).
- Do not make `open` abandon or land anything.
- Tests use a scratch `K3DM_WORKTREE_ROOT` (asserted not to be the real one) and stub `codex`; ledger lines copy
  real event shapes from the M4 ledger, 2026-11-01, with that note in a comment.

## Acceptance

```yaml
must:
  M1: resume without --reason, or with a value outside the four, exits 2 and writes no ledger event and launches no worker
  M2: resume --reason R writes a resume event with reason R and one intervention event with reason R
  M3: an exit-0 run followed by a resume with reason correction is labelled rework; with continue_prompt or clarification it is labelled progress
  M4: an exit-0 run with an intervention reason correction between its exit and the next launch (no reason on the resume) is labelled rework
  M5: open --version V lists each V task with a start and no land/abandon and exits 1; with none it prints nothing and exits 0 (paired control)
must_not:
  N1: a run that meets the accepted, test-refusal, exit-code or abandon rule never changes label because of a resume reason
  N2: a resume with reason other, or a resume event with no reason field (old ledger), never yields rework or progress
  N3: the coverage formula and every metric name and label set stay unchanged
  N4: open never writes to the ledger or touches a worktree
evidence:
  E1:
    proves: [M1, M2, M5, N4]
    kind: offline
    intent: You will see BATS with a scratch worktree root and stub codex show resume refuse a missing or bad reason with no ledger growth (red on the pre-fix dispatcher, which accepts it), write both events for a good reason, and open list an unlanded task with exit 1 and an empty ledger with exit 0, the ledger unchanged byte for byte.
    what: bats on the dispatcher suite
  E2:
    proves: [M3, M4, N1, N2, N3]
    kind: offline
    intent: You will see pytest build one scratch ledger per case and assert rework for correction, progress for continue_prompt and clarification, superseded for other and for a reasonless resume, the accepted/refusal/abandon fixtures unchanged, and the coverage value computed by the unchanged formula; M3 and M4 are red on the pre-fix exporter.
    what: pytest scripts/tests/bin/test_dispatch_metrics.py
  E3:
    proves: [M3]
    kind: live
    intent: You will see, after the next release's dispatches, Run outcomes show non-zero progress or rework from resumes, and 7d coverage above the 2026-11-01 value of 67%.
    what: operator screenshot of /d/k3dm-agent-dispatch, Window 7d
interface:
  - bin/k3dm-codex-dispatch resume --slug S --prompt-file P --reason R
  - bin/k3dm-codex-dispatch open [--version vX.Y.Z]
  - ledger.jsonl under K3DM_WORKTREE_ROOT
  - bin/k3dm-dispatch-metrics --dry-run (k3dm_dispatch_run_outcomes, k3dm_dispatch_run_outcome_coverage)
```
