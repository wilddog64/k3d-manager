# Reviewer trial: Fable vs Argon

**Started:** 2026-11-15 (operator: "then we can compare Fable and Argon to see how they perform")
**Why:** Fable reviews were the largest extra Claude-quota cost in the week of 2026-11-12 (33% of weekly_all in 31% of
the window). Argon (`gemini-4-argon-medium` via agy) draws on a separate Gemini quota. Reviews now default to Argon, and
Fable is kept for high-risk land calls. This log measures what that trade costs in review quality.

## Method

- **Same input, blind.** Each pair reviews the same artifact (design, spec or diff) with the same brief. Neither sees the
  other's findings or Claude's conclusions. Reviews are read-only and every finding needs file:line or a command.
- **Pairs come from three sources:** (1) Argon re-running a review Fable already did (no new Claude quota); (2) high-risk
  land calls, where Fable runs anyway, get an Argon run too; (3) at most one fresh pair per week by choice.
- **Claude scores each finding** against the code: `confirmed` (real, verified), `refuted` (checked and wrong),
  `unverified` (not yet checked), `style` (true but no behaviour impact). Overlap means both reviewers found the same
  defect.
- **Per pair record:** artifact, minutes, tokens (Fable from the subagent result; Argon from the agy conversation db),
  quota cost, counts per score and severity, unique confirmed findings per reviewer, and verdict.
- **Judge after about 6 pairs or at v1.45.0 grooming.** Key questions: does Argon miss confirmed BLOCKER/MAJOR findings
  that Fable catches? How often is each refuted? What does each confirmed finding cost in quota?

## Log

| # | Date | Artifact | Reviewer | Verdict | Findings (B/M/m) | Confirmed | Refuted | Unique confirmed | Cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-11-14 | Part B M2 stage-runner design (scratchpad draft) | Fable | APPROVE WITH CHANGES | 2 / 3+ / – | 4 spot-checked, 0 refuted | 0 | see below | Claude quota (Fable) |
| 1 | 2026-11-15 | same, same brief | Argon | pending | | | | | Gemini quota |

### Pair 1 baseline: Fable findings on the M2 design (recorded before Argon's run)

- BLOCKER: exit code cannot separate fail from abort for bats/unittest/dispatcher (bats `abort()` exits 1); use output
  evidence (TAP plan vs counts, "Ran N tests"). Confirmed (bats 1.14.0).
- BLOCKER: "pure refactor" is false: `scripts/tests/bin/test_test_tripwire.py:30-47` pins recipe text and the
  `test-all:` prerequisite line; `test-python-unit` set -e vs continue; pytest 3/4/5. Confirmed.
- MAJOR: log-line contract with `bin/k3dm-test-metrics` (5→3 stage mapping); MAKEFLAGS exported to every recipe, so the
  script must unset it; `--file` must not redo stage-level work (`K3DM_RESOLVED_PYTEST`).
- MAJOR: missing contract readers: `test_test_tripwire.py`, `suite_discovery.bats:25-26`, `scripts/ci/fast_gate.sh:39-48`,
  webhook `make_targets.py`/`cloud_actions.py`/`lifecycle.py:215`, `Makefile` test-metrics, `AGENTS.md:22`,
  `GEMINI.md:43`, `.clinerules:248`, `README.md:60`. Draft errors: the plist runs `test-metrics` (not test-all)
  (confirmed), and the land test is caller-supplied.
- Open questions: bin/ script OK; exit 3 only for pytest; keep the dispatcher as the stage-1 runner; land a fact-based
  pinning test with Part B (adopted as correction 8 item 11).
