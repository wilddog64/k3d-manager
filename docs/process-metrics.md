# Process metrics: capture first, triage later

**Started:** 2026-11-11 (operator: "sounds good, and we can measure how this can improve our process")
**Rule:** `CLAUDE.md`, Versioning and release scope, "Capture first, triage later". Only P0/P1 are fixed without
triage; P2/P3 are captured and triaged at `/release-groom`.
**Review:** at the grooming after v1.44.0 merges, and again after v1.45.0. Claude fills the table from git, `gh` and
`docs/bugs/`, then recommends keep, adjust or revert.

## What we measure

| Metric | How | Better means |
|---|---|---|
| Cycle time | release branch first commit → PR merged, in days | shorter |
| Bugs fixed inside the release | `docs/bugs/` filed in the window whose fix landed before the merge, by priority | fewer P2/P3 (P0/P1 unchanged) |
| Captured, not fixed | P2/P3 filed in the window and still `OPEN` at the merge | the rule working |
| Triage outcome | of captured P2/P3: `patch` / `carry` / `close` at the post-merge grooming | some `close`: work we never needed |
| **Safety: escalations** | captured P2/P3 later raised to P1/P0, or that caused an incident before triage | **0** |
| Escaped bugs | filed after the merge with `**Introduced by:**` this release | not higher than baseline |
| Triage sessions | per session: trigger (count or age), bugs triaged, minutes, share closed | under ~15 min; some closed |
| Classification agreement | bugs where Claude's Priority equals the second agent's; disagreements by direction | high agreement; disagreements reviewed |

**Tuning:** the operator expects these rules to change as data comes in; record each change here with its date and reason.

- 2026-11-11: triage trigger 10 → 20 captured (or oldest 7 days). v1.43.15 filed ~80 bugs in ~4 days (~20/day), so 10 would fire about twice a day (operator: "let's set threshold to 20 to see that will be a better choice").

**Revert trigger:** any escalation that the wait made worse. Claude reports it at once, not at the review.

## Baseline (old rule: P2s aimed at the open release)

Counted 2026-11-11 by Claude from `docs/bugs/` filename dates and `gh pr list`. "Fixed" is the Status today, so it
includes fixes that landed after that release merged.

| Release | Window | Cycle (days) | Filed | P1 / P2 / P3 | Fixed | P2 fixed |
|---|---|---|---|---|---|---|
| v1.43.13 | 2026-10-31 → 11-01 | 1 | 44 | 1 / 17 / 26 | 13 | 7 |
| v1.43.14 | 2026-11-02 → 11-07 | 6 | 61 | 8 / 31 / 22 | 41 | 23 |
| v1.43.15 | 2026-11-08 → open | ≥ 4 (open) | 77 | 2 / 33 / 42 | 44 | 24 |

v1.43.15 switched rules partway (2026-11-11), so it is a transition release. v1.44.0 is the first full release
under the new rule.

## Results

| Release | Cycle (days) | Fixed in release (P0-1 / P2-3) | Captured open at merge | Triage p/c/x | Escalations | Escaped |
|---|---|---|---|---|---|---|
| v1.44.0 | | | | | | |
| v1.45.0 | | | | | | |

## Triage sessions

| Date | Trigger | Bugs triaged | Outcome | Classification agreement | Notes |
|---|---|---|---|---|---|
| 2026-11-12 | post-merge `/release-groom` (v1.43.15) | 79 | carry 26, close 6, status corrected 6, out at P3 cap 9, passed over 31 (7 of them v1.43.16 picks, not counted) | Argon on 76: 43 equal, 29 higher, 4 lower; operator kept Claude's P on all 33 | Argon read "degraded with a workaround" as P2 for hygiene and test-only bugs: one systematic difference, not 29 separate ones. 869,027 Argon tokens, uncounted by any dashboard. Claude first computed the P3 cap with Argon's raises standing (17 vs 10) and corrected it before recording. `docs/grooming/2026-11-12.md` |

## Review findings log (side-by-side Fable trial)

Started 2026-11-12 (operator: "we can try to experience this side by side workflow a bit"). Every dispatch diff,
first run and each correction, gets a Fable review in parallel with Claude's own read, before land. Fable is briefed
with the diff, spec and related files, never Claude's findings. Claude verifies every finding against the code.
One row per reviewer per review. **Confirmed** = held up when checked; **Rejected** = wrong or not a defect;
**Overlap** = also found by the other reviewer; **First-use** = would have failed on the first live run.
Judged after 2–3 releases.

