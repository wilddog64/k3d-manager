# Plan dashboard shows "ready on your go" for plans whose spec is still a draft

**Status:** OPEN
**Priority:** P3
**Introduced by:** unknown
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** fix running — since 2026-11-18
**Triage:** operator, 2026-11-18, promoted out of the P3 batch ("go with 1, and dispatch to Luna"); fix on `k3d-manager-v1.45.0`
**Prior art:** none (`make find-similar-docs` unavailable: vector store context `k3d-k3d-cluster` missing; exact-slug glob found nothing) — not run

## Symptom

Operator, 2026-11-18, screenshot of the v1.45.0 plans table: plans 1 (remote promote approval), 4 (browser SSH console)
and 5 (dispatch stall recovery) all show **Blocked by: ready on your go** and **⚠ needs your decision**, so it looks as
if three plans wait on the operator. None does yet:

- Plan 1 is `DRAFT`: proof of Slack/Workers behaviour and the Fable + Astra spec review are still owed by Claude.
- Plan 4 is `DRAFT`: refresh and the critical-risk spec review are owed by Claude.
- Plan 5 is `PLANNED`: the spec is not written, and its intent is `**Intent approved:** no`.

## Cause (read from code, not run)

`bin/k3dm-vectordb-metrics:497-531` builds `blocked_by` from branch, dependencies, wave note, intents and file overlaps,
and falls through to "ready on your go" when the `**Dispatch:**` header is not `go`. It never reads the `**Status:**`
first word, so a `DRAFT` or `PLANNED` spec counts as dispatchable.

`intent_required` (`:414`) is true only when a `**Filed:**` line exists with date >= 2026-11-08. Plan 5 has no Filed line
and plan 4 was filed 2026-10-25, so neither shows "intents need approval" even though plan 5's intent is `no`.

## Proposed fix (approved 2026-11-18)

Add a blocker from the Status first word: `DRAFT` → "spec not reviewed", `PLANNED` → "spec not written". Treat
`**Intent approved:** no` as unapproved regardless of the Filed date.

## Change (`bin/k3dm-vectordb-metrics` only)

In `_plan_metrics` (`:371`):

1. **Spec stage blocker.** From the Status value (`status`, already read at `:382`), when the first word is `DRAFT`
   the plan gets blocker `spec not reviewed`; when it is `PLANNED` or `PLAN`, blocker `spec not written`. Match the
   first word only, with the same boundary style `_plan_state` uses (`(?:\b|\s|—|–|-|:)`), case-insensitive. Put
   this blocker first in `blockers` (before `branch not cut`). `_plan_state` is unchanged: these plans stay
   `execution="proposed"`. `PROPOSED`, `SPEC WRITTEN`, `SPEC`, `SCOPED`, `QUEUED`, `READY`, `APPROVED` get no new blocker.
   The existing `dispatched` override (`:520-521`) still replaces every blocker when a dispatch is open.
2. **Explicit intent "no".** A line matching `(?mi)^\*\*Intent approved:\*\*\s*no\b` makes `intent_required` true
   whatever the Filed date (keep the existing Filed >= 2026-11-08 rule as the other way in). `intent_ok` is unchanged.
3. **No orange decision cell before a spec exists.** When a dispatchable plan has the spec stage blocker and its
   `dispatch` is `unknown`, emit `dispatch_approval="n/a"` (the dashboard already maps `n/a` to `-`, grey). An explicit
   `**Dispatch:**` header value is kept as written.

Expected on today's tree (v1.45.0): plan 1 and plan 4 `blocked_by="spec not reviewed"`, `dispatch_approval="n/a"`;
plan 5 `blocked_by="spec not written; intents need approval"`, `dispatch_approval="n/a"`.

## Tests (`scripts/tests/bin/test_vectordb_bug_metrics.py`)

- **New `test_plan_spec_stage_blocks_draft_and_planned`** (scratch git repo on `k3d-manager-v1.58.0`, built like
  `test_plan_operator_go_is_own_label_and_real_blockers_remain`): docs
  - `draft`: `**Status:** DRAFT — written` → `blocked_by="spec not reviewed"`, `dispatch_approval="n/a"`
  - `planned`: `**Status:** PLANNED — not started` → `blocked_by="spec not written"`, `dispatch_approval="n/a"`
  - `draft-gated`: DRAFT with `**Dispatch:** needed` → `dispatch_approval="needed"` (explicit header kept)
  - `proposed` (positive control): `**Status:** PROPOSED` and no Dispatch header → `blocked_by="ready on your go"`,
    `dispatch_approval="unknown"`
  - `spec-written` (positive control): `**Status:** SPEC WRITTEN — not implemented` → `blocked_by="ready on your go"`
  - `planned-dispatched`: PLANNED with an open ledger start for it (ledger shape as in
    `test_plan_blocked_by_dispatch_intent_and_file_wait`, scratch ledger asserted not the real one) → `blocked_by="dispatched"`
  - Every row keeps `execution="proposed"`.
