# Ideas inbox

New ideas land here first, as one line each. They are not plans, not bugs, and not dispatched.

**Rules (operator, 2026-11-07; weekly planning 2026-11-08):**
- A new idea from the operator, an incident, a reading or an agent goes in the table below, not into `docs/plans/`
  and not into a dispatch. Bugs still go to `docs/bugs/`; this inbox is the feature backlog.
- Ideas are promoted at the **weekly sprint planning, Sunday afternoon** (`/sprint-plan`), not at the release cut.
  Claude lists the backlog and the operator picks **1–3 items** for the week. A picked idea becomes a plan in the open
  or next release, within the 5-plan cap, and its row records the plan path.
- Nothing here counts toward the dispatch WIP limit or the 5-plan cap.
- Keep a row short: what, why, and where it came from. Detail belongs in the plan once promoted.

**Triage rules (operator, 2026-11-08):**
- **Every row gets a decision at every planning.** Each `inbox` or `kept` row leaves the session as `promoted`,
  `kept` (stays in the backlog for a named reason) or `dropped`. "Still thinking" is not an outcome.
- **Age limit.** A row kept 4 weeks running without being picked is dropped at the next planning unless the operator
  gives a new reason, written into the row. A dropped row stays in the table with its reason and can come back as a
  new row.
- No row cap: the weekly session is what forces the decisions.

**Status words:** `inbox`, `promoted` (plan path), `kept` (count of weeks and reason, e.g. `kept (2×, waits on D1)`),
`dropped` (one-line reason).

| Added | Idea | Source | Status |
|---|---|---|---|
| 2026-11-06 | Travel with any one laptop (M2, M4 or the M5 hub) and everything still works unless there is no network. Today the platform needs the M5 awake at home, and some cross-machine paths use `.local` names that only resolve on the home LAN; new paths should not assume either. First piece is planned: [`v1.45.0-service-password-travel-bundle`](plans/v1.45.0-service-password-travel-bundle.md); roadmap open decisions D1 (reaching the hub away from home) and D2 (the M2 e2e runner while away). Packing the M5: it will not sleep (`SleepDisabled 1`), so heat and battery are the risk. | operator | inbox |
| 2026-11-07 | Tailscale so any laptop can reach the hub (pull over ssh) from anywhere. Complements the travel bundle but needs the hub reachable; candidate answer to D1. | operator | inbox |
| 2026-11-08 | Smooth `deploy/hub` promotion, so the operator no longer needs Claude to say when and what to run. Three pieces: (1) `make hub-deploy REF=<sha>` on the hub runs promote (typed confirmation kept), appsets-check, appsets-reapply only when ApplicationSet manifests changed, platform-ops and the exporter rollout check, stopping at the first failure; (2) a hub-side check alerts through Alertmanager when the release branch has a CI-green commit `deploy/hub` lacks, naming the commits and the exact command, plus a Grafana "deploy/hub behind by N" stat; (3) a Slack "Promote" approve button (Hermes Slack approval) that runs `hub-deploy` on the hub. The operator stays the gate; no auto-promote on green. Jenkins considered and rejected (deprecated, not deployed). | operator, after the 2026-11-08 bootstrap ("approve from Slack… reduce the friction and make promotion smooth") | inbox |
| 2026-11-08 | CI lint job takes ~17 min (run 42481822700: `make test` 6.4 min, `test-bin` 10.2 min, pytest 2.5 min, all serial on a 4-core runner; the time is ~3,000 fast tests, not a few slow ones). Split the suites into matrix jobs, run BATS files in parallel reusing the fast gate's tree-mutating isolation, and make the `codex dispatch` tests' worker timeouts injectable (~2 min). Target ≤ 7 min. Option 1 alone (matrix) is small enough for a release plan. | operator (Grafana PR checks panel: lint 16.5–18.7 min on #157–#159) | inbox |
| 2026-11-08 | Sprint dashboard in Grafana (beside Bugs/Plans): this week's picks and their state (planned → dispatched → landed → verified), must-do bugs, WIP N/3, plan slots N/5, backlog rows with age and kept count, and picked-vs-landed per week over time. `bin/k3dm-vectordb-metrics` already exports plan and bug state; it would add a reader for `docs/sprints/*.md` and `docs/ideas.md`, so the sprint file needs a fixed, parseable picks table first (`/sprint-plan` Step 3). | operator, 2026-11-08, when adopting weekly planning | inbox |
