# Blind review calibration

Step 2 of the review-improvement sequence the operator adopted on 2026-10-31 (recorded in
`docs/plans/v1.43.13-agent-instruction-files-refresh.md`, "Not in this plan"). The goal is to measure
where Claude's PR review differs from the operator's before anyone changes the review instructions.
This step changes no review instruction, skill or prompt.

## Protocol

1. **Claude reviews first and seals the review.** Claude writes its findings to
   `~/.local/state/k3d-manager/calibration/<release>/claude.md`, outside the repo, and records the file's
   SHA-256 in `memory-bank/activeContext.md`. Claude does not print the findings in the terminal or the PR.
2. **The operator reviews without reading Claude's file.** The operator writes findings to
   `~/.local/state/k3d-manager/calibration/<release>/operator.md`, one per line, as
   `file:line — severity (P0–P3) — what is wrong`, or `process — severity — what` for a finding that is
   not in one file. The first line says what the operator covered, for example
   `Coverage: release scope, PR body, hub-cutover rollback; did not read webhook code`. A process-level
   review is valid: the operator does not need to read every change. Nothing written there is shown to Claude until the
   operator says the review is finished.
3. **Claude compares.** Claude first checks that `claude.md` still matches the recorded SHA-256, then
   classifies each finding:
   - **both** — both reviewers found it; note any severity disagreement;
   - **missed** — the operator found it and Claude did not;
   - **over-flagged** — Claude found it and the operator judges it not a defect;
   - **Claude-only, accepted** — Claude found it and the operator agrees it is real;
   - **not covered** — Claude found it in an area the operator did not review. The operator judges these
     afterwards; they count as neither missed nor over-flagged;
   - **missed by both** — a defect CI, Copilot or a live run found after both reviews.
4. **Record.** Claude writes `docs/calibration/<release>.md` with both reviews and the table, and appends
   one line to the running tally in `docs/calibration/README.md`. Real findings are fixed or filed as
   bugs in the usual way.

Run it on 3–4 release PRs before drawing conclusions. The first is v1.43.12.

## What the results feed

Step 3 (tacit-rule mining) reads the **missed** and **over-flagged** rows across PRs. A rule enters the
review instructions only when the same kind of miss recurs. Step 5 (adversarial reviewers) is added only
for a miss class the tally shows.