- **New `test_plan_intent_no_needs_approval_without_filed_date`:** `**Status:** PROPOSED\n**Intent approved:** no — needs operator`
  with no Filed line → `intents need approval` in blocked_by; positive control: same doc with
  `**Intent approved:** operator, 2026-11-18` and no Filed line → `blocked_by="ready on your go"`; a doc with neither
  line and no Filed date → `ready on your go` (old rule unchanged).
- **Update `test_missing_dispatch_header_reads_as_a_pending_decision_only_before_dispatch` (`:1799`):** its `waiting`
  and `gated` fixtures use `PLANNED` only as a generic not-dispatched status; change both to `**Status:** PROPOSED` so
  the test keeps testing the missing Dispatch header, with every assert unchanged.
- Red on pre-fix code: both new tests fail on the current `k3d-manager-v1.45.0` head; paste the failing lines.

## Files

- `bin/k3dm-vectordb-metrics`
- `scripts/tests/bin/test_vectordb_bug_metrics.py`

## Contract readers

`k3dm_plan_info` labels `blocked_by` and `dispatch_approval` (writer: `bin/k3dm-vectordb-metrics:538`):

- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml:2193` (panel 107 query) and `:2235`/`:2254` show
  `blocked_by` as free text; `:2448-2470` maps `dispatch_approval` (`unknown` → "⚠ needs your decision", `n/a` → "-").
  New values need no dashboard change.
- `scripts/tests/plugins/grafana_dashboard_bugs.bats:1084` asserts the string `ready on your go` stays in the producer
  source: still true.
- `scripts/tests/bin/test_dashboard_queries.py:130` and the lifecycle fixtures at `test_vectordb_bug_metrics.py:354-372`
  use `PROPOSED`/`READY`/`IN PROGRESS`/`LANDED` statuses only: unaffected.
- `bin/k3dm-vectordb-metrics:909` and `:955` read `blocked_by` from `milestones`, a different source: unaffected.

## What NOT to Do

- Do not change `_plan_state` or the `execution` label; do not touch the dashboard YAML.
- Do not change `intent_ok` parsing or the Filed-date rule other than adding the explicit `no` path.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: a dispatchable plan whose Status first word is DRAFT shows blocked_by "spec not reviewed"
  - id: M2
    text: a dispatchable plan whose Status first word is PLANNED or PLAN shows blocked_by "spec not written"
  - id: M3
    text: "**Intent approved:** no adds 'intents need approval' with or without a Filed date"
  - id: M4
    text: a DRAFT/PLANNED plan with no Dispatch header emits dispatch_approval n/a; an explicit Dispatch header is kept
  - id: M5
    text: PROPOSED and SPEC WRITTEN plans and an open dispatch behave exactly as before
must_not:
  - id: N1
    text: "a DRAFT plan shows 'ready on your go' — red today"
  - id: N2
    text: "a PLANNED plan with Intent approved: no and no Filed date shows no intent blocker — red today"
  - id: N3
    text: "a DRAFT plan with no Dispatch header shows dispatch_approval unknown (orange 'needs your decision') — red today"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, N1, N2, N3]
    kind: offline
    command: "pytest scripts/tests/bin/test_vectordb_bug_metrics.py (new tests red on the pre-fix head) plus bats scripts/tests/plugins/grafana_dashboard_bugs.bats"
    intent: The plans table says a plan is waiting on its spec, not on you, until the spec is reviewed; finished specs still say "ready on your go".
  - id: E2
    proves: [M1, M2, M3, M4]
    kind: live
    command: "Claude, after the operator's next hub promote: v1.45.0 plans panel shows plans 1 and 4 'spec not reviewed', plan 5 'spec not written; intents need approval', and no orange 'needs your decision' on those rows"
    intent: The dashboard you screenshotted today stops telling you three plans need your attention.
interface:
  - "k3dm_plan_info blocked_by: new values 'spec not reviewed', 'spec not written'"
```

**Intent approved:** operator, 2026-11-18
**Intent approval note:** "go with 1, and dispatch to Luna" (approving the fix proposed in chat: DRAFT → spec not reviewed, PLANNED → spec not written, Intent approved: no counts regardless of Filed date)
