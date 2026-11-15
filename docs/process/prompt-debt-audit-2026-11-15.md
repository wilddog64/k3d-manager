# Prompt-debt audit — 2026-11-15

Read-only pass by Claude over `CLAUDE.md` (10.3 KB), the parent `../CLAUDE.md`, `AGENTS.md` (5.7 KB), `GEMINI.md`
(6.2 KB), `docs/process/rules.md` (22 KB), the Claude memory index (264 files) and `memory-bank/`. Frame: Lance Martin,
"Prompt instructions accumulate as debt" (AI Engineer 2026): instructions that tax cost, break accuracy (contradictions)
or break outright (dated configuration). Each finding was checked against the repo or machine on 2026-11-15. Nothing
was changed; every row needs an operator decision.

## Break outright — dated or dead configuration

| # | Instruction | Evidence | Recommend |
|---|---|---|---|
| D1 | `CLAUDE.md` + `rules.md`: "Thinking Budget: capped at 8,192 tokens (set via .envrc)" | `.envrc` has no thinking/effort setting; current models take effort levels rather than a fixed thinking budget | **Cut** (or replace with the real effort setting, if one exists) |
| D2 | `CLAUDE.md` + `rules.md`: "RTK (Rust Token Killer) is active for all CLI output" | no `rtk` on PATH, in `~/.cargo/bin` or `/opt/homebrew/bin`; no hook in any `settings*.json` | **Cut** |
| D3 | `../CLAUDE.md`: "ALWAYS use the code-review-graph MCP tools BEFORE Grep/Glob/Read" | not configured in `~/.claude.json`; no such tools in session. A forced lookup with nothing to look up | **Cut**, or reinstall the server if it is still wanted |

## Break accuracy — contradictions

| # | Rule A | Rule B | Recommend |
|---|---|---|---|
| C1 | PR creation gate (`CLAUDE.md`, `rules.md`): no PR until CI green, **Copilot comments addressed**, Gemini live smoke, scope check | Copilot can only review an open PR; memory `feedback_never_draft_pr`: open a normal PR, *then* work CI/Copilot/smoke on it | **Rewrite** the gate as a *merge* gate (open PR → CI, Copilot, smoke, scope → merge) |
| C2 | PR gate: "**Gemini** live smoke test" | Acceptance rule + `GEMINI.md`: "live evidence by the operator or Claude, **never Gemini**"; memory: "live-smoke gate goes to **Codex**" | **Decide** who runs the smoke; one name in one place |
| C3 | Status first word: `OPEN`, `LANDED` or `VERIFIED` only | the dashboard (`prior_art.py`) and pre-commit treat `LIVE-VERIFIED` as a state; 175 docs use it | **Add** `LIVE-VERIFIED` to the rule |
| C4 | WIP rule (2026-11-07): "a P3 is filed with `**Waiting on:** dispatch`" | Capture-first (2026-11-11): every captured bug gets `**Waiting on:** operator decision`, no dispatch until triage | **Cut** the WIP rule's filing clause (capture-first supersedes it) |
| C5 | `AGENTS.md` dispatch: "Do not run git commit" | `AGENTS.md` coordinator section: "End each commit with a `Coordinator:` trailer" (same file, read by workers) | **Scope** the coordinator section to coordinator sessions explicitly; live check E3 of the coordinator bug should ask for the ledger event + the landing commit, not a worker commit |

## Tax cost — load and rituals

| # | Instruction | Evidence | Recommend |
|---|---|---|---|
| T1 | `AGENTS.md` / `GEMINI.md`: "Read the full spec **and the current memory-bank context** before acting" | `activeContext.md` 252 KB + `progress.md` 199 KB ≈ 110K tokens. The 65-second Sol run on 2026-11-15 billed 245K input tokens for 1.8K output | **Cut** for workers (the spec is the contract); **archive** memory-bank by release so the live part stays small |
| T2 | Memory-bank update "mandatory and immediate, after every completed action" | 7+ status-only commits on 2026-11-15; the files are the 451 KB above | **Measure**: trial "update at task boundaries and before `/compact`" for one release, then compare handoff quality |
| T3 | Shared `plan-cap` block in `AGENTS.md` / `GEMINI.md` (triage cadence, "Claude says triage due") | Coordinator-only process, read by every worker; agy loads *both* `AGENTS.md` and `GEMINI.md` (noted 2026-11-01), so shared blocks are paid twice for Gemini | **Cut** `plan-cap` from worker files; keep `security` and `bug-priority` |
| T4 | Second-agent classification: every captured bug classified by Argon | 43 of 78 bugs filed 2026-11-11…15 carry `**Classified:**` | **Decide**: automate at capture time (hook) or drop; a half-followed rule measures nothing |
| T5 | `CLAUDE.md` "Jenkins is a deprecated demo feature…", `k3s-oci` descoped | features not run | **Keep** one line; cheap. Revisit if more accumulate |

## Keep — earned by evidence

Not rituals in the slide's sense: they check against ground truth and have precedents.

- **Verify before trust** — caught fabricated SHAs; on 2026-11-15 caught the M2 promtool "pass" that ran bash 5, and the Sol worker's empty run.
- **Prove external behaviour before dispatch** — `sort: 8` on Grafana 11.4.0, invented `byRefId` matcher.
- **Test controls / must_not red on pre-fix code** — on 2026-11-15 the Sol worker found an unkillable mutant (m2) this way.
- **Contract readers and writers** — the `sensors.py:114` and CVE-promoter misses.
- **Security rules** — standing policy, not a prompt-quality question.

## Suggested next step

Take C1–C5 and D1–D3 as one docs-only change (each is a cut or a one-line rewrite) once decided at grooming. Run T2
as a measured trial in v1.44.1 or v1.45.0, using `docs/process-metrics.md`. Archive memory-bank (T1) as its own small plan.

## Decisions (operator "go ahead", 2026-11-15)

- **Applied:** D1, D2 (cut from `CLAUDE.md` and `rules.md`), D3 (parent `../CLAUDE.md` is not under git: renamed to
  `CLAUDE.md.disabled-2026-11-15`, rename back to restore), C1 (PR creation gate → merge gate), C3 (`LIVE-VERIFIED` added;
  rule now states what the hook really refuses), C4 (P3 filing clause defers to capture-first), C5 (coordinator section
  scoped to coordinator sessions).
- **Open:** C2 (who runs the release smoke; the gate text still says Gemini), T4 (automate or drop Argon classification).
- **Not started:** T1 (worker memory-bank read + archive), T2 (measured trial), T3 (`plan-cap` out of worker files).
