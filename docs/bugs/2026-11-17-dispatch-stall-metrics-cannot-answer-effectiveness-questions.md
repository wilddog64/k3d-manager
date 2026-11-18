# Bug: stall recovery metrics cannot answer whether detection and recovery work

**Status:** OPEN
**Priority:** P3 (proposed: a measurement gap; no wrong behaviour, but the phase 2 gate has no evidence behind it)
**Introduced by:** `docs/bugs/2026-11-14-dispatch-stall-a-detector.md` (v1.44.1) for detection; stages B and C are not built yet
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-17 (Q4 baseline decided; priority and placement at triage)
**Prior art:** `docs/bugs/2026-11-14-dispatch-stall-*.md` (exact-slug pass; `find-similar-docs` not run, vector store needs the hub context) — read, none records these four measures. `docs/bugs/2026-11-14-dispatch-stall-metrics-emit-no-zero-series-without-events.md` — related dashboard series, different gap.
**Filed:** 2026-11-17

## Questions the dashboard should answer

1. **Detection precision:** how many detected hangs were genuinely stalled?
2. **Recovery success rate:** how many stalled tasks resumed and eventually completed?
3. **False recovery rate:** how often did recovery interrupt an agent that was still making progress?
4. **Human attention saved:** how many minutes of manual investigation or intervention were avoided?

## What the ledger holds today

Read 2026-11-17 from `~/.local/share/k3d-manager/worktrees/ledger.jsonl` (3609 rows): one real `stall_detected`,
`e8-toy-stall` (the planted E8 live check, `silent_s` 2705, `killed` 0), then `abandon`. No `stall_diagnosis`,
`stall_decision` or `stall_resume` row exists, and nothing in `bin/` writes the last two: only
`bin/k3dm-dispatch-metrics` reads them. Stages B (approval/resume) and C (diagnose) are carried to v1.45.0.

| Question | Gap |
|---|---|
| 1 | `stall_detected` (`bin/k3dm-dispatch-stall-watch:74`) records no ground truth. The detector does not kill (`killed: 0`), so the run itself can supply it: record the agent log size at detection, and a follow-up event after a fixed delay saying whether the log grew. Grew → false alarm. |
| 2 | Computable once stage B writes `stall_resume`; `bin/k3dm-dispatch-metrics` already joins resume → land/abandon/stalled again. Missing only a rate panel (landed after resume ÷ resumed) that shows its denominator. |
| 3 | Stage B's `stall_resume` spec has `rc` only. It needs the log size at resume, compared with the size at detection: output between detection and resume means recovery interrupted live work. |
| 4 | Needs a baseline. The ledger gives the measured side (silence before detection, minutes to decide). **Decided (operator, 2026-11-17): the baseline is hang-to-noticed times taken from past hang bug docs**, not an assumed constant. First data point: `docs/bugs/2026-11-14-codex-dispatch-silent-running-raises-no-alert.md`, hang 2026-11-14 01:34Z, noticed about 15:00Z when the operator asked: about 13 h. |

## Fix direction (not decided)

- Fold the question 3 field (and the question 2 panel) into stage B's spec before it is dispatched; a spec edit, not new work.
- One detector change for question 1 (log size at detection plus a delayed follow-up event).
- Question 4: collect the pre-detector hang docs that record both a start and a noticed time (the 2026-11-14 doc is the first),
  publish their median hang-to-noticed minutes as a fixed baseline series, and show attention saved per stall as baseline
  minus measured silence-before-detection, with the number of baseline docs on the panel. Docs that lack either time are
  listed and skipped, not guessed.
- Every rate panel shows its count beside it: until a handful of real stalls exist, 1/1 reads as 100%.
