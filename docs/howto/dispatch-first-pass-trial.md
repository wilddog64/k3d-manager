# Trial: better first-pass quality from dispatched workers

**Started:** 2026-11-08 (operator: "go ahead to do that")
**Runs for:** the next 3 dispatches from 2026-11-08. The first is
`docs/bugs/2026-11-08-webhook-gemini-ask-has-no-collected-data.md`.
**Decided at:** the first `/sprint-plan` after the third trial dispatch lands.

## Why

On 2026-11-08, all 5 worker outputs Claude reviewed needed a Claude fix or a `resume` before they could land. Review
caught every defect before landing, but each round costs time and Claude's context. Those defects fall into three
classes, and each class is caught by a different net:

| Defect (2026-11-08) | Caught first by |
|---|---|
| Blocked by read the ledger from the repo root, not `K3DM_WORKTREE_ROOT` | worker running the change once against real data; spec review |
| control-node N6 test passed with the hash check removed | worker mutation-testing the guard |
| N4 red on a `sudo` in help text | worker running every touched suite |
| `--check` / `--dry-run` would install Homebrew on Linux | cross-agent diff review; spec review |
| role CI without pipefail, unpinned pip tools | cross-agent diff review |
| `/etc/zshrc` and `glibc-static` on Rocky | worker probing a real Rocky image |

## The three steps

### 1. Definition of done in the spec

Every trial spec carries the section below, copied verbatim. The worker reads the spec in full, so this needs no change
to the dispatcher. While the trial runs, `bin/k3dm-codex-dispatch` has an open dispatch, and the prompt heredoc can't
change until it lands. If the trial is kept, the text moves into the prompt heredoc (`_dispatch_start`).

```markdown
## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed, not only the new tests. For each, give the command, the exit
   code and every error line. An error you can't explain is a failure, not a pass. If the sandbox blocks a test, say
   so and name it; don't skip it silently.
2. For each `must_not` item: break the guard that enforces it (comment out the check, invert the condition), run its
   test, show it red, then restore the guard and show it green. List any `must_not` whose test stayed green with the
   guard broken.
3. Where the spec allows a read-only run against real data (a real file, a real ledger, a real container image), run
   the changed code once that way and paste what it printed. Otherwise say "no read-only real-data run possible" and
   why.
4. List every place where you chose something the spec did not decide (a default, a path, a mode, an edge case).
```

### 2. Cross-vendor diff review before Claude's review

When the worker exits successfully, a reviewer from the other vendor reviews the diff against the spec: Flash
reviews Luna's work, and Luna reviews Flash's. It is linked to the task:

`bin/k3dm-codex-dispatch start --spec <review brief> --slug <slug>-review --parent <slug> --role review --agent <other>`

- The brief gives the reviewer the spec and the worker's diff, and asks for findings only, with file:line, the input
  that breaks it, and the spec line it violates. The reviewer changes no files.
- Findings are advisory. Claude checks each one, sends the real ones back to the worker by `resume`, and records the
  rest as noise.
- Claude still reviews last, before `codex-land`.
- The diff goes inline in the brief, `docs/reviews/<slug>-review.md`, committed before `start` (settled on first use,
  2026-11-08). Untracked new files are included with `git add -N` before `git diff`, then unstaged again.
- `start` runs the intent gate for review children too. The operator approves each brief, and the brief carries
  `**Intent approved:**` (operator, 2026-11-08, choosing this over exempting `--role review` from the gate).
- `start` also needs a `## Files` section with a backticked path: list the files under review, marked read-only.

### 3. Spec review by a second agent before intent approval

Before Claude shows the operator the intents of a trial spec, an agent that did not write it runs `/spec-review`
against it. The agent also answers: what does the spec leave undecided that a worker would have to guess (paths,
modes, platforms, defaults)? Claude fixes the spec, and then asks for intent approval.

## What we measure

For each trial dispatch, recorded in the table below:
- **Rework:** did the land need a Claude fix or a `resume`? How many rounds?
- **Caught by:** for each defect, the step that caught it first (worker DoD, cross-review, spec review, Claude review,
  verifier, live).
- **Noise:** cross-review findings Claude rejected.
- **Cost:** extra agent runs and roughly how long they took.
- **Tokens:** total for the land: worker runs (the `tokens used` line of each codex log), review children,
  spec-review subagents and every rework round (operator, 2026-11-08). The question it answers: tokens per land that
  needed no rework, against the baseline.

The baseline is 2026-11-08: 5 of 5 lands needed rework, and every defect was caught at Claude review or later.

| Dispatch | Worker | Reviewer | Rework rounds | Caught by (defect → step) | Noise | Tokens (worker + reviews + rework) | Notes |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

## Open points

- WIP: decided by the operator on 2026-11-08 ("let make review as exampt"). A review child changes no files and does
  not count toward the limit of 3 (CLAUDE.md, Dispatch WIP limit).

## Trial 1 log

- 2026-11-08, step 3 (spec review, Sonnet subagent, about 1 minute): 1 blocker and 4 should-fix findings, all
  confirmed against the code. The draft named the wrong collector (`bin/cluster-status`; `hostinger-status` runs
  `_smoke_test_services`). It missed that job output reaches `question` (an injection path into collector choice),
  and that `_parse_gemini_observations` can file bug docs from fenced log text. It also had a vacuous N1, and an M3
  and M4 that couldn't be asserted. A worker would have built the wrong thing on the first finding alone.

## Trial 2 log

- 2026-11-08: `docs/bugs/2026-11-08-slack-hostinger-status-duplicates-cluster-status.md`. Process slip: Claude asked
  for intent approval before the step-3 spec review. The review ran right after; if it changes any approved intent, the
  operator re-approves before dispatch.
- Step 3 result (Sonnet, about 30 s): 3 should-fix and 2 nits, all confirmed. A stale allowlist copy in
  `docs/architecture/cloudflare-slack-relay.md:82`. M1 was only checkable by a source grep; it now has a relay
  behaviour test using the `relay.test.mjs` harness. N2 was not testable black-box; it is now a diff check. The
  `hostinger-status` job-thread command was undecided; it is now explicitly out of scope. E1's intent changed, so the
  operator is asked to approve again: the slip cost one extra approval round.
- 2026-11-08: operator re-approved E1 ("E1 intent approved"). Ready for dispatch when a WIP slot frees.
