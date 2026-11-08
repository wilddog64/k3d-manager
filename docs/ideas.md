# Ideas inbox

New ideas land here first, as one line each. They are not plans, not bugs, and not dispatched.

**Rules (operator, 2026-11-07):**
- A new idea from the operator, an incident, a reading or an agent goes in the table below, not into `docs/plans/`
  and not into a dispatch. Bugs still go to `docs/bugs/`; this inbox is for things we would like to build.
- Ideas are promoted only at a release boundary: when a release branch is cut (`/post-merge`), Claude lists the
  inbox and the operator picks what to promote. A promoted idea becomes a plan in the release it is assigned to,
  within the 5-plan cap, and its row records the plan path.
- Nothing here counts toward the dispatch WIP limit or the 5-plan cap.
- Keep a row short: what, why, and where it came from. Detail belongs in the plan once promoted.

**Status words:** `inbox`, `promoted` (plan path), `dropped` (one-line reason).

| Added | Idea | Source | Status |
|---|---|---|---|
| 2026-11-06 | Travel with any one laptop (M2, M4 or the M5 hub) and everything still works unless there is no network. Today the platform needs the M5 awake at home, and some cross-machine paths use `.local` names that only resolve on the home LAN; new paths should not assume either. First piece is planned: [`v1.45.0-service-password-travel-bundle`](plans/v1.45.0-service-password-travel-bundle.md); roadmap open decisions D1 (reaching the hub away from home) and D2 (the M2 e2e runner while away). Packing the M5: it will not sleep (`SleepDisabled 1`), so heat and battery are the risk. | operator | inbox |
| 2026-11-07 | Tailscale so any laptop can reach the hub (pull over ssh) from anywhere. Complements the travel bundle but needs the hub reachable; candidate answer to D1. | operator | inbox |
| 2026-11-08 | Smooth `deploy/hub` promotion, so the operator no longer needs Claude to say when and what to run. Three pieces: (1) `make hub-deploy REF=<sha>` on the hub runs promote (typed confirmation kept), appsets-check, appsets-reapply only when ApplicationSet manifests changed, platform-ops and the exporter rollout check, stopping at the first failure; (2) a hub-side check alerts through Alertmanager when the release branch has a CI-green commit `deploy/hub` lacks, naming the commits and the exact command, plus a Grafana "deploy/hub behind by N" stat; (3) a Slack "Promote" approve button (Hermes Slack approval) that runs `hub-deploy` on the hub. The operator stays the gate; no auto-promote on green. Jenkins considered and rejected (deprecated, not deployed). | operator, after the 2026-11-08 bootstrap ("approve from Slack… reduce the friction and make promotion smooth") | inbox |
