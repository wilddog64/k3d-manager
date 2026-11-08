# Ideas inbox

New ideas land here first, as one line each. They are not plans, not bugs, and not dispatched.

**Rules (operator, 2026-11-07; release grooming 2026-11-08):**
- A new idea from the operator, an incident, a reading or an agent goes in the table below, not into `docs/plans/`
  and not into a dispatch. Bugs still go to `docs/bugs/`; this inbox is the feature backlog.
- Ideas are ranked at **release grooming** (`/release-groom`, Sunday afternoon and at each release cut), not added
  to a release by default. A ranked idea becomes a plan, either in the next release by displacing a not-started plan
  (5 plans per release, never more) or in the ordered backlog of written plans in `docs/roadmap.md`. Its row records
  the plan path.
- Nothing here counts toward the dispatch WIP limit or the 5-plan cap.
- Keep a row short: what, why, and where it came from. Detail belongs in the plan once promoted.

**Triage rules (operator, 2026-11-08):**
- **Every row gets a decision at every grooming.** Each `inbox` or `kept` row leaves the session as `promoted`,
  `kept` (stays in the backlog for a named reason) or `dropped`. "Still thinking" is not an outcome.
- **Age limit.** A row kept 4 weeks running without being picked is dropped at the next grooming unless the operator
  gives a new reason, written into the row. A dropped row stays in the table with its reason and can come back as a
  new row.
- No row cap: grooming is what forces the decisions.

**Status words:** `inbox`, `promoted` (plan path), `kept` (count of weeks and reason, e.g. `kept (2×, waits on D1)`),
`dropped` (one-line reason).

| Added | Idea | Source | Status |
|---|---|---|---|
| 2026-11-06 | Travel with any one laptop (M2, M4 or the M5 hub) and everything still works unless there is no network. Today the platform needs the M5 awake at home, and some cross-machine paths use `.local` names that only resolve on the home LAN; new paths should not assume either. First piece is planned: [`v1.45.0-service-password-travel-bundle`](plans/v1.45.0-service-password-travel-bundle.md); roadmap open decisions D1 (reaching the hub away from home) and D2 (the M2 e2e runner while away). Packing the M5: it will not sleep (`SleepDisabled 1`), so heat and battery are the risk. | operator | kept (1×, groomed 2026-11-08: its plans `v1.45.0-service-password-travel-bundle` and `-tailnet-read` are already written; rank after v1.44.0) |
| 2026-11-07 | Tailscale so any laptop can reach the hub (pull over ssh) from anywhere. Complements the travel bundle but needs the hub reachable; candidate answer to D1. | operator | kept (1×, waits on the travel bundle's D1 decision) |
| 2026-11-08 | Smooth `deploy/hub` promotion, so the operator no longer needs Claude to say when and what to run. Three pieces: (1) `make hub-deploy REF=<sha>` on the hub runs promote (typed confirmation kept), appsets-check, appsets-reapply only when ApplicationSet manifests changed, platform-ops and the exporter rollout check, stopping at the first failure; (2) a hub-side check alerts through Alertmanager when the release branch has a CI-green commit `deploy/hub` lacks, naming the commits and the exact command, plus a Grafana "deploy/hub behind by N" stat; (3) a Slack "Promote" approve button (Hermes Slack approval) that runs `hub-deploy` on the hub. The operator stays the gate; no auto-promote on green. Jenkins considered and rejected (deprecated, not deployed). | operator, after the 2026-11-08 bootstrap ("approve from Slack… reduce the friction and make promotion smooth") | promoted (`docs/plans/v1.44.0-hub-deploy-one-command.md`, part 1 only; parts 2–3 stay here) |
| 2026-11-08 | CI lint job takes ~17 min (run 42481822700: `make test` 6.4 min, `test-bin` 10.2 min, pytest 2.5 min, all serial on a 4-core runner; the time is ~3,000 fast tests, not a few slow ones). Split the suites into matrix jobs, run BATS files in parallel reusing the fast gate's tree-mutating isolation, and make the `codex dispatch` tests' worker timeouts injectable (~2 min). Target ≤ 7 min. Option 1 alone (matrix) is small enough for a release plan. | operator (Grafana PR checks panel: lint 16.5–18.7 min on #157–#159) | kept (1×, groomed 2026-11-08: ranked below the v1.44.0 picks; costs CI time, not correctness) |
| 2026-11-08 | Live smoke checks as Hermes sensors, so a shipped path that is broken live pages within a day instead of waiting for the operator to hit it. Candidates: a signed slash-command probe to the relay (answers inside Slack's 3 s), a signed test click to `/slack/interactivity` (expects "denied"), the Slack app manifest via `apps.manifest.export` (Interactivity on, request URL right, same app as the `k3dm-slack-webhook` webhook; needs a new Slack config token, operator-approved), and a webhook self-ask "gemini … hostinger status". A human click on a real button stays manual. Each sensor must be silent on a healthy stack. | Claude, 2026-11-08 quality review: Hermes buttons never worked (Interactivity off, wrong app), Gemini asks never collected data, `/hostinger-status` timed out; all passed offline tests | promoted (`docs/plans/v1.44.0-hermes-slack-config-sensors.md`, manifest + unsigned probe; signed probes not taken) |
| 2026-11-08 | Sprint dashboard in Grafana (beside Bugs/Plans): this week's picks and their state (planned → dispatched → landed → verified), must-do bugs, WIP N/3, plan slots N/5, backlog rows with age and kept count, and picked-vs-landed per week over time. `bin/k3dm-vectordb-metrics` already exports plan and bug state; it would add a reader for `docs/sprints/*.md` and `docs/ideas.md`, so the sprint file needs a fixed, parseable picks table first (`/sprint-plan` Step 3). | operator, 2026-11-08, when adopting weekly planning | kept (1×, now a grooming dashboard over `docs/grooming/*.md`; needs a few grooming records first) |
