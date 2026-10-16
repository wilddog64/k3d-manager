# Research paper plan — agent-driven platform engineering case study

**Status:** PLANNED — not started; writing begins after the v2.4 model comparison (see Timeline)
**Filed:** 2026-10-16, at operator request
**Approval:** explicit 2026-10-16 "another thing worth to is to write a resrach paper for what we
are doing (not necessary right now) … plan for it" (operator)
**Related:** `docs/roadmap.md` (Candidate theme — v2.x: model economics; Candidate major — v3.0.0),
`docs/plans/v1.45.1-codex-model-routing-and-efficiency.md`,
`docs/plans/v1.48.0-human-effort-per-release.md`, `docs/howto/cloud-session-requests.md`

This is a planning note, not a release spec. It takes no slot in any release's five-plan cap.

## Working title

*Beyond AI-Assisted Coding: A Longitudinal Case Study of Cost-Constrained, Agent-Driven Platform
Engineering*

## Why this project is worth a paper

Most published evaluations of coding agents use benchmarks: isolated tasks with a test oracle. This
repo covers the whole lifecycle of one platform over more than a year, all in git:

human intent → AI architecture (spec) → agent implementation → verification (BATS, pytest,
mutations, e2e gate) → deployment (ArgoCD) → observability (Grafana, Pushgateway) → incidents →
bug tracking → organisational memory (memory-bank, retros, `docs/issues/`)

Corpus as of 2026-10-16 (`git rev-list --count HEAD`, `ls | wc -l`):

| Artefact | Count | Since |
|---|---|---|
| Commits on the release branch | 1,817 | 2025-08-15 |
| Release tags | 143 | |
| Specs in `docs/plans/` | 328 | |
| Bug docs in `docs/bugs/` | 758 | |
| Issue / review-finding docs in `docs/issues/` | 411 | |
| Retrospectives in `docs/retro/` | 86 | |

## Research questions and evidence

| # | Question | Evidence today | Evidence still to build |
|---|---|---|---|
| RQ1 | Can one experienced engineer coordinate AI agents to develop and operate a complex infrastructure platform? | Git history, releases, specs, retros, bug lifecycle (Filed / Fixed-in / Verified), DR drills | Human effort per verified release (v1.48.0) |
| RQ2 | Does multi-model collaboration outperform a single coding agent? | Codex dispatch metrics per spec (v1.43.3) — observational only | Controlled replay benchmark (roadmap: v2.x model economics, after v2.4) |
| RQ3 | Do more expensive models deliver better verified outcomes? | — | v1.45.1 Codex model routing and efficiency; the same replay benchmark across tiers |
| RQ4 | How much does the agent harness influence engineering performance? | Claude Code CLI vs cloud sessions (`docs/howto/cloud-session-requests.md`), anecdotal | Same specs run under each harness in the replay benchmark |
| RQ5 | Can intent-driven automation reduce manual operational work? | Hub recovery, cloud-bridge, ChatOps (Slack/Hermes), e2e workflows | Intervention ledger (v1.48.0); v2.x intent engine |

**Outcome measure for every RQ: a *verified* outcome**, as the repo already defines it — a spec
landed with its tests green, its mutations shown red, the reviewer's findings resolved, and for
releases, the e2e gate passed. Tokens or minutes per task without that bar would measure activity,
not results.

## Method

- **RQ1, RQ5: longitudinal case study, mixed methods.** Quantitative series from git and the
  Pushgateway history (release cadence, bug inflow and fix lag, operator interventions per release)
  plus qualitative coding of retros and incident docs (what failed, which process rule it produced).
- **RQ2–RQ4: controlled replay.** A frozen benchmark of about 10 already-landed specs of mixed kinds
  (shell plugin, Python producer, dashboard, docs-heavy, bug fix). Each runs from the same base
  commit under each arm (Claude-only, Codex-only, multi-model; model tier; harness). The oracle is
  the spec's own tests plus its recorded mutations. Measures: pass/fail on the oracle, operator
  corrections, tokens or share of weekly quota, wall time.

## Threats to validity (state them in the paper, do not hide them)

- **n = 1 engineer, one repo.** Generalisation is limited; frame it as a case study.
- **The author is the subject**, and Claude also wrote much of the record. Use mechanical sources
  (git, CI, Pushgateway) for numbers; treat memory-bank prose as self-report.
- **Agent reports are untrusted** (fabricated SHAs are documented in this repo). Count only
  independently verified outcomes.
- **Tasks were routed by kind**, so the observational dispatch data confounds model with task. Only
  the replay benchmark answers RQ2–RQ4.
- **Subscription pricing and model versions change** during the study. Record the model ID and plan
  for every run; report quota share, not dollars.
- **Small benchmark.** Results are directional, not statistically significant.

## Data hygiene (start now, costs little)

- Keep model ID, harness and token or quota figures with every dispatch record. The roadmap's
  model-economics theme suggests adding Codex tokens to the dispatch metrics early.
- Snapshot the metrics behind every release (the hub-data export already keeps history).
- Before anything is published: no secrets, tokens, hostnames of private endpoints, or
  customer data. Run the same redaction rules as the repo's security section.

## Timeline

| When | Step |
|---|---|
| Now – v2.0.0 | Data hygiene only. No writing. |
| v1.48.0 | Human effort per release gives the RQ1/RQ5 baseline. |
| v2.4 (+ model-economics theme) | Replay benchmark answers RQ2–RQ4. |
| After that | Draft. Short version first as an experience report; full paper second. |
| v3.0.0 | Possible follow-up paper: the multi-agent product team against this baseline. |

## Venue options (decide when drafting)

- arXiv preprint (cs.SE) first: no gate, establishes the date.
- Industry / experience tracks: ICSE SEIP, FSE Industry, or an MSR mining-challenge style paper on
  the git corpus.
- Practitioner: IEEE Software experience report; the LinkedIn / dev.to pipeline in parallel.

## Open decisions for the operator

- Whether the repo history can be released as a dataset alongside the paper (it holds operator
  notes and infrastructure details; may need a scrubbed export).
- Single paper or two (RQ1/RQ5 longitudinal; RQ2–RQ4 controlled).