| Date | Dispatch (run) | Reviewer | Tokens | Findings | Confirmed | Rejected | Overlap | First-use |
|---|---|---|---|---|---|---|---|---|
| 2026-11-12 | dev-hub-vcluster-b (1) | Fable | 107,610 | 13 | 11 (2 low pending) | 0 | 1 | 3 |
| 2026-11-12 | dev-hub-vcluster-b (1) | Claude | — | 2 | 2 | 0 | 1 | 1 |
| 2026-11-12 | dev-hub-vcluster-b (2) | Fable | 135,495 | 5 + 7 low | 5 checked (H1 reproduced by both; M3 read by Claude), rest plausible | 0 | 1 | 2 (M2 teardown advice, M3 silent exit) |
| 2026-11-12 | dev-hub-vcluster-b (2) | Claude | — | 1 | 1 | 0 | 1 | 0 |
| 2026-11-12 | dev-hub-vcluster-b (3) | Fable | 132,304 | 5 + 1 unverified | 5 (F1 reproduced by Fable and Claude; F2 read plus Fable mutant; F4 chart templates read by Claude) | 0 | 1 | 4 (protected-branch test can't fail, N4 weak, chart no-op keys, untested BRANCH paths) |
| 2026-11-12 | dev-hub-vcluster-b (3) | Claude | — | 1 | 1 | 0 | 1 | 0 |
| 2026-11-12 | dev-hub-vcluster-b (4) | Fable | 110,524 | 6 | 2 verified by Claude (BRANCH test indistinguishable, empty-kubeconfig -f check); 4 read-plausible, sent as low | 0 | 0 | 6 |
| 2026-11-12 | dev-hub-vcluster-b (4) | Claude | — | 0 | 0 | 0 | 0 | 0 |
| 2026-11-13 | dev-hub-vcluster-b (5) | Fable | 121,151 | 11 | 4 verified by Claude (no probe on create path, dead inner branch, DRY_RUN fails, N1 too narrow); 7 read-plausible, 5 sent | 0 | 0 | 1 (first `dev-hub-up` may hit an unready proxy, inferred) |
| 2026-11-13 | dev-hub-vcluster-b (5) | Claude | — | 0 new (6 round-4 fixes re-checked) | 0 | 0 | 0 | 0 |
| 2026-11-13 | deploy-hub-behind-alert (1) | Fable | 93,816 | 13 | 6 verified by Claude (cap test can't fail, unknown cycle resets for:, lookup_failed unread, except-pass reads none, split outside try, hardcoded origin); 7 sent; 3 deferred (squash ancestry, rollback, SHA length) | 0 | 0 | 2 (silent producer, alert reset) |
| 2026-11-13 | deploy-hub-behind-alert (1) | Claude | — | 0 | 0 | 0 | 0 | 0 |
| 2026-11-13 | hermes-slack-config-sensors (0) | Fable | 106,033 | 14 | 4 confirmed by Claude (transient rotate error sets regenerate, pre-lock double rotate, notified set on failed post, N6 test unstubbed); independent verifier also found N8 GREEN, N4 weak, M6 untested — all sent in correction 1 | — | — | — | — |
| 2026-11-13 | hermes-slack-config-sensors (0) | Claude | — | 0 new beyond Fable | 0 | 0 | 0 | 0 |
| 2026-11-13 | dev-hub-vcluster-b (6) | Fable | 92,567 | 6 | 3 shown by mutant/ad hoc test, 1 inferred, 1 nit; all low → captured as P3 `docs/bugs/2026-11-13-dev-hub-b-dry-run-and-untested-probe-paths.md`, not a round 7 | — | — | — | — |
| 2026-11-13 | dev-hub-vcluster-b (6) | Claude | — | 0 | 0 | 0 | 0 | 0 |
| 2026-11-13 | dev-hub-vcluster-b (7) | — | — | — | No Fable review: mechanical split of `dev_hub_up` (pre-commit `_agent_audit` if-count gate, never run in six rounds because the worker cannot commit); Claude checked it as a verbatim move | — | — | — | — |

Quota (operator gauge, 2026-11-13): the two 2026-11-13 Fable reviews (215K tokens together) used 4% of the Fable weekly limit, about 2% per review, so roughly 50 reviews fit in a week.
