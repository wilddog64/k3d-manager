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
| 1 | 2026-11-15 | same, same brief | Argon | APPROVE WITH CHANGES | 2 / 5 / 2 | 6 | 1 partial | 4 (see below) | Gemini quota, 334 s |

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

### Pair 1 Argon findings, scored by Claude (2026-11-15)

- BLOCKER-1 (standalone one-liners break `test_test_tripwire.py:21-47`): **confirmed, overlaps** Fable BLOCKER 2.
- BLOCKER-2 (parallel completion predicate `rc<126 && rc!=2` would count an exit-3 abort as complete; preflight
  before `_run_parallel`, because `--retry-failed` at `Makefile:1745` reruns every file of a stage that is missing a
  tool): **confirmed**. It partly overlaps Fable BLOCKER 1, but Argon calls exit 3 "safe" once a preflight runs, and
  misses that bats `abort()` mid-run exits 1. Fable's sharper point stands.
- MAJOR-1/2 (per-runner exit table; keep `test-python` as the composite stage): confirmed, but these restate the
  design's open questions.
- MAJOR-3 (`FAKE_REPO` needs `bin/k3dm-test-stage` symlinked): **confirmed, unique**.
- MAJOR-4 (latent divergences): **partly refuted**. The CLUSTER_ROLE "bug" is wrong because the dispatcher resets an
  unsupported role to infra (`scripts/k3d-manager:334-344`). The conftest.py skip divergence between standalone
  `test-python-unit` (`Makefile:1485-1486`) and test-all is real but latent (there is no `scripts/tests/bin/conftest.py`).
- MAJOR-5 (log-line contract: `bin/k3dm-test-metrics:55-73`, `[make] python3 <f>`): **confirmed, overlaps** Fable
  MAJOR, with more line detail.
- MINOR-1 contract readers: overlaps Fable on `test_test_tripwire.py`, `suite_discovery.bats`, `make_targets.py` and
  `cloud_actions.py`. **Unique, confirmed:** the `K3DM_JUNIT_XML` writer (`scripts/lib/webhook/lifecycle.py:193`) and the
  tripwire `TMPDIR` coupling with `conftest.py`.
- Q3 note: the dispatcher's `test` calls `_ensure_bats`, which can run `brew install bats-core`
  (`system.sh:1662-1663`); the stage script must check `command -v bats` first. **Confirmed, unique.**
- Missed compared with Fable: MAKEFLAGS exported to every recipe; the plist runs `test-metrics`, not test-all; the land
  test is caller-supplied; bats `abort()` exits 1.

**Pair 1 read:** both reviewers gave the same verdict and agreed on both blockers in substance. Fable was sharper on the
exit-code blocker and caught MAKEFLAGS. Argon found more contract readers and three concrete unique issues
(`_ensure_bats` network install, `FAKE_REPO` symlink, retry amplification). Argon had one partly refuted claim; Fable
had none. Argon's quality is close enough on this pair to keep Argon-first; one pair is not a verdict.

### Pair 2: hub-promote containment diff (Sol run 2, uncommitted), 2026-11-15

High-risk land call (`bin/k3dm-hub-promote` moves the ref the production hub deploys from). Both reviewers got the same
staged diff and spec, blind to each other and to Claude's gate, pre-fix and verifier results. Argon:
`gemini-4-argon-medium` via agy, read-only. Fable: background agent, read-only, scratch mirrors only.

**Verdicts:** Argon APPROVE WITH CHANGES; Fable LAND WITH CHANGES, keep the bug OPEN.

Scored by Claude against the code and real history:

- Fable MAJOR-1 (the squash check does not fire on the incident: `git merge-tree --write-tree` of deploy/hub 9f5f0d89
  into the target conflicts): **confirmed, unique, decisive**. Claude reproduced it in a scratch repo borrowing the
  main object store: rc 1 with 73 conflicts against 34707659, 24 against the squash aa1196ed, 95 against c4d647bf.
  deploy/hub was promoted mid-release; PR #160 gained commits before the squash. Every toy-repo test, the independent
  verifier and Argon missed it because none replayed the real SHAs.
- Fable MAJOR-2 (`hub-promote.md` overstates the squash case): confirmed, follows from MAJOR-1.
- Fable minor-3 (`.github/copilot-instructions.md:42,138` still describe BREAK_GLASS as skipping checks): confirmed,
  unique; a missed contract reader.
- Fable minor-4 (make expands `$` in `SKIP_CHECK_RUNS_REASON` passed as a make variable): unique; not reproduced by Claude.
- Fable minor-5 (reason allows control characters; no injection): unique, accepted as low risk.
- Fable minor-6 / Argon MAJOR-1 (the "before fetching" `!= *"From "*` clause cannot fail): **overlap, confirmed by
  both**; Argon rated it MAJOR with a concrete mutation, Fable minor (die text and unchanged hub carry the test).
- Argon minor-2 (E10 make test passes with the `Makefile:478` change reverted, because `:299` falls back to
  `$SKIP_CHECK_RUNS`): **confirmed, unique** (Claude read `:299`).
- Argon minor-3 (E9 M5 loop reads only the newest tag and one static reason): unique, plausible, not reproduced.
- Fable minor-7 (an exported flag skips checks on every promote): by design; noted.
- Mutants: Fable ran seven (m1 to m7), all red. Argon ran the suites only.

**Pair 2 read:** opposite of pair 1's closeness. Both found the test-strength issues, but only Fable tested the change
against the incident it claimed to fix, and that finding reverses the land decision. On a high-risk land call that is
the case for escalating to Fable; Argon-first stays the default for low-risk work. Cost: Fable 128K tokens, 22 tool
calls, about 10 minutes.
