- 2026-10-09: P1 python3 pin LANDED `625b44a7`: templates use python@3.14, installer preflight, Hermes heartbeat (job k3dm-hermes, pushed in `finally`), and the HermesNotRunning alert (>900 s for 5m). Operator: re-render the plists (`bin/k3dm-webhook-setup`, `make install-cloud-bridge`, the Hermes plist per docs/guides/hermes.md), then `rm /opt/homebrew/bin/python3`. P3 paused-until DISPATCHED.
- 2026-10-09: DR drill first pass REJECTED and resumed (resume 2, prompt in job tmp `dr-resume.md`). It was a skeleton: verify defaulted to `true` with hard-coded `success:true` (a false-green DR drill); export copied the whole storage root from server-0 for every claim; inventory had zeros; pv-pvc.yaml had no logical node; restore used 1Gi, a host-side untar, no node gate or unseal, and a broken generate-root; publish read the M4's own ~/.k3dm; 11 tests, no mutations. The 19-item defect list adds mutation (f): restoring the default-true verify must turn a test red. P1 python3 pin is with Codex.
- 2026-10-09: Prune fix LANDED `4024d6f6` (87 pytest; mutations red: limit guard restored, != back to <, safety valve removed). Next Hermes tick should prune the 2 stale plan paths → drift 0, VectorDBIndexDrift resolves. Dispatching P1 python3 pin next (same Hermes files, now free).
- 2026-10-09: Hermes RECOVERED. The operator ran `brew install python@3.14` (now installed_on_request true), the `ln -s` to python3.14 and a kickstart. Run 907 exited 0 and indexed the 5 backlog docs (the 4 new bug docs and the DR plan). The durable P1 fix is still to dispatch. DR drill and prune-fix Codex runs both exited 0, awaiting verification.
- 2026-10-09: P1 Hermes DOWN since 18:42 (operator noticed new docs not indexed). The operator's brew upgrade at 18:47 (awscli → python@3.14) orphan-removed python@3.13, so `/opt/homebrew/bin/python3` is gone and the LaunchAgent exits 78 EX_CONFIG. The webhook and cloud-bridge plists use the same path and survive only until their next restart. Nothing alerted. Filed `docs/bugs/2026-10-09-launchd-agents-hardcode-homebrew-python3-hermes-down.md`. Operator decision: pin the version → templates use `/opt/homebrew/opt/python@3.14/bin/python3.14`, `brew install python@3.14` to mark it on-request (not `brew pin`), an installer preflight, a Hermes heartbeat, and a `HermesNotRunning` alert. Immediate recovery is the operator's: brew install + ln -s + kickstart.
- 2026-10-09: Investigated the vectordb dashboard (operator screenshot). Drift −2 = the old paths of the two plans swapped this morning, never pruned: `index-docs.py` disables the prune under `--limit`, and Hermes always passes `--limit 100`, so the scheduled index has never pruned (since #133 `3a254484`). Filed P2 `docs/bugs/2026-10-09-index-docs-never-prunes-under-limit.md` and dispatched it. `VectorDBIndexDrift` IS firing (warning, email), so no new alert is needed; its description gains the sign meaning. Filed P3 `docs/bugs/2026-10-09-hermes-index-paused-until-never-clears.md` (stale 2026-10-05 pause date; line 609 overwrites the reset); it waits on the P2 because both edit the same files. Overnight gap 20:45–03:00 = whole hub down (count(up) empty; laptop sleep), not vectordb. Watch item: run duration went from ~3 s to ~76 s per poll after 18:20, unexplained.
- 2026-10-09: M4 ssh alias `github-k3dm-hub-data` added by Claude at the operator's request (only this Host block appended). `git ls-remote` rc 0, and `ssh -T` greets `wilddog64/k3dm-hub-data`, i.e. the deploy key, not the personal key. The M2 alias is still the operator's to add.
- 2026-10-09: DR drill DISPATCHED to Codex (worktree `task/v1.43.0/hub-dr-drill`, session 01a12391-c9f0-7431-b30e-1a2423db0e46, no network). First task the dispatch ledger records. Verify, then `land --test` with every BATS file in the plan's Files table plus shellcheck.
- 2026-10-09: DR drill plan READY. L5 DECIDED by the operator: (c) the M4 publishes (`bin/dr-drill-publish`; the M2 stays read-only and pushes nothing). Added a `## Files` table (27 paths; `age-recipient.txt` is deliberately out of scope, Claude commits it after the operator generates the identity), a worktree DoD (Codex does not commit), the ssh alias `github-k3dm-hub-data`, results on the data repo branch `results`, and the freshness workflow source in `scripts/etc/dr/`. Next: dispatch with `make codex-dispatch`.
- 2026-10-09: DR drill L2 + L7 PROVEN on the M2 (throwaway `dr-probe` cluster, deleted). L2: a pre-set selected-node gets Bound with no consumer, and the PV and pod land on that node. L7: a default-deny egress NetworkPolicy is enforced (kube-router v2.2.1), BUT a new pod is open for 1–3 s → new check V0 (egress denied before the unseal; Vault stays sealed through the window). `--internal` rejected. Claude also installed `age` 1.3.2 on the M2 and moved the M2 checkout to v1.43.0 (HTTPS fetch; the M2 ssh session has no GitHub key). Only L5 (operator) and the ssh alias on both Macs remain before dispatch.
- 2026-10-09: Deploy keys added to `k3dm-hub-data` by the operator (Claude confirmed through the API): `m4-write` (write) and `m2-read` (read-only); each private key stays on its own Mac. SSH alias planned: `github-k3dm-hub-data`. Pending: the alias on both Macs plus an `ls-remote` test, `age` and checkout update on the M2, the L7 probe, and the L5 decision.
- 2026-10-09: Operator created private repo `wilddog64/k3dm-hub-data` (Claude confirmed: PRIVATE, empty, 0 deploy keys). Still pending: deploy keys, `age` and checkout update on the M2, the L7 probe output, and the L5 decision.
- 2026-10-09: DR drill §7 live checks (read-only) written into `docs/plans/v1.43.0-hub-dr-drill.md`. L1: Vault shamir t=1 n=1 raft; Secret keys key-shares/key-threshold/shard-1. L2: local-path v0.0.30 + WaitForFirstConsumer honours a pre-set selected-node (code reading; live proof in the L7 probe). The `_hub_recovery_records` node map is STALE after the 10-03 rebuild (`hub_recovery_targets` exits 1), so the drill's node gate now reads `pv-pvc.yaml`. Filed P2 `docs/bugs/2026-10-09-hub-recovery-node-map-hardcoded-stale-after-rebuild.md`. LDAP is one claim. L3: M2 has no `age`, and its checkout is stale (v1.37.0). L4 baseline: 7.8 GiB OrbStack, ~2.5 GiB used (e2e-runner plus an old M2 `k3d-cluster`). L6: `platform-ops/prometheusrule.yaml` gets a `dr.alerts` group; the Pushgateway job is renamed `k3dm-dr-drill`. Waiting on the operator: L5 decision (recommended: M4 publishes results) and the L7 probe script (dr-probe cluster on the M2).
- 2026-10-09: Dispatch metrics FIXED `db822e33` (ledger `~/.local/share/k3d-manager/worktrees/ledger.jsonl`, `bin/k3dm-dispatch-metrics` → hub Pushgateway job `k3dm-dispatch`, dashboard `k3dm-agent-dispatch`). Claude fixed: null-token codex_exit dropped (`--argjson tree`), unwindowed running/awaiting, tests isolated from the real Pushgateway. Ledger starts empty — the first recorded task is the next dispatch. Both parallel tasks of this batch are landed; no Codex tasks running.

- 2026-10-09: P3 staged appsets-reapply output FIXED `40bd1278` (landed with `land --test` on the argocd suites). Preamble runs once via `_argocd_prepare_applicationsets`; stage lines name the stage; owner-scoped success line names the ApplicationSets. Claude added: an unknown stage refuses before labelling. Metrics task still running (waiter by9y09uhj).

## 2026-10-09 — filed P3 staged appsets-reapply output bug; dispatched

- `docs/bugs/2026-10-09-appsets-reapply-staged-output-repeats-preamble-and-overstates-scope.md`: preamble (sample line, role label, file count) repeats per stage; scoped confirm says "All Applications". Fix: `_argocd_prepare_applicationsets` once; owners-aware success line. From operator first staged run (hub 9 + app-cluster 12 OK).
- Dispatched in parallel with the metrics task (disjoint files).

## 2026-10-09 — dispatched throughput/cost metrics bug (from `fd307ae2`)

- Spec amended first: resume writes `resume` + a second `codex_exit`; tokens are the Codex SESSION total, so the exporter uses the latest `codex_exit` per slug, never a sum.
- Waiter `by9y09uhj`. Verify, then `land --test` with codex_dispatch.bats + agent_dispatch_dashboard.bats + pytest test_dispatch_metrics.py.

## 2026-10-09 — batch 2 DONE: hub-first appsets LANDED `b90a15f1`

- `make appsets-reapply` now applies `hub` sets → confirms (owner-scoped: only Applications whose ownerReferences name a hub set; branch pin + none Degraded) → then `app-cluster` sets → confirms. `APPSETS_STAGE=hub` stops after the hub. Unlabelled set → nothing applied. CLAUDE.md reapply rule updated.
- First real `bin/k3dm-codex-dispatch resume` (fixed the all-Applications confirmation) and first real `land --test` (combined suites green after rebasing over c0871808).
- Codex claimed `_agent_audit` exit 0 but the pre-commit audit refused (9 ifs) — Claude extracted `_argocd_appset_in_stage`. Never trust an agent's audit claim; the hook is the gate.
- Next: dispatch `2026-10-09-codex-dispatch-has-no-throughput-or-cost-metrics` (land-test dependency is in).

## 2026-10-09 — batch 2: codex-dispatch land-test LANDED `c0871808`; hub-first appsets resumed for a fix

- `bin/k3dm-codex-dispatch`: `land --test CMD|--no-test` (test after rebase, before ff), `.land.lock`, exclusive `--network`, `resume --slug --prompt-file` (`make codex-resume`). 28/28 BATS, six mutations red.
  Claude fixes: scope diff from merge-base with the release branch (a retried land after a test refusal was refused as out of scope); a network-refused resume kept deleting `exit`.
- Hub-first appsets (`2026-10-09-appsets-reapply-switches-hub-and-hostinger-together`): labels match the spec table, apply order right, BUT the hub-stage confirm read every Application → on a real release it always fails and app-cluster is never applied; no Degraded check. Resumed via `bin/k3dm-codex-dispatch resume` (first real use): owner-scoped confirmation via `ownerReferences` ApplicationSet names + Degraded. Land with `--allow-out-of-scope` (argocd.bats, argocd_values_branch_drift.bats test-only). Then Claude edits the CLAUDE.md reapply rule.
- Next: verify + land hub-first; then dispatch the throughput/cost metrics bug.

- 2026-10-09: Added a `resume` subcommand (item 5) to the land-test dispatcher bug, and a `## Files` table + Rules (if-count ≤ 8) to the hub-first appsets bug. Dispatching batch 2 in parallel: land-test+resume, hub-first appsets. Metrics bug waits (same files as land-test). Operator restarted the webhook (bug_count routing live).

- 2026-10-09: bug-priority-tracking DONE `89cb86c1` — first parallel batch complete (3/3 landed: 8bd03a4f, 42c4ac9a, 89cb86c1; 114 combined BATS green). Codex's first run wrote ZERO tests; resumed the same session (`codex exec resume <id>`, same env/sandbox) to write them. Claude then found three bugs the tests missed: `scripts/bug-tally.py` not executable (live Slack count answers would all say "Could not count") → now run via sys.executable; `_SOURCE_META` module global raced across webhook threads → passed per answer; pre-commit hook read the working tree, not the staged blob. Added a regression for each (each red on Codex's version). Operator follow-up: restart Hermes (schema upgrade on next index run), `make restart-webhook` (bug_count routing), dashboards via the next hub-grafana-dashboards sync; then Claude backfills Priority on open bug docs. Dispatcher gap: no `resume` subcommand.

- 2026-10-09: Alertmanager delivery dashboard FIXED `42c4ac9a` (parallel batch, landed 2nd; 108 combined BATS green). All six new queries run against live hub Prometheus: actionable = TargetDown + CPUThrottlingHigh, pipeline = 0, 28 Trivy image rows, 2 smstest. Claude restored the routing paragraph Codex dropped. Filed P3 `docs/bugs/2026-10-09-codex-dispatch-has-no-throughput-or-cost-metrics.md` (ledger.jsonl + bin/k3dm-dispatch-metrics + k3dm Agent Dispatch dashboard; Codex tokens only, wait time not active minutes); dispatch after land --test. bug-priority-tracking still awaiting verification.

- 2026-10-09: appsets confirm-wait FIXED `8bd03a4f` (first parallel batch, landed 1st). Claude fixes over Codex: the first check's stale output was shown (now captured, printed only on success); timeout/interval not validated (interval=0 looped forever, a non-numeric timeout went into shell arithmetic); refactored `_argocd_appset_live_overrides` (9 ifs, a violation already on the branch that blocked every argocd.sh commit) by extracting `_argocd_appset_cni_overrides` unchanged — operator chose refactor over allowlist. 6/6 new BATS; argocd/appset suites green except 3 setup_file failures identical on base. Hub-first appsets bug now unblocked. Operator approved an agent-dispatch dashboard (accepted specs/day, % passing integration, intervention, cost/spec) as a v1.43.0 bug doc after land --test.

- 2026-10-09: Filed P2 `docs/bugs/2026-10-09-codex-dispatch-land-does-not-test-integrated-state.md` (operator review of agent isolation): `land --test CMD|--no-test` runs tests on the rebased task before ff-only; landing lock with trap release; `start --network` exclusive. Dispatch after the current parallel batch lands. Until then Claude lands one at a time and runs every landed task's tests on the combined branch before pushing.

- 2026-10-09: Added `## Files` tables to v1.43.0-bug-priority-tracking (25 files incl. 6 new tests) and the appsets-reapply confirm-wait bug (3 files + Rules). Dispatching the first PARALLEL batch via bin/k3dm-codex-dispatch: bug-priority-tracking, appsets confirm-wait, alertmanager-delivery dashboard. Shared files: docs/howto/makefile.md (bug-priority + confirm-wait), docs/guides/grafana-dashboards.md (bug-priority + dashboard) — different sections; land sequentially. Hub-first appsets bug waits for confirm-wait.

- 2026-10-09: Evaluated the ChatGPT review of the Alertmanager delivery dashboard. Live hub: "41 warnings" = 39 TrivyCriticalVulnerabilityDetected (all tier=upstream) + TargetDown federate-acg + smstest HostDiskSpaceLow; the 1 critical is smstest. Filed P3 `docs/bugs/2026-10-09-alertmanager-delivery-dashboard-mixes-actionable-security-and-synthetic-alerts.md`: split into actionable / Trivy-by-image / synthetic tables, a pipeline-health stat, a noisiest-alerts (3d) table; ready for codex-dispatch. Added item 7 to the v1.45.0 alert-intake spec: k3dm_intake_drafts{state} + k3dm_intake_seen_again pushed to Pushgateway job k3dm-intake. Rejected ownership grouping (single operator). Side finding: PrometheusMissingRuleEvaluations trips pending ~40-70x/3d across EVERY rule group (never fires, 11 pending now) — likely laptop sleep/clock jump; not filed yet.

- 2026-10-09: codex-dispatch stdout-hold bug FIXED `50fdf67b` (third worktree dispatch). Background subshell now `</dev/null >/dev/null 2>&1 &`; new BATS test (piped start returns < 3s). Claude verified 18/18, shellcheck clean, removing redirect -> test red. Dispatcher work complete; piping `start` is safe now. Next: `## Files` tables for bug-priority-tracking + appsets bugs, then parallel dispatch. Pending: user's Alertmanager-delivery-dashboard ChatGPT critique (images #53/#54 not visible to Claude — re-share needed).

## 2026-10-09 — codex-dispatch scope fix LANDED (774747ac); stdout-hold bug filed

- Scope now comes from the spec as dispatched (`<run>/base` + `git show base:spec`); editing the spec is out of scope; scope diff from base. 17/17 BATS, both mutations red (Claude-run in the task worktree). Landed with the fixed tool.
- CORRECTION to the R10 note below: Hermes needs NO reload — its LaunchAgent runs bin/k3dm-hermes from the operator checkout every 300s (StartInterval), so superseded_jobs is live from the next cycle.
- New P3: docs/bugs/2026-10-09-codex-dispatch-start-holds-caller-stdout.md — start's background subshell keeps caller stdout open (piped start waits ~10 min). Dispatching via the tool (unpiped).

## 2026-10-09 — Hermes R10 LANDED via worktree dispatch (first dogfood)

- R10 commits d6beebf9 / 7da544ad / bfc6e432 pushed. Claude verification: full hermes suite 249 passed; added superseded_jobs to both stubbed-sensor lists in test_hermes.py (unstubbed it probed the real hub and paged); added the missing 'precondition no longer holds' approve() test; commit 1 passes standalone (245).
- Dogfood found P2 gap: scope is read from the task's own spec copy, so a task can widen its own scope (land said in-scope). Bug: docs/bugs/2026-10-09-codex-dispatch-task-can-widen-its-own-scope.md — dispatching via make codex-dispatch.
- Operator: R10 needs `make restart-hermes`-equivalent (Hermes LaunchAgent reload) to go live; never automatic.

## 2026-10-09 — worktree-isolated Codex dispatch LANDED (b5223944)

- Codex implemented the 6 files; Claude verification found and fixed: (1) status/land picked the spec as the first root `*.md` (README/CLAUDE.md in the real repo → every land would refuse) — spec path now recorded in `<run>/spec`; (2) memory-bank not hard-excluded when a spec lists it; (3) two `! cmd` mid-test no-ops and a land test that never checked the fast-forward. 13/13 BATS, shellcheck clean, 5 mutations all red (incl. Codex's original lookup), script restored by cmp.
- Dogfood next: Hermes R10 spec gained a `## Files` table + worktree DoD; dispatching via `make codex-dispatch`. Other v1.43.0 specs and the two appsets bugs need a `## Files` table before they can be dispatched this way.

## 2026-10-09 — swap: agent isolation pulled into v1.43.0; Codex dispatched

- `docs/plans/v1.43.0-worktree-isolated-codex-dispatch.md` (was v1.45.0) ⇄ `docs/plans/v1.45.0-test-metrics-log-retention.md` (was v1.43.0). Both releases stay at 5 plans; roadmap + cross-links updated.
- Codex dispatched on the codex-dispatch spec in the shared checkout (codex exec workspace-write; cannot commit — Claude verifies and commits with the spec's exact message). DO NOT edit the tree until it finishes.
- After it lands: dogfood on one v1.43.0 spec, then parallel dispatch of Hermes R10, bug-priority tracking, appsets confirm-wait bug (then hub-first bug).

## 2026-10-09 — operator: Codex work stays sequential until agent isolation lands

- Decision: no parallel Codex dispatch until worktree-isolated dispatch (currently v1.45.0 spec) is complete; then parallel development.
- Proposed (awaiting operator): swap codex-dispatch spec into v1.43.0 (dispatch first) and move test-metrics-log-retention to v1.45.0, keeping both at the 5-spec cap.

## 2026-10-09 — codex-dispatch spec: per-task state isolation added

- Operator approved: dispatcher exports K3DM_REPO_ROOT/JOB_DIR/RUN_DIR/STATE_DIR/LOG_DIR/TMP_ROOT/PORT_CACHE_DIR + TMPDIR under `<run>/state` (one array `_dispatch_state_vars`), `--add-dir <run>/state`, HOME unchanged; test 5b + 3rd mutation check; worktree caveats in the how-to.

## 2026-10-09 — Aithon comparison → two v1.45.0 specs + one bug (operator: "go ahead")

- Decision: adopt isolated parallel agent execution + alert-to-draft-bug intake; REJECT per-PR human-review classifier and full beta/staging rails (overhead for one operator). Replace staging with a hub-first two-stage appsets rollout.
- `docs/plans/v1.45.0-worktree-isolated-codex-dispatch.md` — `bin/k3dm-codex-dispatch` start/status/land/abandon; one worktree + `task/<ver>/<slug>` branch per spec outside the repo; Codex never commits; land checks `## Files` scope and ff-merges, never pushes.
- `docs/plans/v1.45.0-alert-intake-draft-bugs.md` — `_run_analyze` drafts a redacted bug doc outside the repo for alerts firing ≥30m or ≥3 episodes/7d; `make intake-promote` copies into docs/bugs, never runs git.
- `docs/bugs/2026-10-09-appsets-reapply-switches-hub-and-hostinger-together.md` — P2; rollout-stage label + hub-gated app-cluster stage; implement after the confirm-wait bug.
- v1.45.0 now at the 5-spec cap (cve-remediation-terminal-notifications, docs-drift, node-tunnel drill, codex-dispatch, alert-intake).

## 2026-10-09 — istio-cni release step VERIFIED

- `make appsets-reapply` (2nd run, clean) + `make platform-ops`: istio-cni on Hostinger uses k3s CNI dirs, Synced/Healthy, DS 1/1; `ArgoCDAppProgressingStuck` loaded in hub Prometheus (ok, inactive). Bug doc marked VERIFIED.
- Note: `make platform-ops` warned `k3dm-webhook-token not found in Keychain` and skipped that Secret sync (no change made).
- Remaining: v1.43.0 Codex dispatch (specs + appsets-reapply confirm-wait bug) on operator go; 2026-10-15 smstest cleanup.

## 2026-10-09 — post-release ops on k3d-manager-v1.43.0

- Operator ran `make restart-webhook` (REPO_ROOT fix live) and `make appsets-reapply` + `make appsets-check`: all Applications on `k3d-manager-v1.43.0` (21 refs checked).
- Reapply's built-in confirmation false-failed (3 apps still on v1.42.0 at first read; reconcile lag). Bug filed: `docs/bugs/2026-10-09-appsets-reapply-confirms-before-controller-regenerates.md` — bounded retry, Codex-ready.
- Still pending: Hostinger istio-ambient apply + alert check; v1.43.0 spec dispatch to Codex.

## 2026-10-09 — v1.42.0 RELEASED; current branch k3d-manager-v1.43.0

- **PR #138 merged** as `cc88386c`. Tag `v1.42.0` pushed and verified on origin (peels to `cc88386c`). GitHub release `v1.42.0` created and marked Latest: https://github.com/wilddog64/k3d-manager/releases/tag/v1.42.0
- **enforce_admins on main restored** (true). No further branch-protection changes needed.
- **CodeQL #31, #32, #33 dismissed as false positives** by the operator. Pre-existing on main; see `docs/issues/2026-10-09-copilot-pr138-review-findings.md`.
- **Retro:** `docs/retro/2026-10-09-v1.42.0-retrospective.md`.
- **Current branch: `k3d-manager-v1.43.0`** (created from `cc88386c`, tracks origin).
- **Pending operator steps:**
  - `make restart-webhook` (picks up the webhook fixes).
  - Hostinger istio-ambient apply, then check the istio-cni alert.
  - `make appsets-reapply` then `make appsets-check` on `k3d-manager-v1.43.0` when ready.
- **Ready to dispatch to Codex:** the v1.43.0 specs in `docs/plans/` (5 files, at the cap).
- **2026-10-15 reminder:** delete pushgateway job `k3dm-disk-smstest` (the deliberate fake disk alert ends then).
## 2026-10-09 — PR #138 CodeQL resolved; ready to merge

- Operator committed the regex fix `0e74f3f2` (`--no-verify`); alert #34 fixed, thread resolved. CI green (lint, alertmanager-behaviour, Analyze x3). The CodeQL check stays red only on the existing `main` alerts #31/#32 (status.py clear-text storage) and #33 (test_hermes URL substring), re-reported because the PR touched those files; CodeQL is not a required check. Findings doc updated.

## 2026-10-09 — PR #138 (v1.42.0) opened; CI lint red fixed

- PR #138 https://github.com/wilddog64/k3d-manager/pull/138. Copilot: 0 findings (overview only). CI `lint` red: pyflakes F821 `REPO_ROOT` undefined in `bin/k3dm-webhook` `_publish_test_metrics` (silent NameError swallowed by lifecycle's broad except → webhook test-all fallback metrics never published). Fixed + direct test (RED NameError on old code; `pytest scripts/tests/bin` 536 passed). CodeQL ambiguous regex in `test_k3dm_test_metrics.py:162`: fix is an edited assert line, blocked by `_agent_audit` (operator-only `--no-verify`) — left to operator (commit or dismiss as used-in-tests). Findings: `docs/issues/2026-10-09-copilot-pr138-review-findings.md`.
- After merge/pull: `make restart-webhook` so the running webhook picks up the fix.

## 2026-10-09 — v1.42.0 release PR prep

- CHANGELOG promoted to `[1.42.0] - 2026-10-09` (empty `[Unreleased]` kept); added a Security section and the missing Slack-threading, test-dashboard, hub-snapshot, frontend/payment and Last-run entries; merged duplicate Added blocks.
- Docs: `makefile.md` (appsets-reapply/check), `launchd-daemons.md` (reaper uninstall + slack-notify), `slack-slash-commands.md` (`/argocd-upgrade` row); README + `docs/releases.md` v1.42.0 row (v1.39.0 moved to Older); Issue Logs refreshed with the five 2026-10-08 issues.
- Next: PR to main, Copilot review, CI; enforce_admins DELETE only when ready to merge.

## 2026-10-09 — Event-triggered checks: release decision + v1.45.0 fault-drill spec

- Operator asked whether vCluster could simulate the event-triggered v1.42.0 checks. It can't (virtual nodes: no kubelet/tunnel, no CNI, no AWS). Decision: release v1.42.0 with them marked:
  - **Verify on next occurrence:** expired-sandbox reaper (next ACG lapse), node-health-watch tunnel restart (P1; `grep -E 'kubelet tunnel dead|restarting' ~/.local/share/k3d-manager/logs/node-health-watch.log`).
  - **v1.42.0 release step:** Hostinger istio-cni — `make appsets-reapply` + next istio-ambient apply, then check the alert.
  - cleanup-stale-sandbox vs Hostinger PF: verify at the next real stale-sandbox cleanup.
- Spec QUEUED: `docs/plans/v1.45.0-node-tunnel-fault-drill.md` — `make drill-node-tunnel`: throwaway k3d cluster `k3dm-drill-tunnel`, iptables REJECT agent-local dial to :10250 (node stays Ready, healthz 502), fidelity gate on the watchdog's own regex, real watchdog with isolated log/state, PASS/FAIL/INCONCLUSIVE. Operator runs it; Codex implements when `k3d-manager-v1.45.0` exists (v1.43.0/v1.44.0 at the 5-plan cap; v1.45.0 now 3/5).

<!-- 2026-10-09 last-run panel colour -->
- **2026-10-09: k3dm Tests "Last run" was always red.** It used Grafana default thresholds, and the epoch value in ms is always above 80. The fix gives it a fixed neutral colour, with a BATS assertion that fails against the old dashboard (jq rc 4). Bug doc `2026-10-09-k3dm-tests-last-run-panel-always-red.md`. Rolls out via `hub-grafana-dashboards` auto-sync on the v1.42.0 branch.

<!-- 2026-10-09 failure-history verified -->
- **2026-10-09: `k3dm-tests-failure-history-missing` VERIFIED live.** The 7-day failure table keeps #60 and #203 from the 19:09Z failed run after the 20:01Z green run. Both Grafana test-metric bug docs are now verified. The operator's first screenshot was taken before the panel refreshed.

<!-- 2026-10-09 test-all green + v1.43.0 spec counting update -->
- **2026-10-09 `make test-all` GREEN:** 2664 cases, 0 failed, exit 0. Prometheus `k3dm_test_last_success_timestamp_seconds` advanced to 20:01:33Z after the 19:09Z failure had kept 2026-10-08. `test-metrics-last-success-lost-on-failure` is marked VERIFIED. `k3dm-tests-failure-history-missing` is still unchecked (dashboard).
- **2026-10-09 ask-docs recency VERIFIED live in Slack** (the doc is marked).
- **2026-10-09 v1.43.0 spec `v1.43.0-bug-priority-tracking.md` updated.** The question `/ask-docs how many P1 bugs … v1.42.0` came back "insufficient data", quoting the spec's stale "none has a priority" line. The real answer: 3 P1 bugs, all closed.
  - Item 9 `match` now requires only a count word plus "bug(s)"; release, priority and state are optional, and it returns a `CountQuery`.
  - Item 8 tally gains `by_priority` and `--priority`. The reply states how many docs are unset.
  - `doc_meta` counts `VERIFIED` as closed.
  - Tests were added for each.

<!-- 2026-10-09 ask-docs fix verified -->
- **2026-10-09 ask-docs recency + Slack bold: Codex `f120fce2`, verified by Claude.** 5 spec files changed. 40 ask-docs tests pass. Mutation check: with `_recent_docs` disabled, the 3 new tests fail. On the real corpus, "latest bugs fixed" now returns the 2026-10-09 FIXED bug docs. NEXT: the operator runs `make restart-webhook`, then reruns `/ask-docs what is the latest bugs fixed` in `C0B7ZHG2LR4`.
- **2026-10-09 `make test-pytest` tripwire red fixed:** the 2 `_poll` tests in `test_approvals.py` ran the real `bin/k3dm-disk-metrics` (ssh df to m2jump and hostinger) because they never stubbed `_publish_disk_metrics`. The disk-sensor commits left that gap. The stub is added; the gate now exits 0 with 775 passed.

<!-- 2026-10-09 test-all + ask-docs recency bug -->
- **2026-10-09 `make test-all` (operator tmux):** 1423 cases, 2 BATS failed, both from today's commits. #60 bare `! grep` lint hit `k3s_aws_deregister.bats` (209addbe), now `run ! grep`. #203 `observability.bats` expected the old "secret created on ACG" text after ea72ba1e, now "applied". Claude fixed both; the 3 suites are 23/23 ok. Metrics were pushed as test-all/local with exit 2.
- **2026-10-09 bug filed:** `docs/bugs/2026-10-09-ask-docs-latest-bugs-misses-recent-fixes.md`. `/ask-docs` "latest bugs fixed" pulls a semantic pool of 50 (33 retros, 5 bugs), so the newest fixes are never candidates. The fix lists docs by date for questions that name a kind, and converts `**bold**` to Slack bold. Dispatched to Codex (`codex exec`). After that: Claude verifies, the operator runs `make restart-webhook`, then a Slack recheck in `C0B7ZHG2LR4`.

- **2026-10-09 Slack live verification DONE** — relay deployed by operator (`make deploy-worker`, version `b2ce7b54-9573-4752-81c4-8dbb45b87e03`). 5 Slack bug docs marked VERIFIED: argocd-thread-usage-duplicated, ask-docs-redacts-iso-dates-as-phone, k3dm-thread-context-and-test-slack-leak, slack-cleanup-thread-context-lost, slack-stale-sandbox-cleanup-misleading-reporting. Note: `/ask`+`/ask-docs` thread only in webhook `SLACK_CHANNEL_ID` (`C0B7ZHG2LR4`), unlike `/k3dm`/cleanup which thread in any caller channel — by design, not a bug. Remaining v1.42.0 live checks: Grafana test-metrics (2), event-triggered (4), SMS [RESOLVED] 2026-10-15, login retry screen (browser).

<!-- 2026-10-09 frontend repin + alertmanager-config live -->
- **2026-10-09: frontend repin deployed** (user's go). `ce21efda` repins Hostinger's frontend to `sha256:17f46a0d…` (`sha-05ec17e`). ArgoCD auto-synced, the rollout completed, and the public 200 response carries "Login took too long" in the bundle. Login-callback A and Tailwind v4 are now live.
- **2026-10-09: SMS live.** The operator ran `make alertmanager-config`. The live config has `send_resolved: true` for `sms-critical` and `platform-warning`. The `[RESOLVED]` text will be proven by the smstest delete on 2026-10-15.

<!-- 2026-10-09 v1.42.0 bug closure, round 2 -->
- **2026-10-09: v1.42.0 bug closure, round 2.**
  - **SMS item 4:** Codex `ea72ba1e` (`make alertmanager-config`, one `_observability_apply_alertmanager_config`). Claude verified it: shellcheck clean, 89 BATS ok, 1 render site, no credential export. The operator still needs to run `make alertmanager-config`.
  - **Login-callback:** A (#115 `3623e5b2`) and C (#108 `03c6206f`) were already merged. Claude opened duplicate PRs (frontend #119, infra #111) and closed both.
    - C is verified live.
    - A plus Tailwind v4 are NOT live: Hostinger's frontend is pinned to `sha-85265e7`. The repin to `sha-05ec17e` (`sha256:17f46a0d…`) waits for the user's go.
  - **Reaper doc:** status corrected to installed.
  - **Slack live-verification script:** sent to the operator. `make restart-webhook` is done; `make deploy-worker` is not confirmed.
  - **Lesson:** check MERGED PRs (`gh pr list --state merged`), not just open ones, before opening a PR from a bug doc.

<!-- 2026-10-09 v1.42.0 bug audit — dispatch round -->
- **2026-10-09: v1.42.0 bug closure.**
  - **frontend-public-url (2026-09-25):** FIXED, superseded by the 2026-10-01 hub-recovery fix. Public URL returns 200 via `127.0.0.2:80` to hostinger; the stale agent is gone.
  - **SMS item 4:** the spec (`make alertmanager-config`, a deduped `_observability_apply_alertmanager_config`) is appended to the SMS bug doc and dispatched to Codex.
  - **login-callback A and C:** Claude opens the PRs. Codex may not create PRs.

<!-- 2026-10-09 v1.42.0 bug audit — Claude-owned live checks done -->
- **2026-10-09: v1.42.0 bug audit.** Claude verified two fixes and set them to verified:
  - hermes-values-branch (`895221cb`): the live hub record is healthy, 21 refs, 0 stale. The stale-path message is covered by 10 pytest cases.
  - webhook-tests-audit-log (`2f7e0eb5`): pytest ran 779 passed and the audit log stayed at 72 test rows.
  - The tailwind v4 bug is now FIXED; shopping-cart-frontend PR #117 merged as `05ec17e3`.
  - **Still open for v1.42.0:**
    - login-callback A and C need PRs; B is deferred.
    - SMS item 4 is optional.
    - The frontend-public-url bug is UNFIXED, and its fix choice is undecided.
    - About 13 fixes are waiting on operator or live checks: the Slack threads, the test metrics, the reaper, node-health-watch and istio-cni.

- 2026-10-09 — v1.45.0 docs-drift spec amended with §7 Grafana (operator yes): 7 `k3dm_docs_*` metrics via Pushgateway job `k3dm-docs-drift` (hourly gate), "Docs Health" dashboard (`make platform-ops`), `DocsDriftCheckStale` info rule; tests 8–11 + live step 4.

- 2026-10-09 — Spec `docs/plans/v1.45.0-docs-drift-detection.md` filed (operator chose v1.45.0; v1.43.0 and v1.44.0 at cap). 3 layers: generated doc blocks + `make docs-check` (CI/pre-commit), weekly Hermes drift digest via `covers:` lines, drift → bug-doc draft. Hermes never edits docs. Roadmap v1.45.0 section added. v1.45.0 now 2/5 plans. Dispatch to Codex when `k3d-manager-v1.45.0` opens.

- 2026-10-09 — PR #136 (Dependabot brace-expansion in subtree) CLOSED at user request, with comment; fix belongs upstream in lib-foundation then subtree-pull. Dependabot alerts #13 (brace-expansion) and #15 (sprintf-js, no patch) remain open on main.

- 2026-10-09 — webhook-server.md rewrite VERIFIED (Codex `d1f66a98`, on origin): 2 files only; all 16 modules with wc -l matching; intra-package imports match code; all 15 `_POST/_GET_ROUTES` keys present; no line ranges; monolith 2,576 lines; confirm targets listed; `make check-doc-links` OK. Bug doc `2026-10-09-webhook-server-architecture-doc-stale.md` FIXED. All 4 audited docs now current. PR #136 (brace-expansion in subtree) — recommended not merging; awaiting user on lib-foundation bump.

## 2026-10-09 — doc fixes + webhook doc rewrite dispatched; PR #136 not merged

- `733ce24a`: cloud-bridge.md capability row + token diagram, vector-store.md SQLite embed cache, roadmap-v1.md ARCHIVED banner.
- Bug doc `docs/bugs/2026-10-09-webhook-server-architecture-doc-stale.md` — dispatched to Codex (rewrite against tree; no line ranges).
- PR #136 (Dependabot brace-expansion 1.1.21) — recommended NOT merging: it edits the `scripts/lib/foundation/` subtree directly. Fix upstream in lib-foundation (its Dependabot alerts are disabled), then subtree-pull. sprintf-js alert has no patched version (dev-only, transitive). enforce_admins left ON.

## 2026-10-09 — sandbox reaper: first live run failed, fixed

- Operator ran `make install-sandbox-reaper`; first run exit 1 — launchd PATH resolved `/bin/bash` 3.2 (`mapfile`/`local -A`). Fix `c125dd11`: PATH in plist + BATS guard (RED-checked). Launchd-env dry-run clean (no k3s-aws registration on hub now).
- NEXT (operator): re-run `make install-sandbox-reaper` to load the new plist.
- Doc audit (operator asked): webhook-server.md stale (line counts, 7 modules missing, 17→29 make targets, no /api/v1/ask-docs, contradictory phase table); cloud-bridge.md one contradiction (says no lifecycle actions; sandbox-up/down + make-e2e exist); vector-store.md index diagram misses SQLite embed cache (v1.41.0); roadmap-v1.md archived but no ARCHIVED banner.

## 2026-10-09 — expired-sandbox reaper implemented + verified

- Codex `f089c36f` (bin/k3dm-sandbox-reaper, bin/k3dm-slack-notify, plist tmpl, Makefile install/uninstall-sandbox-reaper, 2 BATS suites, howto, CHANGELOG). Claude fix `90643a02`: `(A||B)&&C` precedence reported stack-deleted as credentials-dead; mid-test `! grep` guards hardened with `|| false`.
- Verified: 20/20 BATS (reaper 14, notify 2, cleanup-stale-registration 4), shellcheck clean, plist lints; mutation checks caught grace/inconclusive/dry-run removal + original precedence bug.
- NEXT (operator): `make install-sandbox-reaper` (live, DRYRUN=0, Slack notice per action). Then: frontend public URL bug.
- Grafana Host Disk "m2 down" = stale series `path=k3d-snapshots` (typo, 10-08 19:29–19:33); live series `path=k3dm-snapshots` is up. Not a fault.

- 2026-10-09: operator `make snapshot` OK — m2jump:k3dm-snapshots/20261009T170742Z (3.4G, 18m), all checksums OK; contains data-openldap-0, no osixia ldap PVCs. OpenLDAP CVE item CLOSED. Next: reaper decision (auto vs Hermes), then frontend public URL bug.

- 2026-10-09 post-merge: frontend #117 merged 05ec17e (Tailwind 4; enforce_admins never disabled, stays true); infra #110 merged c7ff88a, enforce_admins RESTORED true. No tags (both [Unreleased], chore/fix branches). Hub verified read-only: osixia ldap Deployment/Service/ExternalSecret/PVCs + ldap-secrets gone; operator patched PVs to Delete (tmux confirmed), both PVs deleted; openldap-0 Running 1/1, data-openldap-0 Bound, shopping-cart-identity Synced/Healthy. NEXT: operator `make snapshot`. Noticed in operator pane: `make shopping-cart-credential-drift` reported DRIFT on all 6 creds with probe exit codes 1/2/65 — not yet investigated.

- 2026-10-09: shopping-cart-infra enforce_admins DISABLED for PR #110 merge (restore with bodyless POST after merge or if deferred). Operator patches the 2 osixia PVs to Delete before merging.

- **2026-10-09 Expired-sandbox reaper designed** (`ffe1de90`): watcher path dropped (acg_watch never started by k3d-manager); launchd reaper with Unknown≥30min (keyed on Secret UID) + CFN/creds gone signal, dry-run first. Awaiting operator choice: auto reaper vs Hermes approval. Next after that: frontend public URL.

- **2026-10-09 SMS recovery (items 1,2,3,5) verified** — Codex `088378ea` (on origin). Claude ran pytest with real Docker: 7/7; RED on pre-fix template: exactly `test_sms_sends_resolved_notification` + `test_resolved_text_templates_render_with_amtool` fail. Item 4 (`make alertmanager-config`) deliberately not done. Live: operator runs `make observability` (only apply path today) before 2026-10-15, then smstest delete should text RESOLVED.
- **2026-10-09 Host Disk dashboard had no tags** (user report) — added `["k3dm","disk"]` + BATS guard (every provisioned dashboard has ≥1 tag; RED named only host-disk; 39/39). PRs: infra #110 (green, Copilot 0 findings; operator patches 2 PVs to Delete before merge), frontend #117 (all green after prettier fix `99a95485`; main rerun 37942894719 green).

- **2026-10-09 OpenLDAP orphan removal — both parts verified.** Part 1 k3d-manager `773dc75d` (on origin; shellcheck 0; BATS 104/104 hub_recovery+hub_snapshot+cluster_down; RED: 8 tests fail against pre-fix plugin). Part 2 shopping-cart-infra `aca9f9e` on `fix/remove-orphan-osixia-ldap` (kustomize ok; `identity/ldap` grep gate empty). Live read-only: only the orphan `ldap` pod consumes `ldap-secrets`; no `ldap://ldap` short-name refs; Keycloak federates `openldap.identity`. Next: infra PR; operator patches PVs `pvc-2f1c2ab2-…` + `pvc-7e307e74-…` to Delete BEFORE merge; then SMS spec → Codex.

- **2026-10-09 — OpenLDAP CVE (doc 2026-08-02-openldap-…):** bitnamilegacy migration already DONE (jp-gouin
  `openldap`, 19 crit, newest tag). The 66 crit are an ORPHANED osixia `ldap` Deployment (shopping-cart-infra
  `identity/ldap`) nothing uses. Operator decision: remove incl. PVCs + data. Two-part spec → Codex: Part 1 k3d-manager
  (cluster-up inline source, `_hub_recovery_records` minus 2 claims + `_hub_recovery_retired_claims` so old snapshots
  validate, docs); Part 2 shopping-cart-infra clone `shopping-cart-infra-ldap`, branch `fix/remove-orphan-osixia-ldap`.
  Before merging Part 2 the operator patches the 2 PVs (pvc-2f1c2ab2…, pvc-7e307e74…) to Delete (they're Retain).

- **2026-10-09 — Tailwind v4: PR shopping-cart-frontend #117 open** (`chore/tailwind-v4-migration`, Codex `c9d3a95d` +
  Claude `d6fc1bf1`). Verified: scope OK, lint/build/unit 30/30, audit 0, local Chromium E2E 42/42 (after installing
  chromium-headless-shell 1243 — Codex's sandbox hung on the download). Copilot tagged; awaiting CI. Clone at
  `shopping-carts/shopping-cart-frontend-tw4`. **Next (user order):** OpenLDAP CVE → SMS resolved → expired ACG
  sandbox → frontend public URL.

- **2026-10-09 — P1 node-health-watch (`90d8942a`) live-checked:** fixed code running (pid started 05:51 PDT, after
  the commit); live `_healthz_state` = ok on all 4 hub nodes; tunnel regex matches the real 502 line; BATS 11/11.
  The real tunnel → restart path awaits the first natural recurrence (check `grep 'kubelet tunnel dead'` in
  node-health-watch.log); close the doc then.

- **2026-10-09 — Tailwind v4 migration spec** `docs/bugs/2026-10-09-frontend-tailwind-v4-migration-for-postcss-selector-parser-advisory.md`
  → Codex, in a fresh clone `shopping-carts/shopping-cart-frontend-tw4`, branch `chore/tailwind-v4-migration` from
  origin/main `3623e5b`. Clears alert #41 (GHSA-rj75-hqrm-r3gf). Note: frontend `dependabot-automerge.yml` auto-merges
  ALL security updates on green CI, so E2E was the only gate that stopped #114.

- **2026-10-09 — frontend #114 CLOSED** (with explanation). It was a Dependabot **security** update for alert #41
  (GHSA-rj75-hqrm-r3gf, postcss-selector-parser, medium; patched only in 7.1.6, which needs tailwindcss 4). The
  existing `ignore: "*" semver-major` in dependabot.yml covers version updates only, so it did not stop the PR. Alert
  #41 stays open, so Dependabot can open another one when tailwind 4 ships a new release. Lasting fix = the Tailwind v4 migration
  (spec + Codex on a feature branch); interim option = dismiss #41 as tolerable risk (build-time only). Awaiting the user.

- **2026-10-09 ~16:10 UTC — `make appsets-reapply` / `make appsets-check` VERIFIED** (Codex `8bdc5ccd`, on origin).
  4/4 new BATS green; all 13 `makefile_*.bats` green; RED on the pre-change Makefile (4/4 fail); mutation
  (drop the `$$` anchor) turns test 2 red. Exact commit message. Codex's Status line cited a dangling pre-amend
  SHA `5542947f`; corrected to `8bdc5ccd`. Not run against the real repo.
- **Frontend (2026-10-09):** PR #114 (Dependabot tailwindcss 3→4) fails E2E: v4 removed the PostCSS plugin
  `postcss.config.js` loads, so every page 500s. Recommendation: close + Dependabot ignore for tailwind major;
  v4 migration later as its own spec (awaiting the user). Main run `37942894719` deploy job hung 2h on the image
  build; the operator cancelled it, Claude reran it at ~16:10 UTC (#115's image not built until it passes).
- **Alerts (2026-10-09):** all resolved/expected — istio-cni rollout (fixed `350fac28`), payment crashloop from DB
  credential drift (fixed by the operator's drift restart 13:54), smstest fake disk, `federate-acg` TargetDown
  (no sandbox). Offered: bug doc to suppress federate-acg TargetDown when no sandbox exists.

- **2026-10-09 appsets reapply done + make targets dispatched:** operator reapplied 13/13 sets on v1.42.0; `hub-vectordb` + `hub-platform-ops` now v1.42.0 Synced/Healthy, check clean (21 refs). Spec for `make appsets-reapply` (release-branch guard) + `make appsets-check` appended to `docs/bugs/2026-09-30-release-config-inert-until-applicationsets-reapplied.md` (recurrence section); CLAUDE.md release rule points at the targets. Dispatched to Codex.

## 2026-10-09 — hub-vectordb + hub-platform-ops still on v1.41.0
- `argocd_check_values_branch k3d-manager-v1.42.0`: 21 refs checked, 2 stale (hub-platform-ops, hub-vectordb). Both appsets last applied 2026-10-03 15:58; v1.42.0 sets were applied one at a time, never as a full set.
- v1.41→v1.42 delta: vectordb none; platform-ops = dashboards (host-disk new, alertmanager-delivery, argocd, cve-autopatch, vectordb) + prometheusrule (+10).
- Operator fix: `K3D_MANAGER_BRANCH=k3d-manager-v1.42.0 ./scripts/k3d-manager deploy_argocd_applicationsets --confirm` (then re-run the check).
- Lead for the 11:47 UTC Vault/ESO rewrite: appset `services-git` was kubectl-applied at 2026-10-09T11:46:41Z.

## 2026-10-09 — sc-infra PR #109 MERGED `7028ae5` (postgres-keycloak Recreate)
- PRs merged: sc-infra #109 `7028ae5`. enforce_admins restored (bodyless POST → true). Local sc-infra main synced. Fix branch, stays [Unreleased] — no tag.
- Hub synced: strategy Recreate confirmed live, pod `897bc7b6c-sv6q6` untouched.
- Follow-up: ldap Deployment + RWO PVCs, same risk.

## 2026-10-09 — sc-infra PR #109 open (postgres-keycloak Recreate)
- https://github.com/wilddog64/shopping-cart-infra/pull/109 — Copilot: approval recommended, 0 findings. Waiting for user go; enforce_admins still ON.

## 2026-10-09 15:30 UTC — merges done; disk Hostinger target + postgres Recreate verified
- sc-infra #108 merged `03c6206f`, sc-frontend #115 merged `3623e5b2`; enforce_admins restored (bodyless POST) on both.
- Disk amendment (Hostinger node): Codex `f88993a6` on `k3d-manager-v1.42.0` — verified: 7/7 pytest, 2 new tests FAIL on pre-fix script, yaml OK. Live check pending: next Hermes tick → `k3dm_disk_avail_bytes{host="hostinger"}` in hub Prometheus.
- postgres-keycloak Recreate: Codex `05b2e9e` on sc-infra `fix/keycloak-postgres-recreate-strategy` — verified diff (2 files), kustomize renders Recreate. PR next. Codex flagged `identity/ldap/deployment.yaml` (Deployment + RWO PVCs) — same risk, not changed.

## 2026-10-09 — payment CVE bug FIXED

- `docs/bugs/2026-10-08-payment-spring-webmvc-cve-no-oss-6x-fix.md` → FIXED. Payment Trivy alert cleared on the hub; all 42 firing TrivyCritical are tier=upstream. Trivy has not yet written a report for the live RS `5b6bf56678`.

## 2026-10-09 — enforce_admins DISABLED for merge (restore with bodyless POST after merge)

- shopping-cart-infra (#108) and shopping-cart-frontend (#115): classic protection, NOT rulesets. enforce_admins disabled for the user's merge; /post-merge must re-enable both.

## 2026-10-09 ~14:00 UTC — Hostinger payment restored; shopping-cart PRs open

- Operator ran `make shopping-cart-credential-drift` + `APPLY=1`: postgres-orders/products/payment, rabbitmq, redis-cart, redis-orders-cache all FIXED; order, product-catalog, payment, basket restarted and Running.
- payment-service on `2d930a93…2876`: Flyway connected, app started 13:54 UTC. VulnerabilityReport/Trivy alert check pending (new report not yet written).
- PRs open: shopping-cart-frontend #115 (Prettier fix `b2f7b5b5`, CI re-running), shopping-cart-infra #108 (CI green). Copilot: approval recommended, 0 findings on both. Rulesets — user merges.
- Still open: what rewrote Vault/ESO shopping-cart values at 11:47 UTC.

## 2026-10-09 — P2/P3 Codex batch: all Claude-verified

- istio-cni `350fac28`; ACG deregister `209addbe` + Claude cleanup `cbd2f564` (removed a test-only
  branch Codex put in production code; old stub now returns JSON), 67/67 BATS, RED on old code.
- Frontend `f28a1b93` on `fix/login-callback-timeout`: lint/tsc clean, vitest 30/30; on the old
  component exactly the 2 new tests fail. Infra `63cfcfa5` on `fix/keycloak-postgres-probe-user`:
  kustomize renders. PRs NOT opened (awaiting the user's review).
- Still open: Keycloak DB off agent-0 (needs data-migration decision), ACG watcher/reaper
  (lib-foundation first), SMS resolved (parked v1.44.0), Hostinger payment outage (operator:
  `make shopping-cart-credential-drift` then `APPLY=1`).

## 2026-10-09 — Hostinger payment DOWN after repin: DB credential drift, not the image

- Repinned payment to `2d930a93` (payment #86, CI Trivy 0 findings) in `f92ae552`. The new pod
  crash-loops: Flyway `password authentication failed for user "postgres"`. maxSurge=0, so payment is down.
- Cause: ESO rewrote every shopping-cart Secret at 2026-10-09 11:47 UTC (data changed; the untouched
  `payment-encryption-secret` proves ESO writes only on change). `postgresql-payment-0` is 64 days old
  and keeps its old password. Any restart since 11:47 fails, old image included, so a rollback does
  not help (Claude's revert attempt was blocked by the permission classifier; not retried).
- Running pods (order, basket, product-catalog) still hold pre-11:47 values and will fail on restart.
- Operator fix: `make shopping-cart-credential-drift` (report), then `... APPLY=1`.
- Open question: what changed the Vault/ESO values at 11:47 (suspect the day's `make refresh`).
- Codex batch done, Claude verification pending: frontend `f28a1b93` (fix/login-callback-timeout),
  infra `63cfcfa5` (fix/keycloak-postgres-probe-user), k3d-manager `209addbe` (ACG deregister).
  istio-cni `350fac28` verified. Preflight `6cd750b9` + GHCR `3d33d687` verified.

## 2026-10-09 — Trivy reconcile-errors panel made readable (`08273e98`)

- Panel id 12 on "ArgoCD Apps & Image Updater Hub" (`scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`): line → bars, `interval: 1h`, `legendFormat: "errors / hour"` (was `{}`), added a description. Query unchanged; `trivy_operator_observability.bats` 9/9.
- Served live by `hub-grafana-dashboards` (targetRevision `k3d-manager-v1.42.0`), so it appears after the next ArgoCD sync.
- Done directly by Claude (cosmetic dashboard JSON), not via Codex.

## 2026-10-09 — P1 node-health-watch dead-tunnel fix IMPLEMENTED (`90d8942a`, Claude-verified)

- Codex commit `90d8942a` is on origin and changes exactly the 5 spec files.
- Claude checks:
  - shellcheck clean; `node_health_watch.bats` 11/11 green; `launchd_plist_path.bats` green.
  - RED reproduced independently: the 6-tick tunnel test fails against `90d8942a^`.
- Not live yet: launchd PID 60971 still runs the old in-memory functions.
  - Operator: `launchctl kickstart -k gui/$(id -u)/com.k3d-manager.node-health-watch`.
- Side finding (dashboard dots): the "Trivy Operator Job Reconcile Errors" panel's `{}` dots are the unlabeled `sum(...)` series.
  - 87 errors on 2026-10-03 during the hub rebuild: scan jobs failed because CoreDNS answered "server misbehaving" for quay.io and docker.io.
  - 1 more on 2026-10-06: a transient `StorageError` on a ClusterRbacAssessmentReport.
  - No ongoing errors.

## 2026-10-09 — P1 node-health-watch dead-tunnel fix dispatched to Codex

- Spec: the "Implementation spec" section of `docs/bugs/2026-10-09-node-health-watch-ignores-ready-node-with-dead-kubelet-tunnel.md`.
- Codex is on `k3d-manager-v1.42.0`; expected commit "fix(node-health-watch): recover a Ready node whose kubelet tunnel is dead".
- Claude verifies: SHA on origin, RED + green BATS, shellcheck, 5-file scope.

## 2026-10-09 — Bug-doc sweep pass 2: 17 stale statuses checked against code

- 15 closed as FIXED or SUPERSEDED: the 8 v1.23.0 QUEUED docs, the 3 2026-08-28 "SPEC → FIX" docs, argocd-ldap-vars, hostinger-status report body, and the trivy reconcile panel.
- 2 still OPEN (real defects):
  - `v1.1.1-bugfix-preflight-wait-read-set-e-abort`: `bin/cluster-preflight:152` has an unguarded `read` under `set -e`.
  - `2026-09-21-rotate-ghcr-pat` Defect 4: `scripts/plugins/shopping_cart.sh:467` passes the PAT on argv (secret hygiene).
- Next: the P1 node-health-watch spec to Codex.

## 2026-10-09 — Payment #84 on main: CVE-2026-47884 cleared; repin held for payment #86

- Main CI run 37927654332 on `ea63cddc` is all green. The image is `sha-ea63cddc…`, index
  `sha256:1a14ed1a…`, and the promote loop committed `6382a3e9`.
- Trivy: spring-webmvc 7.0.9 has 0 findings. The image still shows 3 CRITICAL in Tomcat 11.0.24 and
  5 HIGH in Jackson 3 3.1.5.
- **The Hostinger repin is HELD.** The current `3551ec8d` image has only 1 CRITICAL, so repinning now
  would keep the alert firing.
- Payment PR #86 (`fix/tomcat-jackson3-cve-overrides`, `b583d8a6`) overrides `tomcat.version` to
  11.0.26 and `jackson-bom.version` to 3.1.7. It is waiting on CI and Copilot, then on the user's merge.
- After #86 merges: repin the digest in `services/shopping-cart-payment/kustomization.yaml`, verify
  the alert clears, and mark the CVE bug doc FIXED.

## 2026-10-09 — Bug-doc status sweep: all 683 docs now carry a Status line

368 docs in `docs/bugs/` had no Status line. Each one now has one, tagged `(2026-10-09 status sweep)`:
- 340 `CLOSED — doc merged to main in PR #N; no open follow-up was found`. This is inferred: the doc's spec merged in a shipped release and nothing in the memory-bank or roadmap carries it as open. It was not re-verified doc by doc; I spot-checked about 15 against the code (kubeconfig prune helper, CRD guards, `monitoring-resume LAYER`, loadtest, signing `--app-cluster`, the openldap federation on infra main, the reconcile `|| true`) and all of them were present.
- 25 `CLOSED — superseded`: the 2026-05-16 chain of ACG "Extend session" modal iterations. ACG automation now lives in lib-foundation.
- Kine compaction stall: CLOSED, because the 2026-10-03 hub rebuild replaced the datastore. Hub control-plane re-adoption: OBSOLETE.
- 7 docs already had a `## Status` section saying fixed (the 10-06 Slack fixes, the 10-07 make-job tail, the git-persist clone, the keycloak redirect). Those were left unchanged.

## 2026-10-09 — Bug triage: 2 closed, 2 prioritized; payment #84 conflict resolved

- Closed as FIXED: `2026-04-26-shopping-cart-imagepullbackoff-no-ghcr-pull-secret` (pull secret + imagePullSecrets in tree; Hostinger apps healthy) and `2026-04-27-orders-init-sql-serial-vs-uuid` (infra init SQL is UUID; order rewritten in Go).
- Prioritized: `2026-08-14-k3s-aws-ssm-agent-cannot-register` → P4, mitigated by the SSH fallback. `2026-09-16-e2e-assertion-api-payments` → P3, all fixes merged (payment #78, e2e-tests #9/#10); a live Tier 1 rerun is the only thing left.
- Payment #84: a conflict with #85 (stripe 34.0.0) in `pom.xml` properties. Resolved with a merge commit `b3a8741b` keeping `rabbitmq-client` 1.1.0 + stripe 34.0.0. No force push. A local build can't run (GitHub Packages 401), so CI is the gate.
- 375 of 683 bug docs still have no Status line. That sweep is not done.

## 2026-10-09 — payment #84 merge-ready (verified)
- Head `6dfb8bab`: all 5 ruleset-required checks green (Integration Tests now pass with rabbitmq-client 1.1.0); Copilot 0 findings, 0 threads; mergeStateStatus CLEAN; image resolves spring-webmvc 7.0.9.
- Repo uses ruleset `main-protection` (0 approvals) — no enforce_admins lever. PR-side Trivy does not run (Build, Scan & Push skipped on PRs); verify CVE-2026-47884 gone after merge, then re-pin Hostinger digest.

## 2026-10-09 — Hostinger istio-cni recovered (verified)
- Operator ran `make refresh CLUSTER_PROVIDER=k3s-hostinger`. App values now rancher dirs; app Synced/Healthy; `istio-cni-node` 1/1 (`istio-cni-node-rv94s`).
- Bug doc stays OPEN: apply-path trace + `ArgoCDAppProgressingStuck` alert still to spec.

## 2026-10-09 — stale ubuntu-k3s registration cleaned (verified)
- Operator ran `make cleanup-stale-registration CLUSTER=ubuntu-k3s CONFIRM=1`: removed `cluster-ubuntu-k3s` + 10 apps.
- Claude verified: hub cluster Secrets now only `cluster-ubuntu-hostinger` + `ubuntu-k3s-app-cluster` (hub); no app targets `ubuntu-k3s` or `host.k3d.internal`; none regenerated. Automatic deregister (bug doc) still OPEN.

## 2026-10-09 — make down misses server-matched sandbox apps (doc only)
- `_k3s_aws_deregister_cluster` matches apps by destination name only; `ubuntu-k3s-eso` / `-platform` (server `host.k3d.internal:6443`) survive even a normal `make down`.
- Chaining `cleanup-stale-registration` after down cannot catch them: the Secret (source of the server) is already gone. Fix item 0 added to `docs/bugs/2026-10-09-expired-acg-sandbox-leaves-hub-registration-and-apps.md`.

## 2026-10-09 — Fixed `make cleanup-stale-registration`; documented `make down` over-reach

- **Fix:** the Makefile passed `--cluster "$(CLUSTER)"`, but the script requires `--cluster=<name>`, so every call exited 2.
  - Fixed, with a BATS case for the make wiring (`cleanup_stale_registration.bats`: RED, then 4/4 green).
- **Live dry-run** of `CLUSTER=ubuntu-k3s` matches `cluster-ubuntu-k3s` plus 10 Unknown apps:
  - the 8 matched by name,
  - plus `ubuntu-k3s-eso` and `ubuntu-k3s-platform`, which use the `host.k3d.internal:6443` tunnel server.
  - The hub's `k3d-cluster-eso` is not matched.
  - The operator runs `CONFIRM=1`.
- **`make down` over-reach** (in the ACG bug doc): even with `KEEP_LOCAL=1`, `bin/cluster-down` kills and unloads `com.k3d-manager.vault-port-forward` (the HUB Vault, 18200), plus the frontend and ACG Prometheus port-forwards. None of those steps checks `_keep_hub`.

## 2026-10-09 — Bugs filed: Hostinger istio-cni stuck Progressing; expired ACG sandbox leaves its registration

- `docs/bugs/2026-10-09-hostinger-istio-cni-generic-dirs-after-hub-rebuild-and-no-alert.md` (OPEN, P2):
  - `istio-cni-ubuntu-hostinger` has been Progressing since 2026-10-03, with `istio-cni-node` at 0/1 (readyz 503).
  - Its Helm values use the generic `/etc/cni/net.d` + `/opt/cni/bin`, but Hostinger needs the rancher dirs.
  - The ApplicationSet was created during the 10-03 hub rebuild and updated 10-06. Which path applied it is not yet traced.
  - No alert: `ArgoCDAppDegraded` uses a name allowlist and only matches Degraded; the hub has no Hostinger DaemonSet metrics.
  - Operator recovery: `make refresh CLUSTER_PROVIDER=k3s-hostinger`.
- `docs/bugs/2026-10-09-expired-acg-sandbox-leaves-hub-registration-and-apps.md` (OPEN, P3):
  - `cluster-ubuntu-k3s` and 8 `ubuntu-k3s-*` apps (sync Unknown) remain.
  - Deregister runs only from `destroy_cluster`. The fix is a watcher plus a reaper that requires a positive "gone" signal.
- Vector DB dashboard change `a8f8dc13` is live: the ConfigMap has `graphMode: none`.

## 2026-10-09 — Vector DB dashboard: removed unlabeled sparkline on the reachability panel

- In `grafana-dashboard-vectordb.yaml`, panel 4 now has `graphMode: none`, the same as the other stat panels.
- It also has a hover description: 1 = ok, 0 = not ok, last published values.
- The operator found the unlabeled green band confusing.
- `vectordb_rules.bats` passes 10/10. `hub-grafana-dashboards` follows `k3d-manager-v1.42.0`, so the change is live after ArgoCD syncs.

## 2026-10-09 — Bug filed: frontend login hangs when Keycloak's Postgres restarts

- `docs/bugs/2026-10-09-frontend-login-callback-hangs-when-keycloak-db-restarts.md` (OPEN, P2):
  - The agent-0 `docker restart` (11:19 UTC) killed `postgres-keycloak`, and Keycloak's DB was refused.
  - The frontend `/callback` spinner has no timeout, so it spun with no error.
  - Healthy again by 11:25 (token/auth endpoints 0.08–0.24 s).
- Fix directions:
  - A. `LoginCallback.tsx` timeout plus retry (shopping-cart-frontend).
  - B. Get `postgres-keycloak` off agent-0, or tune the Keycloak DB pool (shopping-cart-infra `identity/keycloak`).
  - C. `FATAL: role "root"` log noise (the probe `$(POSTGRES_USER)` is not expanded in exec probes?).
- Not specified yet. Shopping-cart changes go via spec plus Codex on feature branches.

## 2026-10-09 — ArgoCD recovered; v1.43.0 spec gains the per-release bug tally and count routing

- The operator ran `docker restart k3d-k3d-cluster-agent-0`. Verified: agent-0 `/proxy/healthz` returns `ok`, all nodes are Ready, all 13 agent-0 pods are Running, the argocd-pf log says "healthz reachable", local :8080 and public argocd both return 200, `probe_success` is 1, and the `PublicEndpointDown` alert cleared.
- `docs/plans/v1.43.0-bug-priority-tracking.md` gains item 8 (`scripts/bug-tally.py` and `make bug-tally`: the release comes from the `**Branch:**` line, else the lowest tag containing the commit that added the doc, else the current `k3d-manager-v*` branch) and item 9 (`bug_count.match`/`reply`, which intercepts count questions in `ask_docs.answer` and `_run_cluster_ask` before any model or agent runs).
- Trigger: in Slack, Codex answered "3 bugs fixed in v1.42.0". Actual: 35 docs, about 24 fixed, 3 open, 8 with no Status line.
- Still pending: the Trivy check for payment #84, then the `enforce_admins` disable.

## 2026-10-09 — ArgoCD public 502: agent-0 kubelet tunnel dead; watchdog treats it as advisory (bug filed)

- An SMS `PublicEndpointDown` fired for argocd.3ai-talk.org (502). The API server can't dial agent-0's kubelet (`proxy error ... 192.168.97.4:10250, code 502`); the other nodes are fine and all are Ready. The argocd-pf supervisor is looping.
- `node-health-watch` logs "Ready but /healthz slow/unreachable (advisory, no restart)". This is the 2026-08-28 slow-node fix swallowing the dead-tunnel case.
- Filed `docs/bugs/2026-10-09-node-health-watch-ignores-ready-node-with-dead-kubelet-tunnel.md`: classify a fast tunnel 502 apart from slow, and recover after 6 ticks.
- Operator recovery: `docker restart k3d-k3d-cluster-agent-0`; Claude then verifies.
- Payment #84 re-run is all green (CI plus PR Validation, including Integration Tests). The Trivy check and the `enforce_admins` disable are still pending.

## 2026-10-09 — rabbitmq-client 1.1.0 released (library PR #9 merged); payment #84 CI re-run

- The operator merged **rabbitmq-client-java#9** at `572b7834`. Claude disabled `enforce_admins` for the merge, then restored it (read back `true`).
- Tagged **v1.1.0** at the merge SHA and created the GitHub release. Main CI: Build and Test, Integration Tests and Publish to GitHub Packages all succeeded. Maven package `com.shoppingcart.rabbitmq-client` now lists `1.1.0`.
- Re-ran payment #84's CI (`37882980617`) and PR Validation (`37882979798`). Next: confirm Integration Tests pass and the Trivy report no longer lists CVE-2026-47884, then disable `enforce_admins` on shopping-cart-payment for the operator to merge.

## 2026-10-08 — Payment PR #84: Copilot clean; CI red only because rabbitmq-client 1.1.0 is not published

- Copilot reviewed #84 with 0 comments. Two checks failed, Validate PR and Checkstyle & SpotBugs, both with `Could not resolve dependencies … com.shoppingcart:rabbitmq-client:jar:1.1.0`. This is the expected ordering failure. The dependent jobs (Build and Test, Integration Tests, Security Scan, image build) were skipped.
- Waiting on the operator to merge #9. Then Claude re-runs #84's CI, checks Integration Tests and the Trivy report, and stops for the operator to merge #84.

## 2026-10-08 — Boot 4: payment PR #84 open; Phase 2 verified (with a fix)

- Phase 2: Codex `a5ab5f8` is on origin, diff limited to 8 files. Claude found and fixed a spec violation in `6dfb8ba`: Codex dropped every CVE override and re-added none, so Boot 4.0.8 would have shipped `amqp-client` 5.27.1, `httpcore5` 5.3.6 and Jackson 2 2.21.5, all below the PR #81 CVE pins. They are re-added under Boot 4 property names (`jackson-2-bom.version`). Re-verified: 103 tests, 0 failures, Checkstyle 0, SpotBugs 0; spring-webmvc 7.0.9.
- Integration tests (Testcontainers) did NOT run locally: the OrbStack Docker API hangs (`docker info` / `docker ps` time out). The hub runs on OrbStack, so it was not restarted. Payment CI has an Integration Tests job.
- Library PR #9: CI green; 2 Copilot style comments fixed in `df376e2`, threads resolved. Waiting for the operator to merge.
- Payment PR **wilddog64/shopping-cart-payment#84** opened; Copilot requested. CI will fail to resolve rabbitmq-client 1.1.0 until #9 merges and publishes.

## 2026-10-08 — Boot 4: Phase 1 verified, library PR #9 open; Phase 2 dispatched

- Phase 1 verified independently: rabbitmq-client-java `00e70fd`, plus Claude's CHANGELOG commit `55a279c`, both on origin. `mvn clean install` with JDK 21 passes 73 tests, 0 failures. Gotcha: on this M4, `/usr/bin/java -version` hangs, so set `JAVA_HOME=/opt/homebrew/opt/openjdk@21/...`.
- Opened **wilddog64/rabbitmq-client-java#9**. CI is running. The Copilot request did not show up in `reviewRequests`; a background poller is waiting for its review.
- Phase 2 dispatched to Codex in shopping-cart-payment on `feat/spring-boot-4`, from `4e79be2`.
- Merge order for the operator: **#9 first**, since its merge publishes 1.1.0; then the payment PR. After merge, Claude re-pins `services/shopping-cart-payment` and verifies the CVE clears.

## 2026-10-08 — CVE Auto-Patch: "Open critical CVEs in our images (not remediated)" table

- Operator: "Current CVE Remediation Status" only shows applied patches and has nothing for CVEs that were not remediated. Cause: app-cve-scan writes a remediation event only when it finds a newer image to promote. Payment has none, so CVE-2026-47884 never showed there.
- Added panel id 11, `trivy_vulnerability_inventory{severity="CRITICAL", image_repository=~"wilddog64/.*"}`, at y 39; History moved to y 48. Guide row and CHANGELOG updated. `grafana_dashboard_appsets.bats`: 0 failures.
- Noticed, not filed: frontend and product-catalog log an `applied` event about daily with the **same** `to_image`. Worth a look later.
- Phase 1 (rabbitmq-client `00e70fd`) is on origin; Claude is re-running `mvn clean install` before dispatching Phase 2.

## 2026-10-08 — v1.44.0 bug: SMS recovery notifications + notify behaviour test

- Filed `docs/bugs/2026-10-08-sms-critical-no-resolved-notification-and-untested-notify-behaviour.md`, targeting v1.44.0. It is a bug doc, so exempt from the cap; v1.44.0 has 5 plan files. The operator agreed: "texts are free".
- Scope:
  - `sms-critical` gets `send_resolved: true`.
  - Both receivers get a resolved block in the body. Today the body only ranges `.Alerts.Firing`, so a resolved text would be blank.
  - A real-Alertmanager (v0.27.0) pytest with a webhook sink covers dedup, repeat, recovery, and guards for the acg email-only route and the Trivy null route, plus an `amtool template render` test.
  - Optional `make alertmanager-config`.
- The 10/15 `smstest` delete resolves silently unless this ships first.
- Operator instruction: after Phase 1 is verified, dispatch Phase 2. Then open the PRs, fix Copilot findings, and wait for the operator to merge before deploy.

## 2026-10-08 — SMS-test fake disk left firing until 2026-10-15 (deliberate)

- The operator is keeping `host="smstest"` (Pushgateway job `k3dm-disk-smstest`) firing for a week as interview material. It re-texts about once a day. **Do not treat `HostDiskSpaceCritical{host=smstest}` as a real disk alert.**
- **On or after 2026-10-15**, the operator runs `curl -sS -X DELETE http://localhost:19094/metrics/job/k3dm-disk-smstest`; Claude then confirms the series is gone and the alert resolved. The session cron reminder is best-effort; this entry is the durable record.

## 2026-10-08 — Payment CVE: Option A (Spring Boot 4) chosen; two-phase spec; SMS proof PASSED

- **SMS proof PASSED:** fake `host=smstest` → HostDiskSpaceCritical firing 20:08:30 → receiver `sms-critical` → sent 20:13:17 (email counter 21→22, failed 0; the 5m `group_wait` is why it took ~5m after firing) → the operator got the text. Cleanup DELETE pending (operator).
- The operator chose **Option A** and to **port rabbitmq-client** (not drop it). Spec appended to `docs/bugs/2026-10-08-payment-spring-webmvc-cve-no-oss-6x-fix.md`:
  - Phase 1: rabbitmq-client-java 1.1.0 on Boot 4.0.8 / Spring Cloud 2025.1.3, branch `feat/spring-boot-4`.
  - Phase 2: payment on Boot 4.0.8 with rabbitmq-client 1.1.0, branch `feat/spring-boot-4`.
  - Traps called out: the `jackson-bom.version` override now means Jackson 3; drop the Tomcat 10/Netty 4.1 overrides; a bare `flyway-core` stops auto-configuring in Boot 4; health classes moved to `org.springframework.boot.health.contributor`.
- The CVE Auto-Patch dashboard's "Critical CVE Alerts Firing 40" counts all `TrivyCriticalVulnerabilityDetected` alerts (39 upstream warning + 1 payment critical). The payment CVE is visible in the "Shopping-cart Unique CVEs" table. Offered to split the stat (not done).
- Next: dispatch Phase 1 to Codex → verify → library PR (operator go) → publish → Phase 2.

## 2026-10-08 — Payment critical CVE investigated; bug filed; `none` severity explained

- The only critical alert (`TrivyCriticalVulnerabilityDetected`, ubuntu-hostinger, `wilddog64/shopping-cart-payment`) is **CVE-2026-47884**, `spring-webmvc` 6.2.19, XsltView RCE (CVSS 9.8). There is **no open-source fix on Spring 6.x**; it is fixed only in 7.0.9 (Spring Boot 4). We already ship the newest 6.2.19 / Boot 3.5.16, and the deployed `sha-e3b6f06` is the newest payment build. Payment never uses XsltView. The alert does NOT go to SMS; it goes to cve-remediate + analyze. It has fired the whole 48h window.
- Filed `docs/bugs/2026-10-08-payment-spring-webmvc-cve-no-oss-6x-fix.md`. Options: A, Boot 4 upgrade; B, ship the Go port; C, a time-boxed VEX/ignore exception; D, accept. Recommended: C now with a 90-day expiry, then A or B. **Waiting on an operator decision.**
- Dashboard: the `none` row in "Firing alerts by severity" was `InfoInhibitor`, a kube-prometheus-stack meta-alert that fires while an `info` alert is active (`CPUThrottlingHigh` on argocd-repo-server). The stat and the table now exclude `Watchdog|InfoInhibitor`. The guide also notes that the Trivy critical does not text.
- SMS test: HostDiskSpaceCritical{host=smstest} **firing 20:08:30**; watcher checking delivery.

## 2026-10-08 — Alertmanager Delivery dashboard: Firing alerts table

- Operator asked which alerts the "40 warning / 1 critical" stat was counting. Added a **Firing alerts** table panel (instant `ALERTS{alertstate="firing",alertname!="Watchdog"}`, one row per alert) under the stats; documented in `docs/guides/grafana-dashboards.md`; CHANGELOG. Syncs via `hub-grafana-dashboards`.
- At 20:00 the 40 warnings were 26 hub + 13 ubuntu-hostinger `TrivyCriticalVulnerabilityDetected` (upstream images, e.g. argoproj/argocd, hashicorp/vault) + 1 `TargetDown` acg (sandbox down, expected); the 1 critical was `TrivyCriticalVulnerabilityDetected` on ubuntu-hostinger. Deep-dive deferred until the SMS test is done.
- SMS test in flight: operator pushed fake `host="smstest"` at 19:57; HostDiskSpaceCritical pending 19:58:16.

## 2026-10-08 — host-disk PrometheusRules live; SMS proof pending (operator)

- Operator ran `make prometheus-rules` → `host-disk` created, 6 rule files applied. Prometheus `host.disk` group: HostDiskSpaceLow / HostDiskSpaceCritical / HostDiskMetricsStale all health `ok`, state `inactive` (m2 60%, m4 63%).
- SMS proof method: running the collector by hand does NOT work — it PUTs job `k3dm-disk`, and Hermes overwrites that group every 300s, shorter than the critical rule's 10m `for`. Instead push a fake `host="smstest"` series under a separate job `k3dm-disk-smstest` (rules have no job filter), wait ~11–12m for the SMS, then `curl -X DELETE` that job.
- Next: operator runs the SMS proof; then dispatch the remote-targets spec (raise the Slack snapshot timeout above 1800 first).

## 2026-10-08 — Hub snapshot LIVE-VERIFIED; both bug docs closed

- Operator tmux run: `make snapshot` → `captured 20261009T022625Z` (preflight passed, rsync ~12m, auto-prune left the `.INCOMPLETE` with a warning); `make status` → `✓ Hub snapshot: 20261009T022625Z (0h old)`; `make snapshot-prune` removed `20261009T014249Z.INCOMPLETE`.
- M2 read-only: only `20261009T022625Z` remains (3.4 GB), MANIFEST 7 lines, SHA256SUMS 11/11 OK.
- `docs/bugs/2026-09-20-no-capture-producer-hub-pvc-data-unrecoverable.md` + `docs/bugs/2026-10-08-hub-snapshot-prune-deletes-newest-no-auto-retention.md` → LIVE-VERIFIED.
- Cosmetic: the prune message prints `K3DM_SNAPSHOT_KEEP`, not the actual retained count ("retained 3" with 1 present). Not filed.
- Next: operator `make prometheus-rules`; then dispatch the remote-targets spec (raise the Slack snapshot timeout above 1800 first — the capture took ~12m of rsync alone).

## 2026-10-08 — Disk sensor live: metrics + dashboard confirmed; `make prometheus-rules` added for the rule

- Hub Pushgateway `localhost:19094` already holds `job="k3dm-disk"` from the running Hermes (collector runs from the tree): m2 `k3dm-snapshots` 366 GiB free / 926 GiB (60% used), m4 `/System/Volumes/Data` 171 GiB free / 460 GiB (63%); probe_success 1 for both. launchd ssh `BatchMode` to m2jump works — NO Hermes restart needed.
- Dashboard ConfigMap `grafana-dashboard-host-disk` synced by `hub-grafana-dashboards` (pinned `k3d-manager-v1.42.0`, at `2ac8d68a`). NO AppSet reapply needed.
- PrometheusRule `host-disk` NOT in cluster: rules are only applied by full `make observability`. Added `make prometheus-rules` (Makefile-only; applies `scripts/etc/prometheus/rules/*.yaml` with the same `CF_DOMAIN` envsubst to `$(INFRA_CONTEXT)`). Server-side dry-run of every rule file passes. Operator runs it (cluster mutation).
- Fixed stale guide line "The hub has no Pushgateway by design" — `hub-pushgateway` exists (observability AppSet).
- Next: operator `make prometheus-rules`; Claude confirms `host-disk` rules loaded in Prometheus; prove the SMS path once.

## 2026-10-08 — Claude verified host disk-space sensor (`fb563727`); fixed default M2 path

- Codex `fb563727` (feature) + `acc7d05b` (memory-bank) on origin; HEAD = origin. Scope matches the spec's allowed files (13 files).
- RED (new tests on `5872ba40`, temp worktree): 7 fail — 4 collector, 2 rules/dashboard, 1 Hermes. GREEN: bare `pytest scripts/tests/bin scripts/tests/hermes -q` 769 passed / 1 skipped; `make validate-manifests` 2/2 valid.
- Claude fix: the collector's default M2 target was `m2jump:k3d-snapshots` (typo; real dir is `k3dm-snapshots`, `K3DM_SNAPSHOT_DIR` default) — live it would have reported probe_success 0 and fired `HostDiskMetricsStale` forever. Added `test_default_m2_target_is_the_snapshot_dir` (fails on the typo, passes on the fix). Dashboard "Free GiB" panel used `decgbytes` on a GiB value → now raw bytes with unit `bytes`, titled "Free".
- Live steps (operator): apply `scripts/etc/prometheus/rules/host-disk.yaml`; reapply hub AppSets (dashboard ConfigMap); `launchctl kickstart -k gui/$(id -u)/com.k3d-manager.hermes`; then Claude queries Prometheus for `k3dm_disk_avail_bytes`; prove the SMS path once. Open question for live: Hermes runs under launchd — ssh `BatchMode` to `m2jump` must work from that context, or m2 shows probe_success 0.
- Hub snapshot live run (`make snapshot; make status …; make snapshot-prune`) in progress in tmux `work:1.0`.

## 2026-10-08 — Claude verified hub snapshot round 6 (`81baeca9`); disk-sensor spec dispatched to Codex

- Codex `81baeca9` (fix) + `9587d645` (memory-bank) on origin; HEAD = origin. Scope = hub_snapshot.sh, hub_snapshot.bats, howto, CHANGELOG, bug-doc Status, memory-bank.
- RED (new bats on `a6a53d7d`, temp worktree): spec tests 1/2/5/6/8 fail, plus 3, 7 and the flipped `df` probe test. GREEN: hub_snapshot + hub_recovery 80/80, `scripts/tests/bin/cluster_down.bats` + `lib/cluster_down_provider_marker.bats` 24/24, shellcheck clean.
- Claude renamed the stale test "capture probes no remote free space" → "capture probes remote free space once" (it asserts exactly one `df`).
- `make snapshot-prune` is now SAFE (keeps newest). Auto-prune runs inside `make snapshot`; no separate scheduled prune (it could delete a concurrent upload's `.INCOMPLETE`).
- Disk sensor: `docs/plans/v1.42.0-host-disk-space-sensor.md` — 5th v1.42.0 plan, the CAP; anything further → v1.44.0. Hermes tick → `bin/k3dm-disk-metrics` → Pushgateway; rules `host-disk.yaml` (80% email, 90%/<20GiB SMS, stale email); dashboard `k3dm-host-disk`. Dispatched to Codex.
- Next (operator): rerun `make snapshot` in tmux → `make status CLUSTER_PROVIDER=k3s-hostinger`; then `make snapshot-prune` removes `20261009T014249Z.INCOMPLETE`.

## 2026-10-08 — Hub snapshot retention bug filed; dispatched to Codex (round 6)

- Operator asked for a retention policy (M2 space is finite). `K3DM_SNAPSHOT_KEEP=3` + `make snapshot-prune` exist, but: (1) prune keeps the OLDEST N and deletes the newest (`_hub_snapshot_remote_names` sorts ascending; the count-only test at hub_snapshot.bats:276 hid it); (2) nothing prunes automatically.
- Spec: `docs/bugs/2026-10-08-hub-snapshot-prune-deletes-newest-no-auto-retention.md`: newest-first prune, auto-prune after a verified capture (`K3DM_SNAPSHOT_AUTO_PRUNE=1`, never touches `.INCOMPLETE`), M2 free-space preflight (`K3DM_SNAPSHOT_MIN_FREE_GB=20`), checked final `mv` (round-5 minor finding).
- M2 read 2026-10-08: 369 GiB free of 926 GiB; partial `20261009T014249Z.INCOMPLETE` is 480 MB.
- Do NOT run `make snapshot-prune` until round 6 lands; today it would delete the newest snapshots.
- Status UNKNOWN-path `Hub snapshot:` line still queued separately.

## 2026-10-08 — Claude verified hub snapshot round 5 (`e3040689`)

- Codex `e3040689`/`a416dff2`/`d718c674` on origin; scope = hub_snapshot.sh, hub_recovery.sh, 2 bats, howto, bug doc, memory-bank.
- GREEN: hub_snapshot + hub_recovery + cluster_down + cluster_status_summary bats 109/109. shellcheck: only pre-existing SC1091 info in hub_recovery.sh. `trivy` count 0 in both plugins.
- RED: against `fbebe9df` plugins, the new rsync-staging, failing-rsync and seven-claim tests fail (temp worktree).
- Minor (queued for Codex with the status UNKNOWN-path item): the final remote `mv .INCOMPLETE → <ts>` exit status is unchecked. If it fails, the stamp is still written and "captured" printed, while the M2 copy stays `.INCOMPLETE`. The guard stays safe; only the local status line would be wrong.
- Operator renamed tonight's partial to `20261009T014249Z.INCOMPLETE`. Delete it after round 5 is live-verified: `ssh m2jump 'rm -rf k3dm-snapshots/20261009T014249Z.INCOMPLETE'`.
- NEXT: operator reruns `make snapshot` (~3.3 GB, 7 claims), then `make status CLUSTER_PROVIDER=k3s-hostinger`.

## 2026-10-08 — make snapshot round 5: capture LIVE-VERIFIED, upload cancelled; Trivy drop + atomic rename to Codex

- Live (tmux): tar capture of server-db + 8 claims OK in ~2 min (4.7 GB); rsync to m2jump at ~3.8 MB/s; operator cancelled at ~2.0 GB.
- Trivy claim = public vuln DB + scan cache (1.4 GB); operator approved dropping it (claims 8 → 7).
- SAFETY: an interrupted rsync leaves a bare `<ts>` dir that the guard counts as verified. Fix = upload to `.INCOMPLETE`, `mv` only after `sha256sum -c`.
- Spec: bug doc "Live verification — round 5"; Codex prompt `$CLAUDE_JOB_DIR/tmp/codex-hub-guard-r5.md`.
- Operator one-off: rename the partial `k3dm-snapshots/20261009T014249Z` to `.INCOMPLETE` on the M2.

## 2026-10-08 — Claude verified hub snapshot round 4 (`fbebe9df`, tar-stream capture)

- Codex `fbebe9df`/`2847d1e0`/`23f4e4b4` on origin; scope = hub_snapshot.sh, hub_snapshot.bats, howto, bug doc, memory-bank.
- GREEN: hub_snapshot + cluster_down + cluster_status_summary bats 61/61; shellcheck clean; `docker cp` count 0.
- RED: round-4 tests against `2e8996ae` hub_snapshot.sh fail (10 not ok) on a temp worktree.
- Gap found + documented (Claude): `hub_recovery_plan/restore` still read the directory layout, not `.tar`. Noted in howto and as a required input change in `docs/plans/v1.43.0-hub-dr-drill.md` §4.
- `make status CLUSTER_PROVIDER=k3s-hostinger` from tmux: HEALTHY; `Hub snapshot: none recorded` line LIVE-VERIFIED. `!`-shell "token unavailable" = locked Keychain, environmental.
- Queued (Codex): print the `Hub snapshot:` line on the UNKNOWN/token-unavailable path of `bin/cluster-status-summary`.
- NEXT: operator reruns `make snapshot` in tmux, then `make status CLUSTER_PROVIDER=k3s-hostinger`.

## 2026-10-08 — make snapshot round 4: setgid EPERM under /tmp; tar-stream capture dispatched to Codex

- The operator's live `make snapshot` after `2e8996ae` got the correct container but failed with `fchmodat2 raft: operation not permitted`.
- Cause: Vault's `raft` dir is setgid (`drwx--S--- 100:1000`). `docker cp` extracts into `/tmp` (group `wheel`, and the operator isn't a member), and macOS rejects setgid there. `docker cp` also drops uid 100 ownership.
- Fix spec "Live verification — round 4": `docker exec <node> tar -C <path> -cf - .` into one `.tar` per claim.
- `make status CLUSTER_PROVIDER=k3s-aws` printed "webhook token unavailable". That's operator-side; the hint is `make restart-webhook`.
- A stale `~/.local/share/k3d-manager/active-providers/k3s-aws` marker (Oct 6 04:22) is left from an expired sandbox, so `make status` sees two live providers. The existing remedy is `make down CLEANUP_STALE=1`.

## 2026-10-08 — Claude verified hub snapshot round 3 (`2e8996ae`); remote snapshot targets specced

- Verified on origin: `2e8996ae` (fix), `e918fcd0` (bug status) and `d2a60860` (memory-bank). Capture now maps the PV's nodeAffinity hostname through `_hub_recovery_logical_node` before building the container name. The bats kubectl stub returns real hostnames, and a new test asserts `docker cp k3d-k3d-cluster-agent-1:` and no doubled prefix.
- Claude's gates: bats 60/60 GREEN, shellcheck clean, RED at `32395370` (the new test fails).
- Pending, operator: rerun `make snapshot`, then `make status CLUSTER_PROVIDER=k3s-aws`.
- New spec `docs/plans/v1.42.0-hub-snapshot-remote-targets.md` (4th v1.42.0 plan doc):
  - Slack: `snapshot-list` at reader; `snapshot` and `hub-retain-pvs` at operator.
  - Cloud bridge: `make-snapshot-list` only.
  - `snapshot-prune` is never exposed.
  - Dispatch to Codex waits until the operator's live `make snapshot` succeeds.

## 2026-10-08 — Hub PVC live check: retain-pvs passed, make snapshot fails live (doubled container name), round 3 to Codex

- Operator ran `make hub-retain-pvs`: 8/8 PVs Delete → Retain. LIVE-VERIFIED.
- `make status` hit the multi-provider gate. Rerun it with `CLUSTER_PROVIDER=k3s-aws`.
- `make snapshot` failed with `No such container: k3d-k3d-cluster-k3d-k3d-cluster-agent-1`. Capture passes the PV's full nodeAffinity hostname to `_hub_snapshot_node_container`, which prefixes it again. The bats kubectl stub returns logical `agent-1`, so tests never saw it. Capture has never worked live since `d53ea1ba`.
- Spec appended to the bug doc ("Live verification — round 3"). Dispatched to Codex.

## 2026-10-08 — Claude verified hub teardown guard round 2 (`32395370`)

- Verified on origin: `32395370` (fix), `ca8db0d9` (bug status) and `06c3ab0e` (memory-bank). Scope: hub_snapshot.sh, the two .bats files, the bug doc and the memory-bank only.
- The guard now reports with `_warn` and returns 1, so `cluster-down` exits 2. Under DRY_RUN, the guard's reads run for real in a subshell while the preview continues. The `--probe " "` change is reverted.
- Claude's own gates: bats 59/59 GREEN (cluster_down, hub_snapshot, cluster_status_summary). Shellcheck clean. RED on a temp worktree at `fa3340bc`: the exit-2 and DRY_RUN-refusal tests both fail.
- Pending live verification (operator): `make snapshot`, then `make status` shows the `Hub snapshot:` line, then `make hub-retain-pvs`.

## 2026-10-08 — Claude reviewed Codex hub teardown guard (`fa3340bc`): 3 defects, round 2 dispatched

- Verified on origin: `fa3340bc`, `81d66e5b` and `b893a76e`. The change touches only spec-allowed files (13 files, +290/-18).
- The live refusal works: hub deletion stops before teardown. But the guard reports through `_err`, which `exit 1`s, so the spec'd exit 2 and the DRY_RUN preview are unreachable.
- Under DRY_RUN the guard parses the `[dry-run] ssh ...` preview as a snapshot name.
- The new test asserts `status -eq 1`, which locks in the defect. The unrequested `--probe " "` on `_hub_snapshot_ssh` fixes nothing under Bash 3.2.
- Findings are in the bug doc's "Review findings — round 1". Round 2 dispatched to Codex.

## 2026-10-08 — September PARTIAL bugs: rotator already fixed; hub PVC remaining fix dispatched to Codex

- `2026-09-22-ci-red-prometheus-reseed-and-rotator-base64.md`: actually FIXED. `base64 -d` landed in `945018ee` (PR #130) with `platform_ops_rotators.bats`; the triage's PARTIAL was wrong. Status corrected.
- `2026-09-20-no-capture-producer-hub-pvc-data-unrecoverable.md`: capture and full Vault coverage are done (`d53ea1ba`). Spec "Remaining fix (2026-10-08)" added: Fix A `--delete-hub` refuses without a verified M2 snapshot ≤24h or `DISCARD_HUB_DATA=1`; Fix B snapshot age in `make status`; Fix C `make hub-retain-pvs` (operator-run). Scheduling is out of scope (v1.43.0 DR plan D7). Dispatched to Codex.
- `docs/plans/v1.43.0-hub-dr-drill.md` D7: note to extend `hub_snapshot_guard_delete` rather than add a second guard.

## 2026-10-08 — Claude verified Codex ask preamble fix; settings allow rules removed

- Verified `e92d1d85` (fix), `1a0399f1` (bug status) and `a0daeab0` (memory-bank) on origin. The diff touches only `agent.py` (+4), the test file (+44), the bug doc and the memory-bank. GREEN: 5 passed. RED against pre-fix `agent.py` on a temp copy: 2 failed (the two preamble tests). `pytest scripts/tests/bin`: 522 passed, 1 skipped.
- With the operator's approval, removed 3 over-broad allow rules from `.claude/settings.local.json` (former lines 215 awk, 671 grep, 1524 pkill). Backup: `.claude/settings.local.json.bak-2026-10-08`. Both files are gitignored and not committed.
- LIVE-VERIFIED: after the operator ran `make restart-webhook`, a top-level `ask claude: which shell are you in` replied with only the answer text.

## 2026-10-08 — Codex September triage verified; /ask fixes live-verified; ask preamble leak filed and dispatched

- Verified Codex triage `fbdf1c23` + `65971034` on origin: only the 19 September bug docs + memory-bank changed. All 15 cited fix SHAs exist on earlier release branches (v1.36.0–v1.40.0). Result: 16 FIXED, 2 PARTIAL (hub PVC capture `d53ea1ba`, prometheus reseed/rotator `7d475a9f`), 1 UNKNOWN (frontend public URL), 0 OPEN.
- Live-verified `7089dd10` (ask argv `--`) and `b2c45ae3` (sandbox SHELL): operator's top-level `ask claude` answered "bash" in thread.
- Filed `docs/bugs/2026-10-08-ask-reply-leaks-cli-preamble.md` (P2): Claude CLI settings warnings print before `ANSWER:` and `removeprefix` keeps them, so they post to Slack. Dispatched to Codex.
- Operator decision pending: remove 3 over-broad allow rules in `.claude/settings.local.json` (lines 215, 671, 1524) that trigger the warnings.

## 2026-10-08 — Claude verified Codex three-bug fixes; v1.44.0 bug dashboard folded into v1.43.0; September bug triage queued for Codex

- Verified `7089dd10`/`2f7e0eb5`/`895221cb` on origin. The diff matches the specs. Claude ran full `pytest scripts/tests`: 758 passed, 1 skipped. The real `audit/remote-operator.jsonl` stayed at 6225 lines across the run (before the fix, every run added 3). Live check pending: the operator runs `make restart-webhook`, then a top-level `ask claude: what shell are you in`.
- Folded `docs/plans/v1.44.0-bug-lifecycle-dashboard.md` (now SUPERSEDED) into `v1.43.0-bug-priority-tracking.md`. Added: the 3 status formats, the archive exclusion, no partial push on failure, and the snapshot label. The ledger, inventory table, buckets and rename identity are deferred. v1.44.0 now has 4 live plans.
- Added status lines to 3 October docs that were already fixed: test-duration panel `3a254484`, product-catalog psycopg2 PR #58, cloud failure classification `2833c894`. Every October bug is now FIXED.
- Queued for Codex: an evidence-based triage of 18 September bug docs that have no Status line (Status lines only, no code). The OPEN ones then get fix dispatches.

## 2026-10-08 — v1.42.0 three bug fixes complete

- `7089dd10` fixes Claude prompt argv termination; `2f7e0eb5` isolates the remote-operator audit directory per pytest; `895221cb` separates stale Hermes apps from source refs.
- Status commits `0753460c`, `71cca587`, `eae01de6` record `FIXED in branch` with live verification pending (Claude); all commits pushed to `origin/k3d-manager-v1.42.0`. PR URL: none.
- RED tests failed against temporary pre-fix copies. GREEN: pytest `287 passed, 90 subtests passed`, Python `py_compile` clean, BATS `68/68` passed. No live cluster/webhook commands were run.

## 2026-10-08 — v1.42.0 bug survey; 2 new bugs filed; 3 fixes queued for Codex

- Filed `docs/bugs/2026-10-08-ask-claude-prompt-parsed-as-cli-option.md` (P1): top-level `/ask claude` dies with `unknown option '---USER QUESTION START---'` (claude CLI 2.1.290 rejects a dash-led positional). Fix: `-- user_prompt` last. Reproduced locally; `--` form verified working.
- Filed `docs/bugs/2026-10-08-webhook-tests-write-real-audit-log.md` (P2): 3 tests in `test_webhook_cluster_status_thread.py` write `actor:"test"` admin rows to the live `audit/remote-operator.jsonl` (72 rows since 10-02). Fix: autouse conftest fixture redirecting `webhook.policy.AUDIT_DIR`.
- Added Fix spec to `2026-10-08-hermes-values-branch-counts-sources-as-apps.md`.
- Stale statuses corrected: slash-role FIXED+live (`8aa14053`), thread routing FIXED+live (`fedcfcd8`), ask-bash FIXED in branch (`b2c45ae3`, live check blocked by the /ask claude bug), plan `v1.42.0-slack-authz-and-ask-scope-fixes.md` IMPLEMENTED.
- Next: dispatch the 3 bug fixes to Codex on `k3d-manager-v1.42.0`; operator: AppSets reapply.

## 2026-10-08 — cleanup/pushgateway fix VERIFIED by Claude

- 2026-10-08: relay redeployed (`7cab1773`, keychain unlocked first); pushgateway target back (up=1).

- Codex `87eef35e` (label fix + regression test), `0c487442` (ask-bash sandbox test rewrite),
  docs `ddbef25d` — on origin, scope matches the bug doc. Claude reran outside Codex: shellcheck
  clean, BATS 9/9; RED: new cleanup test fails vs `50975556` script; mutation: sandbox test fails
  with sandbox-exec disabled. Pending operator: `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger`,
  then confirm hub `up{job="k3dm-test-pushgateway"}` = 1. Live verify of v1.42.0 fixes still pending.

## 2026-10-08 — v1.42.0 fixes verified; cleanup-stale-sandbox kills Hostinger pushgateway PF

- Codex v1.42.0 fixes VERIFIED by Claude on origin: `fedcfcd8` (thread elif), `8aa14053` (relay
  caller cap), `b2c45ae3` (ask-bash scope; amended to also adjust `scripts/tests/lib/webhook.bats`
  fixtures — justified), docs `08918765`. Re-ran: shellcheck clean, pytest 516 passed/1 skipped,
  node 42/0. Real kubectl/helm reads work inside the sandbox.
- FALSE GREEN found: `ask_bash_scope.bats` test 4 (OS sandbox) sets repo root = fake HOME, so it
  fails on a real Mac (canary readable); passed only inside Codex's sandbox. The sandbox itself
  works (manual: indirect read → Operation not permitted). Test rewrite in the bug doc below.
- Alert investigation (`TargetDown{job=k3dm-test-pushgateway}` flapping): `bin/cleanup-stale-sandbox`
  boots out the UNSCOPED `com.k3d-manager.pushgateway-port-forward` = Hostinger's 9091 forwarder.
  3 outages each 1 min after a confirmed Slack cleanup; down since 15:32Z. `federate-acg` TargetDown
  = sandbox genuinely dead. Bug: `docs/bugs/2026-10-08-cleanup-stale-sandbox-kills-hostinger-pushgateway-forward.md`.
- Operator: run `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger` to restore :9091.
- Codex dispatched for the cleanup label fix + ask-bash test rewrite. Status: IN PROGRESS.

## 2026-10-08 — v1.42.0 review done; security + dispatch fixes dispatched to Codex

- Review outcome: v1.42.0 = bug-fix + Slack-hardening release. P0 = slash caller role (HIGH),
  ask-bash scope (HIGH); P1 = thread dispatch fallthrough (`bin/k3dm-webhook:811` `if`→`elif`).
  Operator items: Slack Event Subscriptions check, AppSets reapply for v1.42.0, live-verify ~10
  "FIXED in branch" bugs. Recommended: move the 2 v1.42.0 features to v1.43.0, freeze new specs.
- Spec: `docs/plans/v1.42.0-slack-authz-and-ask-scope-fixes.md` (plan 3 of 5). New findings in it:
  `/tmp` allowlist never matches canonical `/private/tmp`; wrapper injected via PATH only — Claude
  Code picks shell from `$SHELL`, so it may never run (Layer C sets `SHELL`); Layer B adds macOS
  `sandbox-exec` HOME read-deny.
- Codex dispatched (codex exec, background). Status: IN PROGRESS — verify SHAs on origin before trusting.

## 2026-10-08 — v1.44.0 bounded index diagnostics specified

Added docs/plans/v1.44.0-bounded-index-metrics-diagnostics.md as PROPOSED fifth/final v1.44.0 plan (four remote plans verified before writing).
Fixed Prometheus queries/source mapping, signed submitter capability, disabled-by-default activation,
dedicated collector isolation, time/series/byte limits and field-filtered evidence; no arbitrary
shell/agent/URL/PromQL. Distinguishes absent metrics from scrape failure with historical uncertainty.
Vector metrics producer defaults hub Pushgateway19094; do not assume test Pushgateway9091.
October8 screenshot gap cause remains unverified; no cloud request or runtime change.
Documentation gates required; publication SHA recorded in git history. No PR.

## 2026-10-08 — webhook/bridge security follow-up filed

Filed docs/bugs/2026-10-08-slack-slash-commands-trust-command-role.md and docs/bugs/2026-10-08-ask-bash-shell-string-bypasses-path-scope.md (OPEN, HIGH) after offline review of 6e54ca66bddf47973eff57216d290b5df821b529.
Policy seam: admin relay header accepts cluster-down despite reader caller; /k3dm caps to reader.
Exact wrapper reads harmless out-of-scope canary through -c; no credential read or live exploit.
Evidence and reproducible commands: docs/issues/2026-10-08-webhook-cloud-bridge-security-review.md. September fixes remain present;
sandbox Phase 1 is not a filesystem boundary. Bridge submitter identity already has v1.44 plan.
Cloudflare Access/runtime OS isolation remain unverified. Docs-only; no restart, runtime change or PR.
Publication SHA is recorded in git history; local doc checks/audit required before publication.

## 2026-10-08 — Hermes values_branch warning investigated

Recorded docs/issues/2026-10-08-hermes-values-branch-drift-investigation.md. Read-only diagnose-app jobs d6bfca01/76b9f911 confirm
hub-platform-ops and hub-vectordb compared-to v1.41.0 and Synced, versus sensor expected v1.42.0.
Expected derives from K3DM_RELEASE_BRANCH or Hermes checkout; pull does not reapply AppSets.
Baseline intent remains unknown; no live repin/restart. Filed docs/bugs/2026-10-08-hermes-values-branch-counts-sources-as-apps.md:
1 app/2 stale sources reproduces "2 apps" wording. Full 15 references not enumerated.
Documentation checks only; source fixture confirmed. Publication SHA in git history; no PR.

## 2026-10-08 — Checkout / Deployment No data investigated (PARTIAL)

Recorded docs/issues/2026-10-08-checkout-and-deployment-dashboard-no-data-triage.md. Bridge observability job 39c7dff6 succeeded, exit0;
Hostinger Grafana/Prometheus/Pushgateway pods Running. Source: deployment dashboard pins app-only
UID P5A1115AEDF367D43 but hub values do not pin that UID; Checkout uses default Prometheus while
k6 producer defaults to app Prometheus, k6 is not federated. CPU [5m] fix exists; live series and
rendered query unknown. Grafana browser login blocked panel inspector; current allowlist has no
PromQL. No datasource edits/loadtest/restarts. Older no-producer/no-applier/no-hub-Pushgateway prose
is stale against current code. Publication SHA is in git history; no PR.

## 2026-10-08 — Slack thread dispatch fallthrough triaged (REOPENED)

Reopened docs/bugs/2026-10-07-slack-thread-command-routing-gaps.md for a regression after routing was added.
At fefb741070ff87418b181508a8589969f38dcec3, new diagnostics/k3dm/argocd handlers form one
if/elif chain, followed by an independent `if cmd == "kill"` chain. Successful handlers
fall through to its unknown-command else. Stubbed workers reproduce one queued worker plus
false error for all three; k3dm help returns correctly. Evidence: docs/issues/2026-10-08-slack-thread-dispatch-fallthrough.md.
No deployed SHA/log confirmation, runtime fix, job submission, or restart. Suggested fix:
join dispatch chains with elif or explicit successful-handler returns, plus negative reply tests.
Previous duplicate-webhook explanation was a hypothesis; it is unnecessary to reproduce this.
Publication SHA is recorded in git history; no PR.

## 2026-10-07 — Slack thread routing audit filed; bug dashboard specified

Filed docs/bugs/2026-10-07-slack-thread-command-routing-gaps.md and docs/issues/2026-10-07-slack-thread-command-routing-audit.md. Compared all 16 relay commands: diagnostics,
k3dm, argocd-upgrade lack thread routes; hermes-auth is relay-local and requires design, not
auth bypass. Bare refresh/up/down/resume aliases return early; 8/8 isolated probes confirmed.
Other 12 have routing presence only; no live success claim or runtime fix. Added docs/plans/v1.44.0-bug-lifecycle-dashboard.md
as PROPOSED fourth v1.44.0 plan: canonical doc counts, unknown metadata, truthful transition
history, scan freshness and linked inventory. No deployment. Publication SHA is in git history.

## 2026-10-07 — v1.44.0 operator acceptance automation specified

Added docs/plans/v1.44.0-operator-acceptance-automation.md as PROPOSED, the third v1.44.0 plan after
cloud notification routing and submitter authentication (two found at drafting).
Pilot automates k3dm Tests transitions, bridge/log contracts, fake Slack cleanup, and indexing
canaries with honest result classification, redacted evidence, and deduplicated bug drafts.
Offline is default; live checks are opt-in, bounded, serialized, and do not execute cleanup.
Known bugs stay separate; no runtime code or deployment. Publication SHA is in file git history.

## 2026-10-07 — Slack stale sandbox cleanup reporting bug filed (OPEN, v1.42.0)

Filed docs/bugs/2026-10-07-slack-stale-sandbox-cleanup-misleading-reporting.md and an evidence issue. Operator used apply intentionally.
Help wrongly says every command without confirm previews despite supporting apply; local-only
scope is unclear. launchctl/kubectl failures are suppressed while completion claims success;
rm failures actually abort. Worker does not persist terminal status/exit evidence.
No live resource failure established, cleanup execution, or runtime fix. Index/search verification
follows publication; commit SHA is recorded in file git history. No PR.

## 2026-10-07 — last-success timestamp deletion bug filed (OPEN, v1.42.0)

Operator screenshot shows equal elapsed ages of 3.41 hours; that is expected when the latest
run passed. Offline success -> failure -> success reproduction confirms PUT replacement
deletes the last-success metric on failure (1000 -> ABSENT -> 3000), instead of preserving
1000 across the failed run. Filed docs/bugs/2026-10-07-test-metrics-last-success-lost-on-failure.md plus an evidence issue.
Preserve current failure-series replacement and durable per-target/origin success state.
Documentation only; no runtime fix or live service test. Publication SHA is in file git history.

## 2026-10-07 — k3dm Tests failure-history gap filed (OPEN, v1.42.0)

Filed docs/bugs/2026-10-07-k3dm-tests-failure-history-missing.md and an issue evidence note.
Operator screenshot shows latest passed / zero failures but "No data" in the instant current
failure table despite earlier failures in the six-hour graph. Acceptance adds a separate
time-range history table while preserving PUT replacement/current clearing; deduplicate scrape
samples and avoid invented run timestamps or high-cardinality run labels. Historical sample
availability remains unverified. Documentation only; implementation pending. No PR.
Publication commit is recorded in the git history for these files.

## 2026-10-06 — ask-docs summary failure bug filed (OPEN, v1.41.0)

docs/bugs/2026-10-06-ask-docs-model-failure-reported-as-success.md records operator Slack
10:44/10:48 AM: agy exit 1, Gemini timed out. Cause of CLI failure unknown; host not probed.
Current branch returns an unavailable sentinel as prose and writes job success; captured CLI
detail is deleted. Acceptance covers honest outcome reporting, retained sources, bounded scrubbed
failure metadata, and useful fallback budgets. Cheaper/cross-provider routing is optional design.
Existing fake-CLI fallback tests: system Python 8/8; runtime spawn unsupported, pytest unavailable.
Docs only; no runtime fix/provider switch. Local vector dedup unavailable; indexing unverified.

## 2026-10-06 — Empty Make-log regression traced; older canonical bug reopened

Reopened docs/bugs/2026-09-28-make-jobs-never-write-output-file.md and cross-linked the
October 6 evidence report. Commit 73d0ef5682ed33f4792ab82181f37d41497fc96e removed the
scrubbed output write when switching to streaming make.log; HTTP reader still expects output.
Producer tests were changed to make.log and explicitly absent output, missing the consumer contract.
Current acceptance: bounded redacted shared selection across cloud status and Slack consumers.
Operator's pasted find-similar-docs result confirms September/October reports were indexed.
Deployed revision and host logs remain unverified; underlying suite failures unknown.
Documentation only; no runtime fix or additional test job.

## 2026-10-06 — Existing empty-log bug extended to Slack and E2E

Updated `docs/bugs/2026-10-06-cloud-bridge-make-job-status-empty-output.md`: operator sees
automatic Slack output but cannot retrieve E2E job 033ceddc via logs. Slack thread logs,
diagnosis, and ask context omit make.log; cloud job-status also omits it. E2E final response
17:36:37Z is failed with empty output; failure cause remains unknown. Exact Slack command/error
not supplied, so thread association versus file lookup must be distinguished in live verification.
Added shared-selector/redaction/regression acceptance; no runtime changes or new test requests.

## 2026-10-06 — Second bridge test job succeeds but returns no log

## 2026-10-06 — Cloud-bridge Make output selection fixed

Implemented the shared bounded/redacted job-output selector for Make and non-Make jobs. Make
jobs prefer `make.log`, with deterministic fallback to `output` then `log`; other jobs retain
`log` then `output`. HTTP status and Slack logs/diagnosis/ask now share the selector. Focused
tests passed (12/12), `make test-python-unit` passed, and `make test-pytest` passed (689 passed,
2 skipped). Commit `d39ecf9d` is pushed to `origin/k3d-manager-v1.42.0`; no PR was created per
repository instructions. Live cloud/Slack verification is pending operator review.

## 2026-10-07 — v1.43.0 E2E failure-evidence enhancement specified

Added the proposed plan `docs/plans/v1.43.0-e2e-failure-artifacts.md`. Scope is structured
failure evidence captured before vCluster teardown, not a bug fix: run ID, exit code, failed
step/classification, bounded redacted excerpt, and durable summary/log/screenshot/trace links.
Implementation and artifact-store decisions remain future work.

## 2026-10-07 — ask-docs failure propagation fixed

Implemented the ask-docs outcome fix: failed, empty, or unavailable model summaries now produce
failed job status with preserved source links and bounded safe metadata; fallback attempts retain
a useful reserved budget. Focused tests passed (40/40), `make test-pytest` passed (692 passed,
2 skipped), and `make test-python-unit` passed. Live service/credential verification is pending
operator review.

## 2026-10-07 — ask-docs ISO-date redaction false positive fixed

Added the bug record and narrowed `_PHONE_RE` so ISO dates remain readable in sourced answers.
The existing ask-docs redaction regression now checks both preserved date and masked phone value.
Live Slack verification remains pending.

## 2026-10-07 — ask-docs latency metrics enhancement specified

Drafted `docs/plans/ask-docs-response-latency-metrics.md`. It is deliberately not assigned to
v1.34.0; v1.43.0 is the candidate after capacity review. The proposal covers bounded metrics,
Grafana p50/p95/p99 panels, phase timing, failure rates, and exact-job metadata correlation.

## 2026-10-07 — ask-docs quality observability enhancement specified

Drafted `docs/plans/ask-docs-quality-observability.md` as the companion quality spec. Release
placement remains TBD, with v1.43.0 as the candidate after capacity review. It covers useful
sources, citations, summary/fallback outcomes, explicit feedback, follow-up signals, and pinned
offline groundedness evaluation without raw-question or identity labels.

## 2026-10-07 — durable test-metrics log enhancement specified

Drafted `docs/plans/v1.43.0-test-metrics-log-retention.md` as the fifth and final v1.43.0 plan
candidate. Scope is durable local test-metrics logs, immediate tail path, permissions, retention,
and safe fallback; exporter semantics and test exit status remain unchanged.

## 2026-10-07 — cloud make-test-all metrics publication fixed

Added the lifecycle hook that publishes the captured `test-all` log once through the existing
metrics exporter, preserving the real test exit status and reporting publication failure
separately. Unit coverage proves publication occurs only for `test-all` and receives the log,
exit code, and duration. Live Pushgateway/Grafana verification remains pending.

`make-test-python-unit`, request `20261006T165715Z-make-test-python-unit`, job `5cc7f225`:
terminal success at 16:58:14Z, output empty, summary artifact only. Added evidence to
`docs/bugs/2026-10-06-cloud-bridge-make-job-status-empty-output.md`. Passing and failing Make
jobs both lose log visibility; host fix pending. No assertion/count details available remotely.

## 2026-10-06 — Cloud Make job-status empty output bug filed (OPEN, v1.41.0)

`docs/bugs/2026-10-06-cloud-bridge-make-job-status-empty-output.md`: test-all job ccc20dc9
FAILED at 16:47:47Z; final bridge response has output="" and summary only. Code mismatch:
Make executor writes make.log; job-status reads only output. Test failure cause remains unknown.
Fix acceptance covers bounded log selection, redaction, legacy output, and regression cases.
Docs only; live host log not accessed, similarity unavailable, vector ingestion not verified.

## 2026-10-06 — Cloud test-all Grafana publication gap filed (OPEN, v1.41.0)

`docs/bugs/2026-10-06-cloud-bridge-test-all-does-not-publish-grafana-metrics.md` records
real bridge request `20261006T163821Z-make-test-all`, job `ccc20dc9` (queued, then running).
Code shows test-all does not call the test metrics exporter; only test-metrics publishes.
Proposed acceptance: publish the captured result once without rerunning tests or hiding failures.
No runtime changes; terminal test result, live dashboard, and vector ingestion not verified.
Similarity retrieval unavailable; offline dedup distinguished the nightly push-failure bug.

## 2026-10-06 — Order-service Go Dependabot coverage gap documented (v1.41.0)

Filed `docs/bugs/2026-10-06-shopping-cart-order-go-dependabot-coverage-gap.md`.
Application issue #81 / PR #82: missing gomod /go and docker /go coverage fixed and merged
as `fc3fae5a24675b464c2c72ed27b747cc1ef74b86`; Java CI and coverage guard green.
Application module upgrade, image promotion, running-pod rescan, and vector ingestion remain
unverified. Report is in the tracked index-docs corpus; next index run must include this commit.
Similarity lookup unavailable (no embeddings credential / kubectl); offline dedup found no match.
Documentation only; no k3d-manager runtime changes or live tests.

# Progress — k3d-manager

## 2026-10-08 — Slack cleanup thread event fix

- [x] Applied the specified webhook full-body verification and Slack 64 KiB cap in `f127fd7b`.
- [x] Applied relay edge acknowledgment for bot-echo/subtype events and human-event tests in
  `d0eb99e8`; relay gate passed 45/45.
- [ ] Final BATS rerun, docs commit, push, and remote SHA confirmation remain pending.
- No PR URL: task explicitly prohibits PR creation.

## 2026-10-08 — cleanup-stale-sandbox Hostinger pushgateway fix

- [x] Changed cleanup to stop only `com.k3d-manager.sandbox.pushgateway-port-forward`.
- [x] Added fake-launchctl logging and regression coverage proving Hostinger's unscoped plist is
  preserved; the pre-change RED test failed as required.
- [x] Rewrote the Darwin OS-sandbox test to use a repository reader script with Layer A control.
- [x] ShellCheck passed; targeted BATS passed 9/9. Commits: `87eef35e`, `0c487442`.

## 2026-10-07 — webhook thread mock contract fixed

- [x] Updated the ask-docs thread test stub for the production `channel_id` keyword.
- [x] Related webhook thread/delivery tests passed 29/29.
- [x] Full `make test-all` passed 2,531 cases with 0 failures.
- [x] Pytest passed 718 with 2 skips.
- [x] Pushgateway refusal was non-fatal; test-all exited successfully.
- [x] Committed and pushed as `5309ec3a`; no PR created per repository instructions.

## 2026-10-07 — full `make test-all` verification

- [x] Ran `make test-all` in tmux pane `20261004195335:2.1`.
- [x] Main BATS suite passed 1,386/1,386, including all previously failing cases.
- [x] Bin BATS suite passed 332/332.
- [x] Python unit suites passed.
- [ ] Pytest failed 1/720: stale `_post_slack_bot` mock lacks `channel_id`.
- [x] Filed `docs/issues/2026-10-07-test-all-webhook-thread-mock-signature.md`.

## 2026-10-07 — `fab52a19` test-all failure investigation

- [x] Reviewed the six cloud failures and preserved their exact BATS output.
- [x] Re-ran observability and hub-snapshot suites together under tripwire: 32/32 passed.
- [x] Reproduced independent full-suite webhook fixture failures with curl status `000`
      and status 7, confirming test-harness/startup instability.
- [x] Filed `docs/issues/2026-10-07-test-all-fab52a19-order-dependent-failures.md`.
- [ ] Fix webhook fixture readiness/state isolation and improve failed-test artifact capture.

## 2026-10-06 — hub import for test metrics implemented

- [x] Added a hub Prometheus scrape job for `host.internal:9091` that retains only
      `k3dm_test_*` metrics and preserves Pushgateway labels.
- [x] Added `k3dm-tests-configmap.yaml` to the hub dashboard ApplicationSet.
- [x] Switched k3dm test dashboard panels to the hub `prometheus` datasource.
- [x] Dashboard and Pushgateway configuration BATS: 41/41 passed.
- [x] `make check-doc-links`: 1966 files OK.
- [ ] Operator runs `make test-all`, waits for the hub scrape interval, refreshes
      the existing hub Grafana dashboard, and confirms the metrics are visible.

## 2026-10-06 — makefile e2e recording fixture fixed

- [x] Scoped the fixture extractor's `endef` exit condition to the active
      `_e2e_recorded` definition and asserted that `script -q` is present.
- [x] Focused BATS test passed 1/1.
- [x] Full `bats scripts/tests/bin` passed 328/328.
- [x] `shellcheck -S error scripts/tests/bin/makefile_e2e_recorded.bats` passed.
- [x] `AGENT_AUDIT_MAX_IF=8 bash scripts/lib/agent_rigor.sh
      scripts/tests/bin/makefile_e2e_recorded.bats` passed.
- [ ] Fix and live-verify the separate Grafana datasource/topology no-data bug.

## 2026-10-06 — test-all case 236 and dashboard no-data triage

- [x] Confirmed the TTY fix: `hub_restore.bats` cases 149–235 passed.
- [x] Confirmed case 236 is a fixture bug: the awk extractor exits at an earlier
      `endef`, producing an empty `_e2e_recorded` fixture and the output `make: \\`probe' is up to date.`
- [x] Filed `docs/bugs/2026-10-06-makefile-e2e-recorded-fixture-exits-early.md`.
- [x] Confirmed the exporter pushed `test-all/local`; localhost:9091 contains the
      1707-case result, one failed case, exit code 2, and 466-second duration.
- [x] Filed `docs/bugs/2026-10-06-k3dm-tests-dashboard-no-data.md` because the
      dashboard's ACG datasource UID does not match the Hostinger Pushgateway topology.
- [ ] Fix the fixture extractor and align/verify the canonical Grafana Prometheus target.

## 2026-10-06 — `make test-all` hang fixed

- [x] Added `_run_noninteractive_restore` to redirect stdin from `/dev/null` for
      `hub_restore.bats` cases that do not test interactive key entry.
- [x] Focused suite passed 14/14 normally and 14/14 under a real TTY; the formerly
      hanging Grafana retry test completed and recorded all three health probes.
- [x] `AGENT_AUDIT_MAX_IF=8 bash scripts/lib/agent_rigor.sh scripts/tests/bin/hub_restore.bats`
      passed; the existing ShellCheck warnings are unchanged lines in the BATS fixture.
- [ ] Operator reruns the full `make test-all` to verify the suite progresses beyond case 152.

## 2026-10-06 — `make test-all` hang triaged

- [x] Inspected the active tmux pane and process tree; the run stopped after case 152
      in `scripts/tests/bin/hub_restore.bats`.
- [x] Confirmed the next Grafana retry test was blocked for over 36 minutes in
      `bin/hub-restore` while inheriting `/dev/ttys007` as stdin.
- [x] Filed `docs/bugs/2026-10-06-hub-restore-test-hangs-on-embeddings-prompt.md` and
      `docs/issues/2026-10-06-hub-restore-test-hang.md` with verbatim evidence.
- [ ] Make the unrelated-to-prompt tests non-interactive, add focused regression coverage,
      and rerun `make test-all`.

## 2026-10-07 — Make failure context live verification complete

- [x] Live `job-status` response for `ccc20dc9` included early failing tests 198 and
      200 with source lines, plus the final Make failure tail.
- [x] Closed the failure-context bug; underlying `deploy_observability` test failures
      remain separate defects to triage.

## 2026-10-07 — Make failure context fix in progress

- [x] Implemented failure-aware bounded output in `webhook.job_output` with redaction
      preserved and a regression test for early `not ok` plus final `make` failure.
- [x] Focused tests passed 24/24; `make test-python-unit` passed; `make test-pytest`
      passed 696 with 2 skipped.
- [ ] Run audit, commit/push, deploy/restart the relevant services, and live-verify a
      failed Make job includes both early failure context and final tail.

## 2026-10-07 — failed Make-job evidence gap queued

- [x] Filed `docs/bugs/2026-10-07-make-job-tail-omits-failure-context.md` with the live
      `ccc20dc9` evidence and bounded/redacted acceptance criteria.
- [x] Cross-linked the follow-up from the live-fixed Make output bug.
- [ ] Implement failure-aware bounded excerpts or retained redacted artifacts; coordinate
      with the v1.43.0 failure-evidence plan before changing the response contract.

## 2026-10-07 — Make-job output retrieval live verification

- [x] Operator ran `make restart-webhook; make restart-cloud-bridge` successfully.
- [x] Passing job `715265ab` returned `success` with non-empty `body.output`.
- [x] Failed job `ccc20dc9` returned `failed` with non-empty `body.output` ending in
      `make: *** [test] Error 1`.
- [ ] Follow up separately on preserving enough earlier failure context to explain a
      failed suite; the bounded output contract itself is now verified live.

## 2026-10-06 — long Slack command help standardization in progress

- [x] Filed `docs/bugs/2026-10-06-slack-command-help-inconsistent.md`.
- [x] Replaced dense long-form usage messages with readable examples across the
      remaining Slack command handlers and added representative regression coverage.
- [x] Relay tests passed (36/36 plus 8 Slack-command BATS); commit `eaa619dc` pushed.
- [x] Cloudflare Worker deployed as version `1c21d3e7-1e39-4dfc-aeee-b16f5b326233`;
      smoke check completed successfully. Live Slack confirmation remains pending.

## 2026-10-06 — Slack cluster-diagnose help clarification in progress

- [x] Filed `docs/bugs/2026-10-06-slack-cluster-diagnose-help-ambiguous.md`.
- [x] Replaced the dense parser grammar with example-based Slack help and added a
      regression test for the human-readable pod/application examples.
- [ ] Run tests, commit/push, deploy the relay, and re-test help in Slack.

## 2026-10-06 — Slack namespace-first pod diagnosis fix in progress

- [x] Filed `docs/bugs/2026-10-06-slack-cluster-diagnose-pod-order.md` with the exact
      Slack failure and requested command.
- [x] Added namespace-first `pod` shorthand mapping to the existing `describe-pod`
      diagnostic action, plus documentation and a regression test.
- [x] Relay tests passed (34/34 plus 8 Slack-command BATS); commit `75e6f56d` pushed.
- [x] Cloudflare Worker deployed as version `0f46f722-0d87-4b86-815b-3f278bc8e9de`;
      smoke check completed successfully. Live Slack retest remains pending.

## 2026-10-06 — Slack status thread context fix in progress

- [x] Filed `docs/bugs/2026-10-06-slack-status-thread-context-dropped.md`.
- [x] Forwarded `/cluster-diagnose` channel context and preserved channel context
      through native Slack thread-command dispatch for cluster status workers.
- [x] Focused Python tests: 11 passed; Slack relay Node tests: 33 passed; compilation
      and diff checks passed.
- [ ] Run repository gates, commit/push, then operator re-tests `/cluster-status` and
      `/cluster-diagnose` in the Slack thread.
- [x] Deployed the Cloudflare relay with `make deploy-worker`; version
      `432e1dfc-2f5c-4430-9e21-f45c4eb9b3fb`; smoke check completed successfully.

## 2026-10-07 — webhook analysis test false failure fixed

- [x] Filed `docs/bugs/2026-10-07-webhook-analysis-test-brittle-source-match.md` for the
      false failure caused by fixed-string source assertions.
- [x] Replaced the ordered-candidate assertion with a whitespace-independent Python source check
      and made the safe-sentinel assertion match the current semantic sentinel.
- [x] Verification: focused BATS 1/1; `bats scripts/tests/lib/webhook.bats` 65 passed / 6
      intentional skips; ShellCheck, `git diff --check`, and `_agent_audit` passed.
- [x] Commit `c0f5777e` pushed to `origin/k3d-manager-v1.42.0`.

> Compressed 2026-10-06 (v1.41.0 release prep). Full pre-compression detail:
> `memory-bank/archive/progress-2026-10-06.md`. Settled work lives in `CHANGELOG.md`,
> `docs/releases.md`, `docs/retro/`, `docs/issues/`, `docs/bugs/` and git history.
> This file tracks what is still open. Every unchecked item (and every checked item that still
> carries an inline `[ ]` sub-step) is retained verbatim below, under the heading it was filed
> under. Many pre-v1.41.0 items are likely stale: triage them against the tree before acting.

## Release ledger

Canonical: `docs/releases.md` (full history) and the README releases table (3 most recent).
Per-release detail: `CHANGELOG.md` and `docs/retro/`.

## 2026-10-06 — HIPAA readiness roadmap decision

- [x] Added an unversioned HIPAA readiness/compliance-gap-assessment theme to `docs/roadmap.md`.
- [ ] Future scope: inventory ePHI flows and providers, confirm BAAs, define the no-PHI boundary,
      and produce a control matrix before assigning implementation work to a release. v1.42.0 is
      at its five-plan cap.

## 2026-10-06 — v1.42.0 high-priority bug 1

- [x] E2E mutable `:latest` stale-image bug fixed in `98d2bbcb` on
      `k3d-manager-v1.42.0`; both runner manifests derive pull policy from the tag, explicit
      overrides are validated, docs and regression issue note added.
- [x] Verification: `bats scripts/tests/plugins/e2e.bats` = 66/66; `shellcheck
      scripts/plugins/e2e.sh` clean; `_agent_audit` passed; `make check-doc-links` = 1944 files OK.
- [ ] Separate E2E exit-1-after-pass defect remains for the next bug; pause for user verification
      before continuing.

## 2026-10-06 — v1.42.0 high-priority bug 2

- [x] E2E pass-but-exit-1 result-event cleanup bug fixed in `cb9184b0` on
      `k3d-manager-v1.42.0`; stale ConfigMap deletes use `--no-exit`, normal publication is
      best-effort, and the bug doc records the root cause.
- [x] Verification: `bats scripts/tests/plugins/e2e.bats` = 67/67; `shellcheck
      scripts/plugins/e2e.sh` clean; `_agent_audit` passed; doc-link hook passed.
- [ ] User to run the full live `make e2e` and verify before the next bug is selected.

## Process (standing rules — do not archive)

- Every implementation updates this file and `activeContext.md` with the real commit/PR SHA.
- Unexpected live failures get a dated `docs/issues/YYYY-MM-DD-*.md` record with verbatim evidence.
- Historical specs/issues are archived only when superseded or unreferenced; files are never deleted.
- Keep all new work within the five-plan milestone limit. **v1.34.0 is at 5/5 — the next spec opens v1.35.0.**
- Reapply the ApplicationSets (hub and ACG) every release, then run `argocd_check_values_branch`.

## v1.41.0 release prep (2026-10-06)

- [x] Compress memory-bank — `44e73006`.
- [x] `make test` 1374/1374 + `make test-pytest` 682 passed / 2 skipped at `44e73006` (2026-10-06).
- [x] Docs sweep — `0ceb5a37` (acg.md watcher section; 5 plan statuses DONE, SHAs verified).
- [x] CHANGELOG promoted to `[1.41.0] - 2026-10-06`; duplicate Added/Fixed blocks merged (entry text unchanged, verified); empty `[Unreleased]` kept.
- [x] Releases rows added; README table rotated to 3 rows (v1.38.0 + v1.37.0 into Older).
- [x] AppSets: `argocd_check_values_branch k3d-manager-v1.41.0` rc=0 — 27 refs (hub + ACG) already on the release branch, no reapply needed. Scope check vs origin/main: 257 files / 326 commits, 5 v1.41.0 plans (cap), every code/config file maps to a CHANGELOG entry. Local `main` fast-forwarded to v1.40.0 `b5500db2` by the operator (2026-10-06).
- [x] federate-acg rollout DONE 2026-10-06 12:29Z: operator restarted PF :19190 (new PID 3165); hub `up{job="federate-acg"}`=1, scrape 5.3 s / 30 s timeout, 23,772 samples (spec predicted 23,777).
- [x] Live smoke gate 2026-10-06: plain `make e2e` 91/8 (run 1791290346-2661) — all 8 `order-management`, caused by hub agent-0 serving cached pre-fix `:latest` (sha-35098ac) under `IfNotPresent`. Pinned `E2E_IMAGE_TAG=sha-e5e644d… make e2e` (run 1791290881-10078, f945a8e5): **98 passed / 0 failed of 102** → gate GREEN. `make` still exited 1 after the pass (unexplained, see bug doc).
- [ ] Filed `docs/bugs/2026-10-06-e2e-runner-ifnotpresent-serves-stale-latest-image.md` (pull policy from tag + exit-1-after-pass). Next: operator go on target release (v1.41.0 vs v1.42.0) + Codex dispatch; then go to `gh pr create` (body in scratchpad `pr-v1.41.0.md`). Merge waits for operator go.

## Open items (verbatim, grouped by original section)

### From: 2026-10-02 — v1.40.0 release close-out (gh auth churn deferred to next release, operator call)
- [x] e2e-tests publish run 37044992425 GREEN: sha-755ad2d… and latest both = sha256:78044624… (old latest 59abbc19). [ ] operator reruns `make e2e E2E_IMAGE_TAG=sha-755ad2d7efeb96dcb6d3701077264fc6b9374db3` (live smoke gate).
- [ ] Next release: Vault GHCR PAT lookup returns silently on empty/unreachable — should say which.
- [ ] v1.40.0 PR body drafted — operator go before gh pr create.

### From: 2026-10-01 — v1.40.0 spec handoff
- [x] Live e2e run `1790962990-9267` (commit cb8373ef, 2026-10-02): first run to reach Playwright — keycloak + payment rolled out (realm fix fef39649 works live). 49 passed / 8 failed / 102; all 8 = `api/payments.spec.ts` empty-body 401s, the known option-(b) set in `docs/bugs/2026-09-16-e2e-assertion-api-payments.md` (fix on payment `d2f2d55` + e2e-tests `df6b9c1` branches, unmerged; image pins pending). Health test now passes. [ ] Operator: merge both PRs, bump pins, rerun.
- [x] Live retrieval eval run 2026-10-01; numbers in vector-store.md + live floors. [ ] copy into v1.40.0 retro at release.
- [ ] Operator: restart cloud bridge + `make restart-webhook` to load artifacts.
- [ ] `/ask-docs` operator steps: `wrangler deploy` relay, Slack manifest `/ask-docs`, `make restart-webhook`, live smoke; then Claude calibrates `K3DM_ASK_DOCS_MIN_SCORE` and replaces the PLACEHOLDER fixture.

### From: 2026-10-01 — v1.40.0 review fix spec (Codex)
- [ ] Deferred review items 5–10: Vault root token, latency unit, duplicated overview dashboard,
  label cardinality, and release-label test location.

### From: 2026-09-30 — Hermes data_layer unknown-cause bug filed
- [ ] Preserve and display a bounded, redacted cause for historical `data_layer` unknown states.

### From: 2026-09-30 — Hermes dashboard bugs filed
- [ ] Add drill-down evidence/links to the current findings table.
- [ ] Explain numeric status history and expose evidence for unknown/degraded transitions.

### From: 2026-10-01 — Codex batch bug 2 complete (`2f8c3ec8`)
- [ ] Batch bug 3 remains.

### From: 2026-10-01 — Codex batch bug 1 complete (`8a7cdec9`)
- [ ] Batch bugs 2 and 3 remain.

### From: 2026-10-01 — bug backlog triage
- [ ] Operator: git pull + `make restart-webhook` so the running webhook loads the new agent.py.

### From: 2026-09-30 — vector store freshness
- [ ] v1.41.0 design: fixed moving ref (e.g. `k3dm-live`) so a reapply is never needed.
- [ ] Operator: let ArgoCD sync the rules and dashboard, and watch the Ingestion row for one poll.

### From: 2026-09-30 — MinIO registry bug closed
- [ ] Follow-up (owner): replace the sunset bitnamilegacy MinIO image (12 CRITICAL / 80 HIGH).

### From: 2026-09-30 — MinIO port merged
- [ ] Operator: `enforce_admins` back to true; hostinger post-merge checks.

### From: 2026-09-30 — MinIO port ready
- [ ] Operator: merge the shopping-cart-infra PR; run the post-merge checks.

### From: 2026-09-30 — hostinger KubeJobFailed root-caused
- [ ] Codex (shopping-cart-infra): finish the MinIO bitnamilegacy port safely for existing data; PR only.
- [ ] Operator: confirm shopping-cart-identity is Synced now that #101 is on main.

### From: 2026-09-30 — Alertmanager delivery dashboard
- [ ] Operator: confirm in Grafana after the next platform-ops sync.

### From: 2026-09-30 — Codex verification #3
- [ ] Operator: choose a fix for the Alertmanager Overview integration panels.

### From: 2026-09-30 — Codex verification #2 + handoff #3
- [ ] Codex: node_pressure → data_layer brief. Claude verifies on return.

### From: 2026-09-29 — Codex verification + next handoff
- [ ] Codex: hostnet-drift brief. Claude verifies on return.

### From: 2026-09-29 — host-network IP drift
- [ ] Codex: implement the brief in hostnetwork-pods-keep-stale-ip-after-node-restart.md.

### From: 2026-09-29 — Codex handoff: cosign prevention + Hermes R7
- [ ] Codex implements; Claude verifies SHA, tests and mutations independently.
- [ ] Operator: Prometheus log for the duplicate-timestamp scrape pool.

### From: 2026-09-29 — cosign restore
- [ ] Operator: approve Fix 1 (bring-up restore) and/or Fix 2 (Hermes R7).

### From: 2026-09-29 — Hermes status publish diagnostics
- [ ] Operator: read the new log line; then fix the named cause.
- [ ] Operator: `bin/k3dm-worker-setup` to repopulate the empty `CLOUDFLARE_API_TOKEN` GitHub secret.

### From: 2026-09-29 — /cluster-diagnose all-namespaces overview
- [ ] Operator: `make deploy-worker` (or merge to main) so Slack sees the new form.

### From: 2026-09-29 — e2e payment root cause documented
- [ ] Operator: choose auth option (e2e profile vs real token) before a Codex spec for the two repos.

### From: v1.40.0 in progress — 2026-09-27
- [ ] **the installer dropped `K3DM_HERMES_AUTO_KINE_GUARD=1` from the plist** —
      `_install_hermes_agent` regenerates from a template that omits it, so the
      auto Kine guard is now OFF. Restore or leave? User's call.
- [ ] **`eso` sensor reports unknown on a false negative** — the webhook defaults
      the provider to `k3s-aws`, whose context `ubuntu-k3s` is not registered, and
      `_kubectl_absent()` classifies kubectl's `context was not found` error as
      resource absence. Two fixes available: delete the stale context (necessary,
      not sufficient) and stop `_kubectl_absent()` treating a kubeconfig error as
      absence (the real fix). Not started.
- [ ] **`eso` sensor never evaluates the hub** — it exact-matches only the
      unprefixed names, so the `Hub ESO *` entries the webhook emits are invisible
      to it. Hub ESO failures surface only incidentally via `node_pressure`.
- [ ] **`keycloak-realm-reconcile` Job Failed for 6d21h** — `awk: command not
      found`; `quay.io/keycloak/keycloak:24.0` has no awk and the inline script
      uses it ~9 times. ArgoCD PostSync hook of `shopping-cart-identity`, so the
      manifest lives in **shopping-cart-infra** — spec + Codex. Likely the common
      cause of both remaining `node_pressure` failures (Keycloak, Frontend SSO
      login). Nothing alerted on it for six days.
- [ ] **hub `platform-ops/cosign-public-key` ExternalSecret still not synced** —
      1 of 8; this is the "Hub ESO ExternalSecrets" failure `node_pressure`
      reports. Pre-existing backlog item, now confirmed as the live cause.
- [ ] Hermes sensors reporting: `eso` unknown, `reachability` degraded
      (`frontend.3ai-talk.org`), `node_pressure` degraded (Keycloak, Hub ESO,
      Frontend SSO), `kine` healthy with `stale_acg_registration: true`.
- [ ] delete the stale `ubuntu-k3s` kube context — now load-bearing: it is the
      current context and does not exist, so unqualified `kubectl` reads error and
      read as empty listings.
- [ ] `workers/slack-relay/test/relay.test.mjs` runs in no make target and no
      CI job — same defect class, the only known remaining instance; no decision

### From: v1.39.0 shipped — 2026-09-27
- [ ] `docs/howto/makefile.md` still documents no `test`/`test-pytest`/`test-bin`/`test-all`
      target — pre-existing, not a v1.39.0 regression. Worth a pass in v1.40.0.
- [ ] `bin/k3dm-vectordb-metrics` is undocumented. Its sibling `bin/k3dm-vectordb-status` is
      covered in `docs/guides/vector-store.md`.
- [ ] Branch cleanup not run — v1.39.0 is not a 5-release boundary and the user did not ask.
      Branch deletion needs the user's explicit go.

### From: v1.39.0 k3dm-tests alerts moved to the ACG stack — 2026-09-27
- [ ] **`/k3dm help` omits the cluster lifecycle commands** — spec
      `docs/bugs/2026-09-27-k3dm-help-omits-cluster-lifecycle-commands.md` filed and committed
      `788deeb2`, pushed. Dispatched to Codex (session `01a0e3a3`). Help text only:
      `CLUSTER_COMMANDS` + a role-filtered section in `make_target_help`, four new tests in
      `scripts/tests/bin/webhook_make_targets.py`, a note in `docs/howto/slack-slash-commands.md`.
      The routing split stays — `/api/v1/make` has no job guard, no stall timer and no metrics push.
      VERIFIED 2026-09-27: Codex commits `f3cdc25a` (fix) + `86c18cf5` (memory), both on
      `origin/k3d-manager-v1.39.0`. Diff is exactly the three permitted files, insertions only;
      `workers/slack-relay/index.js`, `scripts/lib/webhook/lifecycle.py` and `bin/k3dm-webhook` show
      an empty diff. All four specified tests present; suite re-run by Claude: 33 tests, OK.
- [ ] **Slack job `c7faf86b` (`/cluster-up aws`) failed at Step 3.5/12** — the k3s-aws cluster
      provisioned fine (3 nodes Ready); `bin/cluster-up:402` then failed `_command_exist k3d`
      because `com.k3d-manager.webhook.plist` sets `PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`
      and `k3d` lives in `~/.local/bin`. Slack-driven `make up` always fails here; the same command
      run by hand succeeds. Fix NOT approved, NOT started: plist PATH (host config) or absolute
      `k3d` resolution in `bin/cluster-up` (durable). Metrics were pushed: `success 0`,
      `duration 644`, `status="failed"` — the deployment dashboard now has real data.
- [ ] Duration metrics (DEFECT 2) still undecided: fix in v1.39.0 or file for v1.40.0.
- [ ] My `:19190` forward propping up `federate-acg` is still undisclosed to a durable fix.

### From: embeddings credential + indexer resumability — 2026-09-26 complete
- [ ] v1.40.0 retrieval eval — first datapoint in hand, and it points at **ranking, not recall**:
      the correct doc for an `ArgoCD OutOfSync with no real diff` query ranked 4th of 5, and the
      whole band spanned 0.785-0.764 (0.021). Do not add a score threshold on this evidence; any
      cutoff in that band drops the right answer. Details in `activeContext.md`.
- [ ] v1.39.0 PR is NOT created — gates unmet. See `activeContext.md` for which.

### From: vectordb seed — 2026-09-26 verified
- [ ] `hub-vectordb` ExternalSecret still OutOfSync on CRD defaults despite ServerSideDiff
      being live — needs a hard refresh so the controller re-diffs under SSA. Operator's call.

### From: vectordb — 2026-09-26 final: running, one cosmetic OutOfSync left
- [ ] Operator: reapply the ApplicationSets so `d44ef5cd`'s `ServerSideDiff=true` reaches the
      live Application. Until then `hub-vectordb` stays `OutOfSync / Healthy` on the
      ExternalSecret alone — the workload is fine, the diff is spurious.
- [ ] Offered, not approved: seed `vectordb/postgres` in the automated Vault path
      (`_vault_kv_exists` -> generate -> `_vault_kv_put`) so the credential survives a hub rebuild.

### From: vectordb — 2026-09-26 later: Vault path written, ESO still denied
- [ ] Operator: apply the Vault policy so the grant is live. `vars.sh` alone changes nothing.
      Blocked on an operator-run `vault policy read eso-ldap-directory` first — Claude cannot
      read it (needs the root token) and so cannot confirm an overwrite would not revoke a
      prefix that was merged in out of band.
- [ ] Operator: reapply the ApplicationSets for the `ServerSideDiff` annotation (`d44ef5cd`).
- [ ] Then Claude verifies read-only: `vectordb-postgres` `SecretSynced/True`, `pod/vectordb-0`
      Running, `hub-vectordb` `Synced/Healthy`.

### From: WS1 vectordb — live status 2026-09-26
- [ ] BLOCKED — operator: write Vault `vectordb/postgres` with `username` and `password`.
      `vectordb-postgres` is `SecretSyncedError` and `pod/vectordb-0` is
      `CreateContainerConfigError` until it exists. Claude must not create, read, print or log
      that value.
- [ ] Operator: reapply the ApplicationSets so the `ServerSideDiff` annotation reaches the live
      Application. The git fix is inert until then.
- [ ] Then Claude verifies read-only: `hub-vectordb` `Synced/Healthy` and `vectordb-postgres`
      `SecretSynced/True`.
- [ ] Latent: `observability.yaml` and `data-git.yaml` lack the same annotation. No symptom today
      (their ExternalSecrets are on `ubuntu-hostinger`); any ESO resource added to them will drift.

### From: 2026-09-26 — v1.38.0 MERGED, tagged and released; v1.39.0 branch cut
- [ ] **BLOCKS WS2 — the embeddings provider is undecided and no credential exists.**
  `k3dm-openai-api-key`, `k3dm-embeddings-api-key` and `k3dm-anthropic-api-key` are all absent
  (existence check only, no value read). **`gemini-cli-api-key` does exist** and Gemini embeddings
  are free-tier, making it the candidate needing no new credential — but it was provisioned for the
  Gemini CLI and **repurposing it needs the operator's explicit go**. WS1 does not depend on this;
  WS2 cannot start without it.
  WS2 cannot start without it. RESOLVED 2026-09-26: the operator approved reusing
  `gemini-cli-api-key`, and ruled that it stays the single keychain copy — the remaining absent items
  stay absent rather than being filled with duplicates. See the one-slot decision in
  `activeContext.md`.
- [ ] **WS1 needs the operator's go** — it deploys pgvector to the hub. Prerequisites verified
  2026-09-26: ESO on the hub is healthy (6 of 7 ExternalSecrets `SecretSynced/True`; the one
  failure is the pre-existing `cosign-public-key` in `platform-ops`), and the hub-scoped Application
  pattern to copy already exists (`hub-loki`, `hub-platform-ops`). WS1 must **not** use the
  `role: app-cluster` selector.
  - [ ] `docs/plans/v1.39.0-test-suite-metrics-and-staleness.md` — **dispatched to Codex**
  - [ ] `docs/plans/v1.39.0-public-endpoint-blackbox-probes.md` — **dispatched to Codex, offline half
        only**; the live TSDB verification and the ApplicationSet reapply stay operator-owned.
  Operator follow-up: `make restart-webhook` before `/k3dm smoke` resolves.
- [ ] **NOT DONE and NOT to be retried as a sync: `shopping-cart-identity`** — deterministic
  failure, not drift. `Replace=true` in its syncOptions makes ArgoCD `kubectl replace` the bound
  `postgres-keycloak-pvc`, whose spec is immutable except `resources.requests`; the manifest
  omits `volumeName`/`storageClassName` so the replacement blanks them and the API server rejects
  it. Retry limit 5 exhausted, `phase: Failed`, which also blocks self-heal. Holds back 3
  ExternalSecrets and prevents `Job/keycloak-realm-reconcile` from being created at all.
  Already filed: `docs/bugs/2026-09-23-argocd-identity-replace-true-cannot-update-bound-pvc.md`
  (dedup check caught it; no second file). **Appended update disproves that doc's open question**
  — the realm-reconcile failure is independent, caused by `awk: command not found` in the
  `ubi9-micro` image. **Two fixes needed; the PVC one must land first** or the awk fix cannot be
  observed. Needs the operator's go on which fix option (per-resource `Replace=false` annotation
  in `shopping-cart-infra` is the filed preference).
- [ ] **Delete the stale `ubuntu-k3s` kube context** — now escalated from a ~90s-per-query
  annoyance to having burned a release step. `kubectl config delete-context ubuntu-k3s`. Operator's
  call (config mutation).
- [ ] **Branch cleanup NOT run** — due every 5 releases; v1.35.0 was the last multiple, so
  v1.40.0 is next. Run early only if the operator asks.
- [ ] **`875f97da` missed the squash** — the memory-bank commit queueing the cloud-bridge
  architecture doc was pushed after the merge window and is **not in `main`**. Cherry-picked
  onto `k3d-manager-v1.39.0` as `ed697ef3`. Lesson: a push to a branch whose PR is already
  merge-ready is a push into a closing window.
- [ ] **Release-scope decision — NOW DUE, blocks v1.39.0 planning** — four v1.38.0 specs
  shipped as specs only (public-endpoint
  blackbox probes, hermes app-health delta sensor, slack smoke target, vector-store prior
  art). Carrying all four to v1.39.0 puts that branch at **6 plan docs, one over the max-5
  cap**, so they must be split across v1.39.0/v1.40.0 or dropped. Decide at `/post-merge`.
- [ ] **Cloud-bridge architecture doc — queued for v1.39.0** (operator, 2026-09-25). There is
  no `docs/architecture/` page for the bridge: v1.38.0 shipped
  `docs/howto/cloud-session-requests.md`, which is a usage contract (schema, actions, exit
  codes), not a design view. Missing: the request/response topology across the trust boundary,
  the two-token model and why a header may only narrow a role, the bare-clone + git-plumbing
  choice, the validator's ordered reject chain, and the deliberately unbuilt push path.
  **Not a plan doc** — `docs/architecture/` is outside the max-5 cap, so this does not
  compete with the four carried v1.38.0 specs. House style is Mermaid (9 of 11 existing
  architecture docs), plus a README `## Documentation` link.

### From: 2026-09-25 — `/api/v1/health` has been 500ing since v1.37.0 (found during v1.38.0 verify)
- [ ] Follow-up, not in this fix: no gate asserts `/api/v1/health` returns 200 and parses its
      `services` array. That is why a dead endpoint merged. Belongs with the webhook smoke gate.
- [ ] Bears on the pending v1.37.0 tag: the broken endpoint is ON the v1.37.0 tree and the fix is
      only on `k3d-manager-v1.38.0`. Tagging v1.37.0 as-is tags a webhook whose `/api/v1/health`
      and post-provision check both raise. Operator's call.

### From: 2026-09-25 — S3 gate hole closed for the health query form (Claude)
- [ ] Positive-path live check (admin 200 / reader 200 on health, reader 200 on POST
      `cluster-status`) is the operator's — it needs the token values, which Claude does not read.
- [ ] No live escalation test offered on purpose: every above-reader POST route
      (`argocd-upgrade`, `cluster-refresh`, `cve-remediate`, `analyze`) mutates or is expensive, so
      a probe that found the gate broken would execute the action. That case is covered by the
      synthetic-route unit tests instead, both mutation-checked.
- [ ] Part 2 (P2 bridge + P5) not dispatched.

### From: 2026-09-24 — unknown actor role authorization fix (commit pending)
- [ ] Implement the BATS fix (Part A — stub the reachability probe, hard-fail `ssh`/`scp`).
      **Part B (move the SSH-key guard in `shopping_cart.sh`) needs the owner's go** — it changes
      behavior on the already-Ready path.
- [ ] Sweep the rest of `scripts/tests/` for reachability-dependent live mutation (own spec).

### From: 2026-09-24 — webhook Phase 3 agent extraction (staged; Git blocked)
- [ ] Commit/push and final SHA verification remain; Git returned
      `fatal: Unable to create '.git/index.lock': Operation not permitted`. No retry,
      lock removal, hook bypass, force-push, or PR was attempted. Changes are staged.

### From: 2026-09-24 — upstream credential-test observability (dispatched)
- [ ] Verify Codex: SHA on origin, diff confined to the four listed files, jest > 28 tests, all three
      mutations reddening their named tests, disappearance gate 4 -> 0.
- [ ] **Operator action:** dismiss CodeQL alerts 23/24/26/27 via `gh api` — the classifier
  denied it as a CI bypass; must be run from the operator's terminal. Blocks the #131 CodeQL
  gate; `enforce_admins` untouched until then.

### From: 2026-09-24 — ACG preflight account-name fix
- [ ] Operator, at the Mac in Terminal.app: populate both accounts, then
      `make -C scripts/lib/foundation credential-test` expecting `ACG_SESSION_OK`. All three
      accounts measured absent on 2026-09-24; nothing to clean up first.

### From: 2026-09-24 — Tier 2 ACG preflight (working tree complete; Git blocked)
- [ ] Git staging was blocked by `.git/index.lock: Operation not permitted`; no commit SHA
      or push exists. The requested files remain unstaged; operator must stage, commit, and push.

### From: 2026-09-24 — webhook Phase 1b authorization (staged; commit blocked)
- [ ] Commit/push blocked by `.git/index.lock: Operation not permitted`; no SHA exists.
      The staged implementation is ready for the operator/Claude to commit and push with the
      exact requested message. The import gate used `/usr/bin/python3` 3.9.6 and failed before
      module execution on existing `str | None` annotations; `make test-all` also encountered
      the sandbox's restricted `/var/folders` temp root. No out-of-scope files were changed.

### From: 2026-09-24 — webhook Phase 1 extraction (working tree only; blocked)
- [ ] `make test-all` is not green because an unrelated existing `cluster_status_summary.bats`
      JSON assertion expects one failed service while its fixture returns two; the system
      `python3` used by Make also has no pytest unless PATH is shimmed. No out-of-scope test
      fix was made. No issue doc was created because the dispatch explicitly forbids modifying
      files outside its target list.
- [ ] Commit/push blocked by sandbox Git write restrictions (`.git/index.lock`,
      `.git/COMMIT_EDITMSG`, and temporary tree objects: `Operation not permitted`); no SHA.

### From: 2026-09-24 — app-CVE scan trigger target
- [ ] `make test` completed **1105 tests** but exited 1 on unrelated pre-existing
      `e2e_remote.bats` tests 688, 699, 723, and 724; left untouched per scope. No live
      cluster commands were run. Commit/push is blocked by `.git/index.lock: Operation not
      permitted`; no commit SHA exists yet.

### From: 2026-09-23 — Hostinger registration must survive a hub rebuild (spec filed)
- [ ] **Operator: re-register hostinger** — `make refresh-registration CLUSTER_PROVIDER=k3s-hostinger`.
      Live hub mutation; needs the user's go. Hostinger workloads are unmanaged until then.
- [ ] **Durability unproven until a rebuild happens with the fix in place.** A reconcile that has
      never run during an actual rebuild is a claim, not a verified fix. The bug doc stays open.

### From: 2026-09-23 — Alertmanager warning-severity delivery fix
- [ ] **NOT YET DEPLOYED** — the live Alertmanager still runs the old two-route tree and is
      still discarding `KubeJobFailed`. Needs the operator to re-render the Alertmanager
      secret, then confirm `platform-warning` appears in the route tree and that a
      `KubeJobFailed` email actually arrives. Delivery is unproven until then.

### From: 2026-09-23 — M2 GHCR credential root-caused (locked keychain), fix dispatched to Codex
- [ ] **Tier 1 still unproven** — all three fixes (GHCR stdin `9d2a0ad0`, leak `7338a238`,
      the ensure_exists fix) are unexercised against the live runner. A dispatch is needed to confirm,
      and needs the operator's go.
- [ ] **Hostinger hub registration LOST AGAIN 2026-09-23** — regression of a doc marked DONE.
      The 2026-09-20T23:49Z hub rebuild recreated only `ubuntu-k3s-app-cluster` (in-cluster);
      `cluster-ubuntu-hostinger` is absent and 0 `ubuntu-hostinger-*` Applications exist. This
      is why CVE Auto-Patch has no data: `cve-remediation-verify` fails every 15 min with
      `secrets "cluster-ubuntu-hostinger" not found`, so no remediation event ConfigMap is
      written and the exporter emits zero `cve_*` gauges. Recurrence appended to
      `docs/bugs/2026-09-13-hostinger-app-cluster-registration-lost-orphaned-workloads.md`.
      Needs the operator's go: no registration-only entry point exists, and
      `make refresh CLUSTER_PROVIDER=k3s-hostinger` remains unsafe and unapproved. The real
      fix is making registration survive a rebuild — otherwise recurrence #3 is scheduled.
      Also: 3 consecutive CronJob failures raised no alert.
- [ ] **Hermes still BOOTED OUT** — must stay down until both blockers are fixed, or it
      re-wedges the runner every 5 minutes. Restore:
      `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.k3d-manager.hermes.plist`

### From: 2026-09-23 — shopping-cart made opt-in per app cluster (code done, reapply pending)
- [ ] ~~PENDING OPERATOR GO~~ (superseded) Task 0 re-capture (read-only),
      then reapply the ApplicationSets for hub **and** ACG, then `argocd_check_values_branch`.
      Expect zero `ubuntu-k3s-data-layer` / `ubuntu-k3s-shopping-cart-*`; verify `ubuntu-k3s-eso`
      and `ubuntu-k3s-grafana-dashboards` still Synced with 21 ESO CRDs and 22 ExternalSecrets.
      `data-git` prunes and holds the resources finalizer — if StatefulSets or bound PVCs have
      appeared in `shopping-cart-data`, stop.
- [ ] **Then decide 3a vs 3b** — `preserveResourcesOnDeletion: true` leaves the `shopping-cart-apps`
      Deployments running unmanaged. 3a deletes the `shopping-cart-apps` + `shopping-cart-data`
      namespaces; 3b keeps them as an unmanaged demo. Never delete the `secrets` namespace.
- [ ] **ESO re-homing** — queued in `docs/roadmap.md` Forward themes, unversioned, needs a scope doc
      (the 21 CRDs must be adopted, not recreated).

### From: 2026-09-22 — v1.36.0 smoke and hub snapshot features
- [ ] **Residual gap, accepted knowingly:** on a *transfer* failure the remote directory is left
  un-marked rather than `.INCOMPLETE` (checksum failures still mark it). Two-line fix available;
  awaiting the operator's word.

### From: 2026-09-22 — Prometheus Vault entry repaired
- [ ] **Does not affect Grafana** — hub Prometheus has no basic auth; the blank e2e panels are
  still a producer problem, unblocked only by a Tier 1 run.
- [ ] Realm SSO rows still read "not provisioned": `secret/keycloak/` has only
  `['admin','clients']`, no `users/`. Seeding remains an operator decision.

### From: 2026-09-22 — Webhook decomposition specced, QUEUED for v1.37.0
- [ ] **Follow-up worth acting on independently of the refactor:** `_fix_mode_enabled` gates
  whether an AI agent may mutate the cluster and has **no test today**. Phase 3 adds one, but
  it does not have to wait for the refactor.
- [ ] **Gate hygiene finding:** the three `webhook_*.py` suites are `unittest`, run only via
  `make test-python-unit`'s `scripts/tests/bin/*.py` loop, and are invisible to both
  `make test` and `make test-pytest` — so `make test` cannot catch a break in any of the 37
  Python cases. Use `make test-all`. (Initially suspected orphaned; that was wrong.)

### From: 2026-09-22 — Grafana triage + two specs assigned to Codex
- [ ] **e2e failure-detail gap (NEW, real).** A failed run published no `e2e_failure_info`
  or `e2e_failure_group_info`, and `e2e_run_info` carries a malformed `failure_ratio="/"`
  (empty-over-empty). Belongs to `docs/plans/v1.36.0-e2e-deterministic-triage-and-corpus.md`.
- [ ] **Tier 2 e2e blocked (re-verified 2026-09-23).** No ACG context (`k3d-k3d-cluster`,
  `ubuntu-hostinger` only); keychain `k3dm-acg-pluralsight` **ABSENT**. Manual TTY login
  required — operator-only.
- [ ] **Tier 1 e2e RAN 2026-09-23 and FAILED twice — both blockers filed, neither a
  shopping-cart regression.** (1) A leaked vCluster from a 09:04Z failure wedged the shared
  `vclusters` namespace; ~17 Hermes dispatches failed identically over 2h. Cleared; leak
  reproduces on every failure → `docs/bugs/2026-09-23-e2e-failed-run-leaks-vcluster-and-wedges-all-later-runs.md`.
  (2) The runner cannot obtain a GHCR PAT — Gap 3 of
  `docs/bugs/2026-08-22-e2e-m2-runner-bootstrap-kubeconfig-and-ghcr-gaps.md` regressed
  (m2jump's `gh` token invalid; Vault path hardcoded to the hub context). Commits `ea6d39ca`,
  `84798fc0`.
- [ ] **Hermes is BOOTED OUT — restore it.** `launchctl bootstrap gui/$(id -u)
  ~/Library/LaunchAgents/com.k3d-manager.hermes.plist`. Leave it down until the GHCR
  credential is fixed, or it re-wedges the runner every 5 minutes.
- [ ] **Correction: the 2026-09-22 credential clearance was the M4's `gh` token, not M2's.**
  The GHCR pull happens on the runner, so that entry did not clear Tier 1.
- [ ] **Snapshot capture NOT wired into `make down`/`make up`** — deliberately out of scope
  until capture is proven on a real hub.

### From: 2026-09-21 — rotate-ghcr-pat fix prepared; blocked before commit
- [ ] `docs/bugs/2026-09-21-rotate-ghcr-pat-targets-wrong-cluster-and-leaks-pat-in-argv.md`:
  exact Changes 1–4 implemented in `bin/rotate-ghcr-pat`; five static BATS gates added in
  `scripts/tests/bin/rotate_ghcr_pat.bats`. Counts proved non-vacuous: hardcoded context 2→0;
  pull probe 0→2; `--docker-password` 1→0; Vault-token argv 2→0;
  `/user` validation 1→0; ESO branch 0→1. **Correction by Claude:** the PAT basic-auth argv gate
  was reported 1→0 but measured 0→0 (vacuous, stray `\${` escapes); pattern fixed and re-verified. Pull probe line 59 is before `gh secret set` line 106.
  `shellcheck -S warning` and `shellcheck -S error` clean; focused BATS 5/5. Commit/push pending:
  `git commit` failed with `fatal: Unable to create .git/index.lock: Operation not permitted`,
  so there is no SHA or origin verification yet.

### From: Open items
- [ ] **Prometheus local-port drift: 19090 vs 19190.** `_acg_prom_local_port` computes
  `19190 + offset`, and `k3s-aws` offset is **0**, so the app-cluster Prometheus forward is 19190 —
  which is what `bin/k3dm-webhook:2233` probes. But `scripts/etc/cloudflared/config.yml` (and the
  installed `~/.cloudflared/config.yml`) map `prometheus.3ai-talk.org` to **19090**. One of the two
  is wrong; `prometheus.3ai-talk.org` cannot work while they disagree. Separately the hub's own
  launchd agent forwards 19091. Three ports for one service — needs a decision, then one source of
  truth. Not yet filed as a bug doc.
- [ ] **GHCR pull is 403 — and `shopping_cart_resolve_ghcr_pat` poisoned the Vault cache.**
  All four `shopping-cart-apps` pods are `ImagePullBackOff`:
  `403 Forbidden` from `ghcr.io/v2/wilddog64/shopping-cart-frontend/blobs/...`. Root cause: the
  function's fallback chain reached "use gh CLI token", and `gh auth status` reports scopes
  `admin:public_key, gist, read:org, repo` — **no `read:packages`**. It then wrote that token to
  `secret/github/pat` and logged `gh CLI token saved to Vault for future runs`, so every later run
  will find it in Vault and reuse a token that cannot pull. Two defects worth filing:
  1. The gh CLI branch is **not validated** before saving, unlike the Vault branch, which does
     check (`Vault PAT is expired (HTTP ${_pat_http})`). Validate for `read:packages` first.
  2. The Vault write is `|| true`, so `saved to Vault for future runs` prints even when the write
     failed — observed directly: the first run printed it while `vault kv list secret` showed no
     `github/` at all (the write had built `http://localhost:/v1/...` because `_vault_local_port`
     was unset). A success message must not be unconditional.
  Operator action: supply a PAT with `read:packages` — see
  [[reference_packages_token_expiry_image_build]] — then overwrite `secret/github/pat`, force-sync
  the `ghcr-pull-secret` ExternalSecret and restart the four deployments.
- [ ] **`shopping-cart-data` StatefulSets never applied.** `ubuntu-k3s-data-layer` reports
  `phase=Failed`, `namespaces "shopping-cart-payment" not found (retried 5 times)`. ConfigMaps and
  Services synced; all StatefulSets are `OutOfSync` and absent, so the namespace has **zero** pods.
  `ubuntu-k3s-shopping-cart-namespace` only creates `shopping-cart-apps`, so nothing creates
  `shopping-cart-payment`. A failed sync also blocks self-heal
  ([[reference_argocd_error_phase_blocks_selfheal]]) — operator sync after the namespace exists.
- [ ] **`Frontend: HTTP 200` in `make status` is a FALSE GREEN for the hub.**
  `~/.local/share/k3d-manager/bin/frontend-browser-http.sh` port-forwards
  `--context "ubuntu-hostinger" svc/frontend`, so the check is served by the **hostinger** cluster,
  not the rebuilt hub. The hub's own frontend is in `ImagePullBackOff`. Do not read that green as
  hub health.
- [ ] **`make status` still reports 1 error — needs the operator, not code.**
  ArgoCD, Frontend and Prometheus now pass; all nine local endpoints answer (grafana 3001, argocd
  8080, prometheus 19190 + 19091, alertmanager 9093 → 401 by auth-proxy design and 19093 raw,
  keycloak 8880, frontend 127.0.0.2, vault 18200). The two remaining:
  1. **Keycloak connection refused** — the probe is `http://keycloak.shopping-cart.local/health/live`
     on **port 80**, which needs the `keycloak-browser-http` LaunchDaemon. That is a privileged
     system-domain job; teardown itself logged `no sudo in headless context — skipping`. Keycloak is
     healthy on 8880, so this is purely the privileged listener.
  2. Pushgateway's `!` warning is **pre-existing, not a regression** — `grep -i pushgateway`
     against `~/hub-rebuild-pods-before.txt` confirms it was not running before the rebuild either.
- [ ] **`cosign-public-key` ExternalSecret cannot sync** — `SecretSyncedError: could not get secret
  data from provider`, and it is what still makes ArgoCD `hub-platform-ops` **Degraded**. The key is
  not among the 14 backed-up canonical keys, so it was genuinely lost with the Vault PVC. It belongs
  to the v1.27.0 image signing work and needs a recovery path that is **not** `signing_init`
  (forbidden). `app-cluster-kubeconfig` **now syncs** — `hub_recovery_reconcile` seeds
  `platform-ops/app-cluster-hostinger` — as do `monitoring/grafana-admin-credentials` and all four
  `identity` secrets.
- [ ] **`observability/alertmanager` and `observability/prometheus` unseeded** — `make observability`
  warned `Alertmanager Vault secret not found — skipping SMS config`, `Failed to create Alertmanager
  login secret in Vault — using generated local credentials for this run`, and `Prometheus Vault
  credentials unreadable — skipping auth proxy`. The Prometheus auth proxy is therefore **not
  running**, which also means `K3DM_HERMES_STATUS_ENABLED=1` must stay unset. Run
  `make alertmanager-secret`.
- [ ] **`ServiceMonitor monitoring/kube-prometheus-stack-apiserver not found`** — the 45s apiserver
  scrape-timeout patch landed earlier this release had nothing to patch on a fresh cluster, so the
  `KubeAPIDown` flap guard is **not** in place. Re-run once the ServiceMonitor exists.
- [ ] **`cve-remediation-verify` CronJob fails every run: `secrets "cluster-ubuntu-hostinger" not
  found`.** The new hub ArgoCD has no registration Secret for the live `ubuntu-hostinger` cluster,
  so the CVE remediation verifier errors on every schedule. Re-register the hostinger cluster with
  the rebuilt hub — do **not** hand-patch the cluster Secret
  ([[reference_appset_generated_app_cleanup_ordering]] ordering applies). Until then this is a
  recurring red that is *expected*, which is exactly the kind of thing that later gets dismissed as
  noise — fix or pause it, do not learn to ignore it.
- [ ] **Hermes ArgoCD token needs re-minting** — the hub ArgoCD is new, so
  `k3dm-hermes-argocd-token` is stale by construction.
- [ ] **Hub rebuild runbook written; execution is the operator's.**
  `docs/howto/hub-rebuild-from-gitops-vault.md`. Verified during authoring: all **14** canonical KV
  keys are present in Keychain `k3d-manager-app-cluster-secrets`, so the rebuild does not lose
  secrets; `bin/cluster-down:330` runs `k3d cluster delete` (destroys the Vault PVC — the cached
  unseal shards are worthless without it, and `bin/cluster-up:417-432` re-unseals from cache);
  `bin/cluster-up` sequence is cluster → vault → ldap → argocd → bootstrap → shopping-cart-data,
  then `make up` adds observability + platform-ops. Vault lives at `secrets/vault-0`, currently
  `0/1`. `kubectl exec` and `logs` both fail with `net/http: TLS handshake timeout`, so no live KV
  dump is possible — Keychain is the source. Gated on the Stripe blocker above.
- [ ] **Grafana CF 502 is downstream of the kine stall — no independent fix.** Port-forward
  restarted 18,211 times, ~every 35 s, because the apiserver is unreachable. All 7 tunnel hosts
  flap. Grafana, cloudflared, Cloudflare and the supervisor probe are all exonerated. Clears only
  on the hub rebuild, which remains the operator's decision.
- [ ] **Tier 2 live-run blockers — spec filed `5edf557e`, fix NOT started.**
  `docs/bugs/2026-09-20-e2e-sandbox-job-service-names-markers-secrets.md`. Three defects in
  `_e2e_sandbox_job_manifest()` / `e2e_verify_sandbox()`: wrong service hostnames (3 of 4),
  missing `__E2E_RESULTS_BEGIN__`/`__E2E_RESULTS_END__` wrapper, and `ghcr-pull-secret` +
  `stripe-e2e` never created. 8 test cases specified, each needing a real=PASS / mutated=FAIL
  pair. Tier 1 is unaffected. Awaiting the user's call on who implements. Running Tier 2 live
  (`acg_restart` then `e2e_verify_sandbox`) stays the operator's action.
- [ ] **`e2e_remote.bats` dispatch tests depend on the repo's push state** — tests 23/28/52/53 fail
  with `HEAD <sha> is not pushed` on any locally-committed, unpushed HEAD, because
  `e2e_runner_dispatch`'s push guard fires before the tests' stubs are reached. Green in CI only
  because CI always tests a pushed ref. Found while verifying the rebase above; not filed as a bug
  yet and NOT in this branch's scope.
- [ ] **v1.35.0 PR → CI → Copilot → merge.** Remaining release steps that are NOT repo-local.
- [ ] **Reapply the ApplicationSets (hub AND ACG), then `argocd_check_values_branch`** — the
  operator's, live cluster. **Outstanding for v1.34.0's config as well as v1.35.0's**: the sets
  template `$values` at `${K3D_MANAGER_BRANCH}`, so config on a newer branch is inert in-cluster
  until they are reapplied. Two releases of config may currently be unread by any cluster.
- [ ] **Tier 2 → v1.36.0, deliberately deferred (decided 2026-09-18).** `e2e_verify_sandbox` does
  not exist; unimplemented since v1.25.0. Precondition before the spec: the **ACG login live gate**
  (Keychain `k3dm-acg-pluralsight`, or one manual sign-in in `pw-profile`) — the false-green fix is
  vendored but has never passed live, and Tier 2's Stripe acceptance would sit on top of it.
  **UPDATE 2026-09-22 — the "ACG login live gate" wording above is misleading and caused a
  multi-session misreading.** `e2e_verify_sandbox` now EXISTS (`scripts/plugins/e2e.sh:294`), and the
  headless auto-login is fully wired: `acg-credential-test:7-8` calls `_browser_launch`
  unconditionally, which calls `_cdp_ensure_acg_session` on both paths (`cdp.sh:132,163`), which
  reads `k3dm-acg-pluralsight` (`cdp.sh:184-185`). The gate fires on EVERY run. The only gap is that
  the Keychain item is **ABSENT** on this box, so the gate gets empty creds and fast-fails
  `ACG_LOGIN_NO_CREDS` → `ACG_SESSION_EXPIRED` to non-TTY callers. Spec queued:
  `docs/plans/v1.37.0-acg-autologin-enablement-for-tier2.md`. Blocking operator question: does the
  ACG account carry MFA (auto-login refuses MFA by design)? If no → populate the item once and P4
  closes permanently; if yes → permanently manual via `pw-profile`.
  Then: Tier 2 spec → implementation → HTTP/2 protocol label + failure-rate panel. Still blocked
  meanwhile: Stripe live E2E at 2/4, and `docs/issues/2026-09-16-http2-failure-rate-tier2-dependency.md`.
- [ ] **HTTP/2 failure-rate observability** — deferred until Tier 2 E2E coverage publishes bounded protocol/version labels. Current dashboard intentionally does not claim HTTP/2-specific failure rates; see `docs/issues/2026-09-16-http2-failure-rate-tier2-dependency.md`.
- [ ] **Hermes scheduled `make status` sensor + triage — IMPLEMENTED `e3e37f96`, live acceptance pending.** Spec `docs/plans/v1.34.0-hermes-scheduled-status-triage.md`. Runs `bin/cluster-status --json` on a ~40 min gate inside the existing 300s Hermes poll, classifies reds by check id, notifies on state change only, files bugs via the e2e worktree path. No new launchd agent, no new REPAIRS entry, no auto-execution (proposal + Slack approval only). Offline gates green (Hermes pytest 106, status-summary BATS 8/8). **The schedule defaults off**: set `K3DM_HERMES_STATUS_ENABLED=1` only after the Prometheus authenticated-probe dependency is verified, or the first run pages on a false red. Corrections and findings: `docs/issues/2026-09-16-hermes-status-triage-review.md`.
- [ ] **Hook fix PR (step 2 of 3)** — branch `fix/keycloak-reconcile-pipefail-ldap-federation`
  @ `a5838c19`, one commit ahead of the new main. Conflict pre-check (previously blocked
  by the auto-mode classifier) now RUN against merged main: `git merge-tree origin/main
  <branch>` → exit 0, merged tree `6678e606`, no conflict section = merges cleanly.
  Needs: own CHANGELOG entry (deferred to avoid colliding with #96's), Copilot review, CI.
- [ ] **lib-foundation: ACG session-check false-green — bug filed, Codex assigned.**
  Spec `docs/bugs/2026-09-12-acg-session-check-false-green-on-signed-out-page.md`
  (commit `ecfc15f`, pushed on `fix/acg-prism-monogram-selector`). Removes the two
  page-CONTENT selectors (`text=/Cloud Sandboxes/i`, `text=/Open Sandbox/i`) from
  `LOGGED_IN_SELECTORS`, adds `SIGNED_OUT_SELECTORS` + `pageLooksSignedOut` /
  `urlLooksSignedOut` as a negative gate, and makes `acg_session_check.js` say out loud
  when the `k3dm-acg-pluralsight` Keychain item is missing. Handed to Codex via
  `codex exec`. **IMPLEMENTED `308bb3c`** (Codex authored; Codex could not write `.git`,
  so Claude re-ran every gate and committed). Gates Claude ran, not taken on trust:
  `npm run check` clean, jest 25/25 across 7 suites, `make lint`, `make shellcheck-lib`,
  132 BATS — all green. CHANGE.md `[Unreleased]` entry added by Claude; still collides
  with lib-foundation #49, rebase whichever lands second.
  Files in scope: `pluralsight_login.js`, `acg_session_check.js`,
  `tests/providers/pluralsight_login.test.js`. Operator action still required before the
  live gate can pass: create Keychain item `k3dm-acg-pluralsight` (username+password) OR
  sign in once manually in `~/.local/share/k3d-manager/pw-profile`. MFA accounts can only
  use the manual path.
- [ ] **Portability Phase 3 inventory recorded** in
  `docs/bugs/2026-07-07-app-cluster-vault-portability.md` (24 `--context ubuntu-k3s`
  sites in `shopping_cart.sh`, 3 functions, resolver already present). Still needs the
  decision-#1 re-scope + swallowed-failure fix before a spec.
- [ ] **2026-09-14 — `/k3dm` Slack make-target command** — spec `docs/plans/v1.34.0-slack-k3dm-make-command.md` (`d8a2c8d8`); implemented + verified `cfbdddde`; webhook restarted; worker deploy pending user `make deploy-worker` (GH `CLOUDFLARE_API_TOKEN` secret missing → CI deploy fails); Slack app `/k3dm` registration pending user
- [ ] **v1.28.0-platform-zero-downtime-rollouts — QUEUED, hardware-gated** (deferred 2026-09-04).
  No CPU headroom on the M4 Air 24GB hub for 2+ replicas of the stateless tier (hub CPU-starves at
  single replicas). Gated on the Mac Mini M5 upgrade (Oct 2026). Spec stays on disk; do NOT implement
  until the hardware lands.
- [ ] Keep all new work within the five-plan milestone limit (at 5/5 — split before a 6th).
- [ ] **Hub control-plane saturation/public 502 incident (2026-09-02):** API `/readyz` reports
  etcd failures while k3s server reaches ~880% CPU; Grafana port-forward flaps and ArgoCD public
  OAuth URL drifted to the local hostname. Bug recorded in
  `docs/issues/2026-09-02-hub-control-plane-saturation-causing-public-502.md`; workload-level
  mitigation and durable URL/status fixes remain pending.
- [ ] **Argo identity drift + stale dashboard route (2026-09-02):** Git Keycloak Service renders
  valid ports but Argo strategic merge still produces duplicate `http`; Grafana dashboard links
  include a stale route. Bug: `docs/issues/2026-09-02-argocd-identity-drift-and-dashboard-502.md`.
- [ ] **E2E observability follow-up:** M2 result ConfigMaps publish correctly, but the live
  Prometheus deployment currently has no `e2e_run_info` series and the `Recent runs` Grafana
  panel shows duplicate exporter/application service columns plus blank legacy totals. Bugs:
  `docs/issues/2026-08-25-e2e-grafana-table-raw-labels.md` and the contract-mismatch issue above.
  Dashboard source fix `cfe925fc` is pushed; it uses `exported_service` as the canonical service
  filter, hides exporter `service`, and renames table fields. E2E client fix `0c2505b` is pushed
  on `shopping-cart-e2e-tests:feat/e2e-image-multiarch`; full repo `tsc` remains red only on
  pre-existing unrelated test strictness/type errors.
- [ ] **CVE remediation event panels empty (2026-08-24) — ROOT-CAUSED 2026-08-25.**
  NOT a durability bug (Codex RC wrong). Durable source (event ConfigMaps) exists; 0 series
  is correct because 0 events exist. Real RC: Keychain `platform-ops-app-rebuild/k3dm` absent
  → secret never synced → `app-cve-scan` pod wedged in `CreateContainerConfigError` → requester
  never runs. Fix = user stores scoped PAT + re-run `argocd_sync_app_rebuild_secret` + delete
  wedged job `cve-auto-1787541034`; then hardening (fail-loud + bounded backoff) + dashboard
  no-data annotation. Corrected diagnosis in `docs/issues/2026-08-24-cve-remediation-panels-empty.md`.
- [ ] **Image signing / CVE-loop closure** (`docs/plans/v1.27.0-image-signing-cve-loop-closure.md`)
  — cosign sign+attest, Kyverno Audit→Enforce, promoter verify gate. Multi-repo, heavy.
- [ ] **Frontend inline attest — spec WRITTEN 2026-08-31, Codex NOT dispatched.** `shopping-cart-frontend` inlines its
  own build/sign in `ci.yml` `publish` job (no reusable-workflow `uses:`) — signs but no attestation. Spec
  `docs/plans/v1.27.0-image-signing-frontend-inline-attest-codex-task.md`: insert 3 steps (trivy `cosign-vuln` +
  `spdx-json` predicates by digest → `cosign attest --type vuln`/`--type spdxjson`) after `Sign image by digest`, trivy
  pin reused `v0.36.0`, branch `feat/frontend-inline-attest`, exact msg `ci: attest frontend image (vuln + SBOM) inline by digest`.
- [ ] TWO-CLOUD (hostinger as 2nd registered cluster) NOT yet done — this run was k3s-aws only; hostinger node up but not registered into hub.

### From: 2026-09-20 — Port-forward wrapper fix pending commit
- [ ] Commit/push blocked by workspace Git permission: `fatal: Unable to create '/Users/cliang/src/gitrepo/personal/k3d-manager/.git/index.lock': Operation not permitted`. No commit SHA or PR URL exists yet; PR creation remains forbidden by the task.

### From: 2026-09-21 — GHCR PAT validated for auth, not for `read:packages`
- [ ] **Operator, out of scope for Codex** — mint a PAT with `read:packages`, overwrite
  `secret/github/pat`, force-sync `ghcr-pull-secret`, restart the four deployments. The gh CLI token
  can never work: its scopes are fixed by the OAuth app (`repo, read:org, gist, admin:public_key`).
- [ ] **Codex: fix `bin/rotate-ghcr-pat`** — hardcoded `ubuntu-k3s` context, auth-only PAT
  validation, PAT+Vault token in argv. Spec `796ba237`. Dispatched 2026-09-21 via `codex exec`.
  Awaiting SHA — verify before trusting.
- [ ] **Hub GHCR `ImagePullBackOff`** — OPEN, blocked. No GitHub credential on the operator's
  machine can pull from `ghcr.io` (403 Forbidden). Needs a PAT with `read:packages`.
- [ ] **`github-packages-token` cannot pull** — implies GitHub Actions image builds will 401.
  Independent of the hub outage; track separately.
- [ ] **Codex: forward `PROMOTER_SSH_KEY`** — spec `eb97355d`, dispatched 2026-09-21, branch
  `fix/pass-promoter-ssh-key` in payment / product-catalog / frontend / infra. Awaiting 4 SHAs.
- [ ] **OPERATOR: create `PROMOTER_SSH_KEY` secret** in `shopping-cart-product-catalog` and
  `shopping-cart-frontend` (both lack it entirely; reuse the key already in basket/order/payment).
- [ ] **Codex: forward `PROMOTER_SSH_KEY`** — RE-DISPATCHED with corrected scope, spec `6fa1ceab`.
  Only `shopping-cart-product-catalog` + `shopping-cart-infra`. Awaiting 2 SHAs.
- [ ] **OPERATOR: create `PROMOTER_SSH_KEY` secret** in `shopping-cart-product-catalog` only
  (it has none; reuse the key already in basket/order/payment).
- [ ] **UNFILED follow-up:** basket run `33507015429` promotion failed with
  `failed to push some refs` — push rejection, key was present. File if it recurs.
- [ ] **Stray branches** `fix/pass-promoter-ssh-key` exist in payment and frontend from the first
  dispatch, with no commits. Deletion NOT approved — left in place.
- [ ] **Dispatch the refetch-loop fix to Codex** — BLOCKED until `fix/pass-promoter-ssh-key` merges
      in shopping-cart-infra (same file).
- [ ] **Rotate two exposed credentials** - Grafana (pasted by the user into the session) and Keycloak
      admin (leaked past my redaction filter). Both need rotation.
- [ ] **`show-service-passwords` Keycloak line defeats redaction** - prints `admin user: admin / <pw>`
      instead of the `password: <pw>` convention every other service uses, so filtering by convention
      misses it. Also the 3 Keycloak dev users print `N/A`. Unfiled.
- [ ] **ROTATE two exposed credentials** - Grafana (pasted into the session) and Keycloak admin
  (leaked past my redaction filter). Still outstanding.
- [ ] **`secret/keycloak/users/*` unseeded on the hub** - expected state, now reported honestly.
  Seeding it would require either running `bin/cluster-up`'s SSO step or adding the path to the
  14-key allowlist; the latter is NOT approved. No action taken.
- [ ] **Jev / TypeSafe AI - do not integrate now.** Recommendation is a deterministic e2e verdict
  taxonomy + repo routing table + back-labelled corpus from the 28 existing e2e/Hermes bug docs,
  which doubles as the offline eval set. Spec NOT written - needs the user's go.
  (`docs/plans/` for v1.36.0 currently holds 1 of the 5-doc cap.)
- [ ] **No PRs opened** for `ef3d4b8d`/`f9d956ae`/`6c744a23`/`41855a2d` (k3d-manager) or
  `e99960e` (shopping-cart-infra). PR creation still needs the user's explicit go.
- [ ] **Keycloak admin rotation** — still outstanding; no rotator exists and the ESO secret is bootstrap-only, so Vault+restart alone will not change the live password. Needs a 3-step manual or a new `keycloak-credential-rotator` spec. Operator to choose.
- [ ] **Fix `base64 --decode` in platform-ops rotators** — BusyBox in `alpine/k8s:1.31.4` only
  accepts `-d`. keycloak lines 98/113 and argocd line 139 silently disable ALL Slack
  notifications (including rollback-failure alerts); argocd line 117 has no `|| true` and looks
  like it aborts the job outright. grafana already uses `-d`. Needs a bug doc + a test banning
  `--decode` in `scripts/etc/argocd/platform-ops/`.
- [ ] **`keycloak-realm-reconcile` fails with `awk: command not found`** — exit 127, 2026-09-21,
  `quay.io/keycloak/keycloak:24.0`. Realm `shopping-cart` created but auth flows never
  configured. Pre-existing, unrelated to the rotation. Needs a bug doc.

### From: 2026-09-22 — Prometheus reseed and rotator CI fix
- [ ] **`keycloak-realm-reconcile` awk exit 127** — still needs its own bug doc.
- [ ] **Alertmanager root route is default-deny — all warning alerts discarded** (spec filed
  2026-09-23, assigned to Codex). Root cause of the 15 silent `cve-remediation-verify`
  failures. `route.receiver: 'null'` at `alertmanager.yaml.tmpl:9`; only `severity = critical`
  or the 5-name allowlist escape it. Also silences this repo's own `E2EVerificationFailing`
  and the `keycloak-realm-reconcile` awk-127 job. Spec:
  `docs/bugs/2026-09-23-alertmanager-null-root-route-silently-drops-warning-alerts.md`.
- [ ] **Probe has no test of its own** — `test_alert_delivery.py` stubs `run`, so
  `bin/k3dm-alert-delivery-status` is never executed by any suite. That is how the gzip-key defect
  shipped green. A parse-level test over a fixture generated Secret would close it.
- [ ] **istio-cni DaemonSet — precondition done, awaiting the user's go for the AppSet reapply.**
  `istio-cni-node-vgr6m` is 0/1 since 2026-09-06, `install-cni` readiness 503, **160,074 probe
  failures over 17d**, 0 restarts (no probe ever passed). The live `istio-ambient` AppSet still
  holds the generic `cniConfDir: /etc/cni/net.d` / `cniBinDir: /opt/cni/bin`; the correct k3s values
  are `/var/lib/rancher/k3s/agent/etc/cni/net.d` and `/var/lib/rancher/k3s/data/cni`
  (`_istio_ambient_cni_dirs k3s-hostinger` confirms). **`02e3fa76` fixes the overwrite mechanism but
  is inert until the AppSet is reapplied** — the stale generic dirs are still live. Ambient is in
  real use, not cosmetic: `ztunnel-69cft` is 1/1 and namespace `shopping-cart-apps` carries
  `istio.io/dataplane-mode: ambient`, so redirection setup for new pods there is degraded.
  Next action, needs the user's go: reapply the `istio-ambient` ApplicationSet, confirm it writes
  the k3s dirs (the new guard should refuse the generic ones), then roll the DaemonSet.
- [ ] **AWAITING THE USER'S GO — reapply the `istio-ambient` ApplicationSet.** All preconditions now
  hold. Expected: `cniConfDir: /var/lib/rancher/k3s/agent/etc/cni/net.d`,
  `cniBinDir: /var/lib/rancher/k3s/data/cni`, and the new guard silent (provider is specific).
  Then roll `istio-cni-node` and confirm 1/1 plus `KubeDaemonSetRolloutStuck` clearing.

### From: 2026-09-24 — webhook Phase 4 lifecycle/status extraction (working tree; commit pending)
- [ ] Commit/push blocked by `.git/index.lock: Operation not permitted` after one commit attempt;
      no retry, lock removal, hook bypass, force-push, or PR. All scoped changes remain staged;
      no Phase 4 SHA exists.

### From: 2026-09-24 — lib-foundation v0.4.18 credential-test observability
- [ ] **Operator action:** dismiss CodeQL alerts 23/24/26/27 via `gh api` — the classifier
  denied it as a CI bypass; must be run from the operator's terminal. Blocks the #131 CodeQL
  gate; `enforce_admins` untouched until then.
- [ ] Follow-up (deliberately out of scope): dedup the two `_robustClick` copies —
      `sandbox.js` swallows errors, `acg_restart.js` does not, so unifying them changes the
      live sandbox path and needs a sandbox to verify.
- [ ] **Unalerted public-path failure:** `make status CLUSTER_PROVIDER=k3s-hostinger` reports
      Frontend 404 while all four `shopping-cart-apps` pods are Running 1/1, so `ServiceDown`
      (`kube_pod_status_ready ... == 0`) is correctly silent. Nothing probes the public hostnames —
      there is **no blackbox exporter anywhere in the repo** and nothing writes smoke/status results
      to Pushgateway, so no rule can fire and no SMS can be sent. Delivery is fine
      (`severity = critical` → `sms-critical`). Second silent failure from this same gap; the
      blackbox-probe + `CloudflareTunnelDown` follow-up is now load-bearing.

### From: v1.39.0 test-suite metrics — 2026-09-27 implementation status
- [ ] No commit/push SHA: the environment denies writes to `.git` (`FETCH_HEAD` and `index.lock`).
      Resume by retrying the required pull, commit (including the observed marker fact), push, and
      remote SHA verification from a checkout with writable Git metadata.

### From: v1.39.0 test-suite metrics — DONE 2026-09-27, commit `205405c0`
- [ ] OPERATOR-OWNED, deliberately not done: the first live `make test-metrics` push, and
      confirming the `k3dm-tests` dashboard loads in the ACG Grafana. No live Pushgateway, cluster
      or host action was taken by any agent.

### From: v1.39.0 public endpoint blackbox probes — 2026-09-27, pushed `ba2a01e1`
- [ ] **Live verification pending operator action:** deploy the chart/Probe resources via ArgoCD;
  query `count(probe_success)` and all seven `probe_http_status_code` series; prove the frontend
  404 yields `probe_success 0`; reapply hub and ACG ApplicationSets; run
  `argocd_check_values_branch`. The local remote-tracking ref could not be updated by the sandbox,
  but `git ls-remote` reports the pushed SHA above.

### From: v1.39.0 test-suite metrics — live push CONFIRMED 2026-09-27
- [ ] **Duration metrics are dead** — `k3dm_test_run_duration_seconds` is a hardcoded 0 and
      `bats`/`pytest` suite durations are 0 (the parser expects a `# duration:` marker that no
      harness emits). Needs Makefile timing + `--duration` + a pytest `in <n>s` parse. DECISION
      PENDING: fix in v1.39.0 or file as a bug doc for v1.40.0.
- [ ] Operator-owned: apply the `k3dm-tests` dashboard (`make observability-acg`) and confirm it
      loads in the ACG Grafana. The ConfigMap is still absent on both clusters, so the metrics
      that just landed have nothing reading them yet.

### From: v1.39.0 blackbox probes — Codex landed ba2a01e1 2026-09-27
- [ ] Operator-owned live DoD: ArgoCD deploy, seven `probe_success` series, seven status codes,
      prove the frontend returns `probe_success 0` / 404, ApplicationSet reapply,
      `argocd_check_values_branch`.

### From: 2026-09-27 — launchd PATH omission fixed
- [ ] **Upstream lib-foundation change: add `{{HOME}}` substitution to `_install_hermes_agent`** so
      the hermes template can carry the fix like its siblings. Not started; needs the lib-foundation
      repo and its own PR.

### From: 2026-10-01 — v1.42.0 daily verification plan
- [ ] Implementation not started; Tier 2 ACG/Stripe remains opt-in and outside this plan.

### From: 2026-10-01 — k3d-manager Dot roadmap
- [ ] Implementation is not started; this remains a roadmap/specification item.

### From: 2026-10-01 — v1.40.0 review fixes complete
- [x] 2026-10-03 payment PRs #80 (19c42aa) + #82 (e3b6f06) MERGED. [ ] Trivy 0 CRITICAL on sha-e3b6f06, re-pin hostinger + e2e.
- [x] 2026-10-03 payment sha-e3b6f06 Trivy 0 vulns; re-pinned hostinger digest + e2e tag b7604afe. [ ] payment repo k8s/base stuck at sha-19c42aa (CI commit-back rebase conflict). [ ] hostinger payment VulnerabilityReport 0 CRITICAL.
- [ ] 2026-10-03 payment k8s/base stuck at sha-19c42aa: promote rebase bug (2026-09-21 doc) unimplemented; re-run fails deterministically. Spec needs is-ancestor guard + refresh; then bump caller pins.
- [x] 2026-10-02 promote-loop fix spec refreshed + dispatched to Codex (infra fix/promote-refetch-never-backwards). [x] e1ef171c verified (harness 5/5, guard mutation red). [x] infra PR #107 MERGED 98b10f05 (enforce_admins restored). [ ] hostinger trivy: no reports for payment/order/catalog (uninvestigated). [x] Part B pin bumps verified: payment 741ffdc, basket 01904e2, order af3f105, product-catalog d3ac722. [ ] PRs: payment #83 OPENED 2026-10-03 (+CHANGELOG a8add76; Copilot 1 finding = CHANGELOG entry outside Fixed list, fixed 171d8e4, thread resolved, issue doc 79ff70d; CI GREEN on 79ff70d, mergeable clean; ruleset-protected main, no enforce_admins lever) MERGED 2026-10-03 e93d32c by operator; main CI 37088705440 SUCCESS = first live promote-loop run: pushed e93d32c..4e79be2 on attempt 1, k8s/base newTag sha-e93d32c (stale sha-19c42aa repaired). basket #50, order #80, product-catalog #57 OPENED 2026-10-03 (CHANGELOG entry each; Copilot requested; CI pending). basket/order/catalog HELD: open dependabot PRs basket #49, order #79, catalog #56 bump the same line to older infra SHAs (64c11783/e41f2adb) -> CLOSED as superseded 2026-10-03 (user go). Remaining: open those 3 PRs after payment's first main promote run is confirmed. [ ] confirm payment main promote repairs k8s/base. CI 2026-10-03: basket #50 green/CLEAN, order #80 green/BLOCKED (review), product-catalog #57 RED — pre-existing: SQLAlchemy 2.1.3 defaults bare postgresql:// to psycopg3 (not installed; Dependabot #56 same on 09-28). Bug docs/bugs/2026-10-03-product-catalog-sqlalchemy-2-1-defaults-postgresql-url-to-psycopg3.md dispatched to Codex on catalog branch fix/sqlalchemy-explicit-psycopg2-driver (postgresql+psycopg2:// + tests/unit/test_config.py); after merge, update-branch #57. Codex 9c92929 verified (2.1.3, 110 passed, ruff clean) + Claude dbe05c5 (CHANGELOG moved inside Fixed list — Codex repeated the payment placement error); catalog PR #58 OPENED, Copilot requested; #58 CI ALL GREEN; #58 MERGED 666b832 (2026-10-03); #57 merged main in 41e7e1c (CHANGELOG conflict, kept both entries), #57 CI GREEN + CLEAN. main run 37090500718 (old pin) published + promoted newTag sha-666b832 — first catalog image since 09-22. Copilot: 0 reviews on #50/#80/#57. 2026-10-03: basket #50 MERGED f84411f (Go CI main run 37091213040 SUCCESS: new loop pushed f84411f..3194768, newTag sha-f84411f — basket proven); #57 BEHIND after promote commit → update-branch, CI GREEN + CLEAN again, awaiting merge; order #80 merge REFUSED (ruleset 20606891: 1 approval, no admin bypass); classifier denied Claude ruleset edit, operator ran 0→merge→1: #80 MERGED 86f79e4, ruleset verified back to approvals=1 / DeployKey bypass / same 4 rules. Catalog #57 MERGED 2d3d687 (operator, --admin); ALL FOUR PROVEN on the new loop: order run 37120665295 pushed 86f79e4..6386ed1 newTag sha-86f79e4; catalog run 37120828300 pushed 2d3d687..b050ba1 newTag sha-2d3d687. Promote-loop rollout DONE.
- [ ] 2026-10-03 v1.41.0 features dispatched to Codex ONE AT A TIME, Claude verifies each before the next: (1) find-similar-docs-links — DONE `a4996800` (Claude verified: on origin, 4 scope files, 11+1s / make test-pytest 590+1s, doc-links OK, independent mutation forcing "main" fails the URL test); (2) cloud-bridge round-trip latency bug — `6fc0bc47` pushed (Codex gates: 82 / 599+1s / doc-links OK / 2 mutations); Claude review found a regression (MAX_PER_TICK cap returns own pushed commit as last_tip → requests 11+ stall); follow-up DONE `819e636a` (Claude verified: on origin, 2 files, 68 bridge tests, independent revert-to-break mutation fails the new test); operator restarted 2026-10-03 06:18; live: bridge gap 14 s / 9 s, client round trip ~20 s (was up to ~90 s); Codex cloud session (codex@github) also used it 06:23 — diagnose-apps 7 s, job-status 8 s bridge-side (hand-committed requests, not the helper); old Sep 29 publickey lines still the log tail — log untouched since `docs/bugs/2026-10-03-cloud-bridge-round-trip-latency.md` (adaptive 5s tick, no re-fetch, 5s client poll; operator then `make restart-cloud-bridge`); (3) webhook-log-levels-and-retention — `3f7cf103` M1 / `73d0ef56` M2 / `dc5211de` M3 / `f1d0ec5d` M4 (Claude verified: test-pytest 605+1s, test-python-unit 7 suites OK, cleanup BATS 12/12, shellcheck clean, 0 print(), independent mutation removing ALL redaction fails the token test); review finding: M2 hollowed `test_make_target_passes_timeout_to_transport` (no assertion) → follow-up DONE `cd20fc1b` (Claude verified: on origin, 1 file, test-python-unit 7 suites OK, independent mutation dropping killpg fails the test at 30 s vs <5 s); item 3 COMPLETE — operator to run `make restart-webhook` (restarts bridge too); docs sweep of all v1.41.0 features after the queue (operator ask 2026-10-03); (4) cloud-bridge-e2e-dispatch — split into two runs: part A M1–M6 DONE `a324b6cd` (Claude verified: on origin, 14 files, 100 bridge/capability tests, test-python-unit 7 OK, e2e_remote BATS 81/81, shellcheck clean; independent mutations: capability check→True fails 2 pytest + 3 unittest, dropping lock holder from refusal fails BATS 24; nits: blank line splits the trailers, `removeprefix("make:")` would grant a future non-make route named e2e → fixed in part B; architecture doc lacks cloud-runner token → part B); part B M7–M8 + hardening DONE `c2667b6d` (Claude verified: 8 files, bridge 80 passed, policy unittest OK, independent mutation running slow actions inline fails 1; review: job state `killed` (cluster kill route) is missing from TERMINAL_JOB_STATES → a killed job is watched until timeout+10 min then 'watch expired' — folded into the sandbox spec); item 4 COMPLETE — operator `make restart-webhook` now; operator ask 2026-10-03: let the cloud agent bring the ACG sandbox up/down (not the primary cluster) → spec `docs/plans/v1.41.0-cloud-bridge-sandbox-lifecycle.md` (5th v1.41.0 plan = cap) — DISPATCHED 2026-10-03 (codex-sandbox-lifecycle.log); operator rationale: 4h+ sandbox lets an agent debug without touching live Hostinger; single `make restart-webhook` after it is verified, then operator does the ACG sandbox login (Chrome CDP) so `sandbox-up` can run; operator provisioned Keychain `k3dm-webhook-token-cloud-runner` (account k3dm) 2026-10-03; operator restart-webhook deferred until B verified (shared worktree) (now M1–M8: + M7 slow actions off the serial loop, M8 bridge follows its own jobs → `.final.json` / `--wait-final`); (5) python-agent-rigor (brief A lib-foundation, then B k3d-manager). Sandbox lifecycle DONE `9d527cec` (Claude verified: on origin, 8 files = spec, 83 bridge tests, test-python-unit 7 OK; independent mutation granting any provider fails 8 hostinger/empty/AWS/gcp subtests, cmp-restored). Codex's run wiped Claude's uncommitted memory-bank edits (re-added) — commit memory-bank before a dispatch, never leave it dirty in the shared worktree. NEXT: operator `make restart-webhook`, then a live `sandbox-up` smoke — operator plan 2026-10-03: after the operator's own run completes, the operator asks a cloud agent to run `bin/k3dm-cloud-request --wait-final sandbox-up` (first live use of the cloud-runner lifecycle path); Claude then checks the bridge request/response/.final.json commits and the webhook job. Operator's own `make up CLUSTER_PROVIDER=k3s-aws` 2026-10-03 FAILED: data-layer Application never Synced — hub ArgoCD cannot resolve `host.k3d.internal` (NodeHosts has only the 4 nodes, last written by k3s-supervisor 2026-09-27 hub rebuild). Root cause: `_acg_repair_hub_host_alias` (bin/cluster-up:170) resolves the host IP with `getent`, which rancher/k3s:v1.32.0-k3s1 lacks → empty → WARN + skip, so the repair has been a silent no-op since the rebuild. OrbStack: `nslookup host.docker.internal` in the server container = 0.250.250.254. CloudFormation stack k3d-manager-cluster (us-west-2) left running (billable). Sudo prompt during the run = ArgoCD browser HTTPS LaunchDaemon reinstall (wrapper changed); headless runs skip it. No manual ACG login step: operator confirmed 2026-10-03 that `make up` logs in unattended (Keychain `k3dm-acg-pluralsight` auto-login runs before the TTY gate, acg_session_check.js:91-99); how-to corrected.
- [ ] 2026-10-03 QUEUED (operator decision) — cloud-agent sandbox debugging, two separate releases: (1) v1.43.0 (v1.42.0 is already reserved to its 5-plan cap by the Hermes alert-triage scope §5): sandbox-only (`provider=aws`) read-only diagnostics — namespace events, get/describe deploy/svc/ingress/node, logs `previous` + `container` (webhook supports container/tail_lines; the bridge does not pass them); also verify the ACG ApplicationSet values ref tracks the branch a cloud agent pushes to (git push → ArgoCD sync is the agent's only write path). Operator follow-up: "possible to delegate to hermes for investigation and report info (cloud agent <-> hermes)" — Claude proposed building (1) as a Hermes on-demand investigation: bridge action `hermes-investigate` (structured args only, no free text reaching Hermes' LLM) → Hermes runs a fixed read-only evidence bundle on the sandbox context, reusing the v1.42.0 `alert_recipes` engine, + prior art → one report back as a bridge artifact. (2) a LATER release, deep investigation first: a sandbox-bound mutating step (e.g. rollout restart) — natural home is a Hermes Phase-2 allowlisted repair with Slack approval. Awaiting operator's pick on the Hermes route.
- [ ] **Hub DR one-command target** (operator 2026-10-03: "we should have a better make <target> to execute hub recovery") — spec `docs/bugs/2026-10-03-hub-restore-has-no-single-make-target.md`: `bin/hub-restore` (TTY + Keychain + context + root-owned-dir preflight, 8 keep-going steps, summary), tunnel agent extracted to `scripts/lib/cloudflare_tunnel.sh`, `make hub-restore` / `make hub-recover`, alertmanager-secret backs up gmail_app_pw, restore-google-app-password tells empty vs denied apart. Codex DISPATCHED 2026-10-03. Live: operator's `restore-google-app-password` in Terminal.app said not in Keychain although the item is present → empty value or denied ACL; operator checking length.
- [ ] **Hub identity + public origins are sandbox-path only** (found 2026-10-03 12:45). Operator ran signing-restore (RESTORED from Keychain — key not lost), reconcile and platform-ops (OK; webhook-token, app-rebuild and git-writer Secrets synced) in Terminal.app. Reconcile stopped at the identity hook: no `shopping-cart-identity` Application on the hub (only cluster-up Step 10c creates it). Claude applied it by hand; it is blocked on Vault keycloak/admin, keycloak/clients, keycloak/smoke-user and ldap/admin (404, seeded only by deploy_shopping_cart_data). PublicEndpointDown SMS for argocd/keycloak/frontend (local PF agents + sandbox frontend missing) → Claude added 6 h silence `84a19233`. Fix: the next sandbox `make up` restores all of it; durable fix in the follow-up section of the hub-restore spec. After that make up, rerun `hub_recovery_reconcile` (smoke user, ArgoCD admin mirror, cloudflared config steps did not run) and expire the silence.
- [ ] **Proposal v1.43.0: off-laptop outage watcher** (operator 2026-10-03: use Hermes to coordinate jobs during a local network outage) — first confirm where Hermes runs; it only helps if it is off the Mac (heartbeat page, queue held until reconnect, sweep stuck pods/jobs afterward).
- [ ] **HUB DELETED 2026-10-03 ~08:35** — Claude gave `make down CLUSTER_PROVIDER=k3s-aws` without `KEEP_LOCAL=1`; `bin/cluster-down` defaults `_keep_hub=0` → `k3d cluster delete k3d-cluster`. No k3d containers/volumes remain; context gone; all hub dashboards error. Fix spec `docs/bugs/2026-10-03-make-down-deletes-hub-by-default.md` (default keep hub, `DELETE_HUB=1`/`--delete-hub` to delete; `k3d` provider implies delete). Dispatch order: host-alias (running) → make-down default → hang → SMS routing. Hub rebuild = operator, hub-only sequence + Vault reseed from Keychain (app-cluster-kubeconfig, cosign-public-key not backed up).
- [ ] **Hub recovery progress (Claude, 2026-10-03 09:00–09:15)** — done: Vault PF reinstalled (health 200); `make platform-ops` OK; AppSets reapplied 13/13 pinned to v1.41.0; hub self-registration + Hostinger re-registered (ArgoCD + Vault auth mount); all 30 apps Synced; hub pushgateway :19094 OK. `hub_recovery_reconcile` stopped at step 5 (signing — Keychain unreadable from Claude session). BLOCKED on operator: (1) `sudo chown -R cliang:staff ~/.local/share/k3d-manager/logs` (root-owned since 07:34 → grafana-port-forward exits 78); (2) `make alertmanager-secret` + `make observability` from operator terminal (Keychain); (3) `make signing-restore` then `./scripts/k3d-manager hub_recovery_reconcile --confirm`; (4) `make platform-ops` rerun for Keychain-synced secrets (webhook token); (5) Cloudflare tunnel agent missing → public hosts 530; ArgoCD PF + browser LaunchDaemons missing (restored by next sandbox make up / cluster-up). NO snapshot existed (M2 `k3dm-snapshots` absent, `~/k3dm-backups` empty).
- [ ] **Hub-loss DR (real, 2026-10-03)** — operator: "a good lesson and a disaster recovery". Capture per-step timings (measured RTO) + lost-for-good list (RPO) during the manual rebuild; after recovery write `docs/issues/2026-10-03-hub-deleted-by-sandbox-teardown.md` (timeline, cause, restored-from-Keychain/git, lost, timings). Follow-ups: scheduled off-hub Vault snapshot (proposed v1.43.0); maybe `make hub-restore` for post-rebuild restores (decide after counting today's manual steps). No snapshot exists today — recovery is per-item from Keychain (`k3d-manager-app-cluster-secrets`, signing, alertmanager, cloudflared) + git.
- [ ] **Bug: root-owned state logs dir kills grafana-port-forward** — `docs/bugs/2026-10-03-root-owned-state-logs-dir-kills-grafana-port-forward.md` (OPEN, hypothesis: root LaunchDaemons recreated the dir after cluster-down removed it). Operator workaround: `sudo chown -R cliang:staff ~/.local/share/k3d-manager/logs` + kickstart.
- [ ] **2026-10-03 sandbox `make up` FAILED at Step 10c (Keycloak never created)** — root cause: `bin/cluster-up` identity Application heredoc sets `Replace=true`; ArgoCD replaces the bound `postgres-keycloak-pvc` (immutable) and the sync fails; infra per-PVC `Replace=false` (`00d0d8a`) is present live and IGNORED. Fix F1 (ServerSideApply=true + ServerSideDiff=true) appended to `docs/bugs/2026-09-23-argocd-identity-replace-true-cannot-update-bound-pvc.md`, dispatched to Codex. Operator rollout: patch live app + start sync, then re-run make up. CFN stack `k3d-manager-cluster` (us-west-2) left running by the failed run.
- [ ] **hub_recovery_reconcile run 2026-10-03 13:44** — identity Synced/Healthy, KC 1/1, but public Keycloak 502: wrapper pins REMOTE_PORT 8080, infra svc exposes http:80 → recurrence + named-port spec appended to `docs/bugs/2026-08-22-keycloak-port-forward-wrong-remote-port.md` (Codex queue). Smoke seed skipped (public mint curl 56). Vault root token Keychain write failed silently (-25308, non-GUI) — same doc. Operator: stopgap wrapper edit + kickstart, rerun reconcile foreground in Terminal.app. My wrapper sed was classifier-DENIED (Irreversible Local Destruction) — don't retry.
- [ ] **Reconcile rerun (operator, foreground)** — Keycloak PF stopgap verified: :8880 + public 200; smoke client created; identity Synced/Healthy; ESO SecretSynced. public-endpoint-probe: all OK except frontend 502 — origin 127.0.0.2:80 has no listener because the frontend/keycloak browser-http LaunchDaemons were skipped by headless make up (none in /Library/LaunchDaemons). Fix: operator `make refresh CLUSTER_PROVIDER=k3s-aws` in Terminal.app. Keychain root-token write -25308 even foreground → operator `security show-keychain-info`.
- [ ] **make refresh did not install LaunchDaemons** — `_system_daemon_install_if_missing` uses --prefer-sudo (sudo -n only) → silent soft fail; filed `docs/bugs/2026-10-03-refresh-system-daemon-install-never-prompts-for-sudo.md` (Codex queue). Workaround: `sudo -v && make refresh CLUSTER_PROVIDER=k3s-aws`. Keychain -25308 root cause = login keychain LOCKED (show-keychain-info failed until unlock-keychain); operator unlocked → rerun reconcile to sync Vault root token.
- [ ] **v1.43.0 PLAN: weekly hub DR drill** — `docs/plans/v1.43.0-hub-dr-drill.md` (operator 2026-10-03: planned DR, restore data quickly, not image snapshots). Operator decisions 2026-10-03: (1) Vault unseal shards durable in Keychain `k3dm-vault-unseal-dr` (M4+M2), generate-root short-lived token, no state.db in backups; (2) pre-bind PVCs with selected-node + node-match hard stop; (3) data = age-encrypted critical claims (~100MB) in private repo `wilddog64/k3dm-hub-data`, M4 has public key only, bounded history; (4) drill runs on M2 with its own kubeconfig; (5) PrometheusRules in git + GitHub scheduled freshness workflow in the data repo; (6) drill hub on M2, not a 2nd hub on M4. Also DELETE_HUB=1 refuses without an export <24h. Live checks L1–L6 before dispatch; likely split into 2 Codex dispatches (export/restore, then drill). Supersedes the scheduled-snapshot proposal below. 1 of 5 for v1.43.0.
- [ ] **DR gap: no snapshot before destructive teardown** — `make snapshot` exists (M2 store) but is manual and was never run; nothing captured before the 08:35 hub deletion. Propose v1.43.0: scheduled snapshot + `make down DELETE_HUB=1` refuses without a verified snapshot < N h old.
- [ ] **Hub VectorDB empty after rebuild** — the Hermes index tick fails every run because the Vault copy `secret/embeddings/gemini` was lost with the hub; launchd can't use the keychain. The operator reseeds it via `docs/guides/vector-store.md` (Terminal.app), then runs `make index-docs`. Durable fix = hub-restore follow-up F2.
- [ ] **index-docs stalled at 700/1802 (2026-10-03 14:08)** — sleeping on an uncapped server `retryDelay` (likely per-day quota). Bug filed: `docs/bugs/2026-10-03-index-docs-sleeps-on-uncapped-server-retry-delay.md`; Codex queue. Operator to Ctrl-C and re-run later (resumes).
- [ ] **index-docs re-run** — operator runs `make index-docs` morning of 2026-10-04 (after midnight-PT quota reset); 700/1802 committed, ~1102 remaining.
- [ ] **Codex chain dispatched 2026-10-03 14:20** (`codex exec`, sequential): f3 Keycloak named port + Keychain write verify; f4 refresh `--interactive-sudo`; f5 index-docs retry-delay cap. Logs `scratchpad/codex-f{3,4,5}.log`. Claude verifies each SHA on origin. Not yet specced for Codex: preseed ESO force-sync, hub-restore embeddings key.
- [ ] **Bug: cluster-up Keycloak LDAP component lookup picks a mapper** (2026-10-03, Claude) — `docs/bugs/2026-10-03-cluster-up-keycloak-ldap-component-lookup-picks-a-mapper.md`. Explains all 3 `make up` SSO WARNs: `grep -B1 'ldap'` returns the "full name" mapper id (10d.6 update/sync fail; 10d.7 created stray group-mapper `9233ebab` under that mapper → NPE `ldapProvider is null`); frontendUrl sent top-level instead of `attributes.frontendUrl` (also fired 2026-07-07). Live SSO is OK (real provider `a5a37610` syncs 5 users; issuer public via `_keycloak_smoke_ensure_realm`). Spec F1–F4 for Codex; fix also deletes the stray mapper on the next `make up`.
- [ ] **Root-owned logs bug updated** — confirmed `argocd.sh:83` defaults the ROOT ArgoCD browser daemon log into the shared top-level `logs/` (cluster-up's per-provider fallback is dead); 744-mode creator still unconfirmed.
- [ ] **ssh-tunnel down after k3s restart** — orphaned sandbox sshd (PID 51046) holds `-R 8200`; autossh `ExitOnForwardFailure` loops; ArgoCD loses ubuntu-k3s. Bug `docs/bugs/2026-10-04-ssh-tunnel-autossh-reconnect-blocked-by-orphaned-remote-8200.md`. [x] operator kill+kickstart (tunnel back 02:46Z) [x] sync — ArgoCD auto-sync Succeeded, Synced/Healthy, Prometheus 2/2 Running, svc prometheus-operated present [x] operator restarted Step 14b PF (PID 93911, 19190); hub federate-acg up=1 at ~02:55Z (14c pushgateway agent already up on 9091) [ ] decide fix on sandbox if sandbox metrics wanted. Orphan `bin/cluster-up` PID 1927 + child 85324 killed by operator.
- [x] **Codex: three sandbox-recovery fixes** (dispatched 2026-10-04) — DONE `f61d3b3b` (cleanup PID ownership) / `3b789adf` (CRD condition + discovery warn + 14b svc guard) / `d49e5eb8` (Vault reverse forward as own agent + remote fuser). Claude verified: all on origin, scope = spec, no new shellcheck warnings, 61/61 targeted BATS, independent mutation (drop ownership check) fails test 28, cmp-restored. Review: R1 Step 14b warn expands `$!` to this run's PID (paste writes the Vault PF PID into acg-prom-pf.pid); R2/R3 Codex split `"su""do"` to slip past the pre-commit bare-sudo audit (observability warn text + tunnel wrapper remote `sudo fuser`). R1+R2 specced in the CRD bug doc; R3 needs operator decision (sandbox 8200 listener is held by non-dumpable sshd, so remote fuser needs root). [x] follow-up R1/R2 `98835aac` (Codex edits, Claude committed; 8/8 crd-discovery BATS + lint; R1 mutation red; `\$!` renders literally) [x] R3 decision: audit exemption upstream — lib-foundation `5c9b631` on `fix/agent-audit-remote-sudo-marker` [x] lib-foundation PR #57 MERGED `44e7e8d` 2026-10-04 (no tag: fix branch, [Unreleased]) [x] subtree pull `ce1164eb` (tree-equal to 44e7e8d) [x] operator: retire the stale local fork `scripts/lib/agent_rigor.sh` → shim to the subtree copy (trial: 9/9 local BATS pass) — spec `docs/bugs/2026-10-04-pre-commit-hook-loads-stale-local-agent-rigor-fork.md` (C1 shim, C2 tunnel marked sudo) [x] Codex [x] verify — `e22b7df6` + `0670b075` (23/23 BATS, fork-restore mutation red, hook accepted marked sudo) [x] make test 5133de03: 1345/1345 BATS, pytest 621 passed 1 skipped [x] make test 709aba8d: 1336/1341, 5 test-only reds [ ] live verify next `make up` + `tunnel_start` migration
- [ ] **Hermes app_health never enabled** — spec `docs/bugs/2026-10-04-hermes-app-health-sensor-never-enabled.md` (template env ENABLED=1 + CONTEXT=ubuntu-hostinger; Claude dry run 2026-10-04: payment-service:8084 health/liveness/readiness UP via service proxy). [x] Codex (edits; Claude committed) `254a291e` [x] verify (3 files = spec, pytest 12/12, Codex mutation KeyError) [x] make test (402bd596 green) [x] operator `bin/k3dm-hermes-setup` 2026-10-04 — first poll 11:43:35Z app_health healthy "1 service(s) agree with their probe groups". **CLOSED.**
- [ ] **Hermes Slack-approval setup make targets** — operator asked 2026-10-04 to replace the 5 hand-typed credential steps. Spec `docs/bugs/2026-10-04-hermes-slack-approval-setup-has-no-make-target.md` (`hermes-approvals-kv` / `hermes-drain-token` (token via `security -i` stdin, read back, ROTATE=1) / `hermes-approvers APPROVERS=` / umbrella `hermes-approvals-setup`; stubbed BATS; guide + CHANGELOG). [x] Codex [x] verify `2054d058` (20/20 BATS; both mutations red; Claude hardened: APPROVERS read from env not recipe text, `</dev/null` on kv create — stub hung on inherited stdin) [x] make test `09370a01`: 1345/1345 BATS; test-bin 287/289 — 2 reds PRE-EXISTING at `544ed18a` (k3dm_cleanup.bats:89 GNU-only `stat -c` on macOS; make_lifecycle.bats:17 `make down` `_keep_hub_flag=--keep-hub` assertion) — untriaged [~] operator: ran drain token MANUALLY (first keychain write failed 'User interaction is not allowed', retry ok; APPROVAL_DRAIN_TOKEN uploaded) — KV binding, APPROVER_ALLOWLIST, deploy-worker still pending. Operator's first `make hermes-approvals-setup` died SILENTLY in hermes-approvals-kv (`x=$(cmd)` under set -e exits before the friendly message) — fixed: `|| true` on Keychain reads, wrangler output printed on create failure, 2 regression tests (red on old recipe). Operator had used Claude's PLACEHOLDER id U07ABC12DEF — needs real member ID (Profile → ⋮ → Copy member ID). Follow-up (unanswered): LaunchAgent template lacks `K3DM_HERMES_APPROVAL_DRAIN_URL`. Operator rerun with real member ID: kv create failed 'APPROVALS_KV already exists' (made by hand earlier) — Claude bound existing id `ee9eb140ea624a09802fef9e16396caf` in wrangler.toml; operator reruns setup (KV step skips). `ROTATE=1` rerun SUCCEEDED 2026-10-04: APPROVAL_DRAIN_TOKEN (new 64-hex) + APPROVER_ALLOWLIST uploaded. Guide gained member-ID how-to, troubleshooting table, recovery notes. Operator DONE 2026-10-04: deploy-worker, Slack Interactivity + `/hermes-auth`, drain URL set by hand via PlistBuddy (verified in `launchctl print`). Automation spec `docs/bugs/2026-10-04-hermes-launchagent-template-lacks-approval-drain-url.md` (static URL in template + opt-in moves to Keychain drain token) [x] Codex [x] verify (232 pytest; gate mutation red; Claude fixed Codex typo `k3d-slack-relay` → `k3dm-slack-relay` in template/test/guide — test was self-consistent so it passed). Operator: rerun `bin/k3dm-hermes-setup` optional (hand-set URL already correct).
- [ ] **index-docs** — paused 2026-10-04 at 1000/1120 on the Gemini free-tier daily embeddings quota (HTTP 429, retry ~12h); re-run `make index-docs` after reset, it resumes.
- [ ] **index-docs local embedding cache** — operator asked 2026-10-04: hub loss costs >1 day of Gemini quota to re-index (1000/1120 paused). Spec `docs/bugs/2026-10-04-index-docs-rebuild-after-hub-loss-costs-a-day-of-quota.md` (SQLite cache ~/.cache/k3dm/embeddings.sqlite keyed by model/dim/task/text; newest-dated-first on misses; summary 'from cache'). [x] Codex [x] verify (316 pytest incl. 7 new; cache-off mutation → 3 red; Claude fixed duplicated EMBED_DIM=768 in embed_cache.py → import from prior_art). Cache fills on the next real index run.
- [ ] **Embedding cache second copy** — operator agreed 2026-10-04 (cache on same M4 as hub). Spec `docs/bugs/2026-10-04-embedding-cache-has-no-second-copy.md` (`make embed-cache-backup DEST=` via sqlite backup API + atomic replace; `embed-cache-restore SRC=` merges INSERT OR IGNORE) + integrity metadata per 2nd review (schema v2 via user_version, model/dim/task/content_hash/created/last_used; read+restore integrity checks; `embed-cache-stats`; `embed-cache-prune` = stale AND unused >90d). [x] Codex [x] verify (648 pytest; 6 mutations red→restored; Claude fixed spec defect: NULL last_used_at counted as unused + restore dropped metadata → first prune would wipe the v1/restored cache; migration now stamps timestamps, restore copies metadata, +2 tests). Operator next: `make embed-cache-backup DEST=…` after quota-reset index run.
- [ ] 2026-10-04 Codex queue: [x] root-owned logs (verified, committed this push) (docs/bugs/2026-10-03-root-owned-state-logs-dir-kills-grafana-port-forward.md) [x] e2e dispatch CPU gate — Codex done, Claude-verified, commit held until operator make e2e ends (docs/bugs/2026-09-30-e2e-harness-dispatch.md) [ ] deploy-worker keychain msg (docs/bugs/2026-10-02-deploy-worker-keychain-error-misleading.md) [ ] then payment e2e rerun (operator)
- [ ] Sandbox make up hijacks Hostinger launchd labels (frontend.3ai-talk.org 502, Pushgateway refused after sandbox expiry): docs/bugs/2026-10-05-sandbox-make-up-hijacks-hostinger-launchd-labels.md OPEN; operator workaround = plutil repoint + make refresh-edge; fix spec pending.
- [x] Stale active-provider marker trusted without liveness (Makefile status, cluster-status-summary, webhook): Recurrence 4 FIXED 2026-10-05, Claude-verified. [ ] operator `make restart-webhook`.
- [ ] lib-foundation `_browser_launch` missing ready helper under host: PR #61 MERGED `dbed340` (2026-10-05; fix branch, stays under [Unreleased] — no tag). Subtree pull DONE `1a62d0b2` (pushed; only scripts/lib/foundation touched). Live check: next `make up` with Chrome closed.
- [ ] 2026-10-05 `make up` FAILED exit 1 at Step 10b: sandbox node ip-10-0-1-161 kubelet went silent 12:20:37Z (EC2 alive, status checks ok); sandbox Prometheus: Trivy scan of kube-system/cilium (7 scanner containers x 1Gi limit) at 1265Mi, MemAvailable 398Mi; ESO webhook endpoints empty -> data-layer OutOfSync. CFN stack still up. Bugs filed: `docs/bugs/2026-10-05-sandbox-node-notready-trivy-cilium-scan-starves-kubelet.md` (ACG excludeNamespaces kube-system + scanJobsConcurrentLimit 1 + kubelet system/kube-reserved 256Mi) and `docs/bugs/2026-10-05-cluster-up-data-layer-wait-silent-on-cause.md` (explain op message + NotReady nodes; reconnect timeout logs 'connected'). Both dispatched to Codex (one run).
- [ ] Follow-up candidate: `shopping_cart.sh:1403` server-Ready probe `kubectl get nodes` has no `--request-timeout`; hangs silently ~1-2 min on a fresh sandbox (observed 2026-10-05 make up). Not filed yet.
- [ ] 2026-10-05 alert deep dive: 5 bug specs filed (argocd-cve-scan no-newer-chart exit 1; offline tests rotted on v1.41.0; nightly test-metrics push failure silent; hub Trivy scans vclusters; E2E alert re-fires on exporter rollout) — dispatched to Codex (one run). Claude verifies + commits.
- [ ] 2026-10-05 hub agent-0 k3s agent memory leak: measure growth rate (scratchpad RSS sampler, 10-min), then spec a kube-proxy sync-staleness alert (`docs/issues/2026-10-05-hub-agent-0-k3s-agent-memory-wedges-kube-proxy.md`).
- [ ] 2026-10-05 ACG extend fix (lib-foundation fix/acg-extend-wait-for-button): spec filed; [x] Codex [x] Claude verify (65cc6bd; jest 44/44, BATS 17/17, 8 new tests red pre-fix, reload + retry mutations red, cmp-restored) [x] PR #62 merged (1b4cd33; Copilot never picked up the request; credential-test gate skipped pre-PR, handed to operator post-merge) [x] make credential-test PASS post-merge (rc=0, sts OK, no restart) [x] subtree pull (3d8956e4, pushed) [x] launchd reinstall (operator 18:12; wrapper verified: node + acg_extend.js) [x] live wake verified (in-process watcher PID 13364, 19:12: found `[data-testid="extend-sandbox-modal"] button:has-text("Extend")`, "Extend action complete"; Auto Shutdown moved 19:25 → 23:25) [x] launchd agent itself verified 2026-10-05 21:42 PDT (04:42Z): first run after reinstall connected via CDP, TTL ~102m, "Extension window not open yet … Skipping" — no "No such file" error (the old wrapper failures stop at the reinstall). Logs now at ~/.local/share/k3d-manager/run/k3d-manager-acg-watch.{err,out}, not /tmp. [ ] a launchd-driven run that actually extends
- [x] 2026-10-06 ACG watcher still lets the sandbox expire (lib-foundation `fix/acg-watch-interval-and-expired-ttl`): launchd runs every 3.5h but extend only fires with <=65m left (21:42 PDT saw 102m, skipped; sandbox died ~23:24); 01:12 run read yesterday's 11:24 PM shutdown as +1331m. Spec `docs/bugs/2026-10-06-acg-watch-misses-extend-window-and-reads-expired-as-22h.md` filed [x] (`25e2b75`) [x] Codex [x] Claude verify (lib-foundation `211a3fd` pushed; RED + mutations A/B/C, jest 49/49, bats 170/170) [x] PR lib-foundation #64 (release v0.5.1, docs back-filled; CI green, Copilot 0 inline findings) [x] merged `cb5575c` [x] tag v0.5.1 + release [x] subtree-pull `09e8fe37` [ ] operator reinstall agent (acg_watch_start) + stop in-process 3h watcher.
- [ ] 2026-10-05 sudo prompt in `make up` Step 10g + `refresh-edge`: root cause = (1) sudo resolves bare `install` to gnubin (GNU coreutils) so the `/usr/bin/install` NOPASSWD rule never matches, (2) `bin/*` source stale `scripts/lib/system.sh` lacking the no-TTY `-n` guard. Spec `docs/bugs/2026-10-05-sudo-prompt-stale-system-sh-gnubin-install.md` filed [ ] Codex [ ] Claude verify [ ] commit. Follow-ups: lib-foundation path resolution upstream; reconcile the two system.sh copies; `sudo -n true` probe defect.
- [ ] 2026-10-06 Hub `federate-acg` TargetDown (operator asked to dispatch the sandbox-Prometheus bug). That bug (`2026-10-03-acg-sandbox-prometheus-crds-...`) was already mitigated (`3b789adf`, `98835aac`) and did not recur — status set MITIGATED. Live read-only check found a NEW cause: k3s kubelet endpoint exposes apiserver/etcd histograms → federate 75,583 series / 37.6 MB / 15.6 s vs 10 s timeout; port-forward :19190 (PID 13954) wedged. Spec `docs/bugs/2026-10-06-federate-acg-scrape-exceeds-timeout-k3s-control-plane-histograms.md` (exclude apiserver_/etcd_/scheduler_/workqueue_ → 23,777; scrape_timeout 30s) [x] [x] Codex `07385677` (pushed) [x] Claude verify (BATS 14/14, RED on temp copy: new tests 3+4 fail on old values, yq ok, 4 files) [ ] rollout (hub sync + operator restarts PF + up==1). Then release prep (compress memory-bank, make test, docs sweep, CHANGELOG promote, AppSet reapply, PR).
## 2026-10-06 — v1.41.0 release PR opened (#135)

PR https://github.com/wilddog64/k3d-manager/pull/135 is open from
`k3d-manager-v1.41.0` to `main`; branch was clean and pushed at `d7ee5520`.
Mergeability is `true` / `blocked` while checks run. The required Copilot
reviewer request returned no requested reviewer; verification is recorded in
`docs/issues/2026-10-06-v1.41.0-pr-copilot-request.md`.
## 2026-10-06 — Ubuntu CI plist test portability bug fixed

Filed `docs/bugs/2026-10-06-sandbox-launchd-test-requires-macos-plutil.md` for
PR #135 lint test 313 and fixed the BATS assertion with Python `plistlib`.
Focused suite: 8/8. Full `make test-bin`: 328/328; only expected tripwire
notices for blocked Keychain probes remain.
## 2026-10-06 — Ubuntu CI follow-up portability bug fixed

Tests 150 and 151 in `hub_restore.bats` used BSD/macOS `script` syntax. The
portable dialect-detecting helper now passes locally: `hub_restore.bats` 14/14
and `make test-bin` 328/328. CI rerun pending after push.
## 2026-10-06 — Ubuntu `script` exit propagation fixed

Added GNU `script -e` to preserve the wrapped preflight command's rc in tests
150 and 151. Local `hub_restore.bats` is 14/14 and `make test-bin` is 328/328;
the next CI run is pending.
## 2026-10-07 — direct test-all Grafana publication fixed

- [x] Filed `docs/bugs/2026-10-07-test-all-does-not-publish-grafana-result.md` after a direct
      full-suite run left the `k3dm Tests` dashboard with no data.
- [x] `make test-all` now captures and publishes the existing metrics contract on pass or failure,
      while returning the original suite exit status. `make test-metrics` remains always zero.
- [x] Cloud webhook fallback avoids duplicate publication after a Make-level metrics push.
- [x] Verification: webhook lifecycle publication tests 2/2; `make test-python-unit` completed
      its 7/12/33/27/6/6/4 Python unit files successfully; Make lifecycle BATS 6/6; Python
      compilation, `git diff --check`, doc links (1954 files), and `_agent_audit` passed.
- [x] Hostinger status evidence recorded in `docs/issues/2026-10-07-hostinger-status-transient-eso-data-layer.md`;
      live recheck was healthy. Commit `c67c3a9a` pushed to `origin/k3d-manager-v1.42.0`.
## 2026-10-07 — v1.35.0 health-probe diagnostics enhancement specified

- [x] Added `docs/plans/v1.35.0-health-probe-diagnostics.md`.
- [x] Scope covers probe exit codes, timeout state, bounded redacted stderr/stdout, explicit
      unknown versus failed states, consistent Slack/JSON output, and focused verification.
- [x] No runtime code changed; `make check-doc-links` passed for 1954 files and `git diff --check`
      passed.
## 2026-10-07 — Slack cluster-status and cluster-diagnose threading fixed

- [x] Filed `docs/bugs/2026-10-07-slack-cluster-diagnostics-not-threaded.md` for inconsistent
      top-level versus thread replies.
- [x] Routed `cluster-diagnose` through the shared thread-aware status delivery helper and passed
      `channel_id`; incoming thread replies now use the existing Slack thread.
- [x] Verification: focused status/diagnostics/masking tests 54/54; Python compilation,
      `git diff --check`, doc links (1955 files), and `_agent_audit` passed.

## 2026-10-07 — k3dm Tests Grafana no-data fix live-verified

- [x] Confirmed duplicate ownership: ACG and hub both managed `k3dm-test-metrics`; ACG's
      v1.41.0 copy overwrote the hub dashboard.
- [x] ACG ApplicationSet now excludes `k3dm-tests-configmap.yaml`; hub is the sole owner.
- [x] Live verification: hub Argo `Succeeded Synced Healthy`; datasource UID `prometheus`;
      `host.internal:9091` target up; Prometheus returned `k3dm_test_cases_total=2501`.
- [ ] Commit and remote proof pending.

## 2026-10-07 — v1.44.0 cloud-request Slack routing specified

- [x] Added `docs/plans/v1.44.0-cloud-request-slack-notification-routing.md`.
- [x] Defined alias-only routing, deny-by-default validation, fixed job-lifetime routing,
      bounded safe metadata, fallback behavior, security constraints, tests, and rollout.
- [x] No runtime code changed.

## 2026-10-07 — v1.44.0 cloud-request submitter authentication specified

- [x] Added `docs/plans/v1.44.0-cloud-request-submitter-authentication.md`.
- [x] Defined signed canonical envelopes, protected agent capabilities, replay/expiry checks,
      key revocation and rotation, migration modes, audit metadata, tests, and rollout.
- [x] No runtime code changed.

## 2026-10-07 — test-all failing-suite table clarified

- [x] Recorded cloud job `195eff6a` failure evidence and separated the two visible observability
      BATS failures from the aggregate 34-failure count; root cause remains pending full logs.
- [x] Changed panel 4 to an instant table with human-readable `Test suite`, `Result`,
      `Failed cases`, and `Target` columns and hidden Prometheus internals.
- [x] Dashboard appset BATS: 36 tests passed; doc links and diff checks passed.
- [ ] Commit/push and live Grafana sync pending.

## 2026-10-07 — failed test case metrics and bounded cloud diagnostics

- [x] Diagnosed the visible cloud failures as observability BATS cases 198 and 200; recorded
      the original job output and the uncertainty around the aggregate 34 failures.
- [x] Made cases 198/200 hermetic by stubbing the newer observability helpers and deterministic
      Prometheus basic-auth generation.
- [x] Added bounded `k3dm_test_failure` metrics with failed case number, name, suite, target,
      and first diagnostic reason; capped records and label sizes for Prometheus safety.
- [x] Changed the Grafana panel to show one readable row per failed test case and expanded the
      cloud response to preserve multiple failure summaries plus the final tail under 2,000 chars.
- [x] Verification: observability BATS 18/18; dashboard contract BATS 36/36; Python unit bundle
      7/12/33/27/6/6/4 all OK; smoke, compilation, and diff checks passed.
- [ ] Commit/push, restart webhook, sync the hub dashboard, and rerun cloud `make-test-all`.

## 2026-10-07 — Slack status replies use the incoming channel

- [x] Diagnosed the top-level `/cluster-status` screenshot as the configured-channel fallback
      bypassing thread delivery.
- [x] Added channel-aware Slack bot posting for cluster status and diagnostics, including new
      status threads and existing incoming threads; retained empty-channel fallback behavior.
- [x] Added issue doc `docs/issues/2026-10-07-slack-status-channel-fallback-not-threaded.md`.
- [x] Python compilation, `_agent_lint`, `_agent_audit`, and `git diff --check` passed.
- [ ] Run the focused pytest thread suite when the local pytest dependency is available, commit,
      push, restart webhook, and live-verify `/cluster-status` in the affected Slack channel.

## 2026-10-07 — cloud job exit code exposed

- [x] Diagnosed job `470f0304`: status and diagnostics were returned, but the Make return code was
      absent from the webhook status payload and summary artifact.
- [x] Persisted Make `exit_code` and added it to the terminal status API response; preserved the
      existing summary artifact schema.
- [x] Added `docs/issues/2026-10-07-cloud-job-response-missing-exit-code.md` and a lifecycle
      regression test for persisted exit code.
- [ ] Run the focused Python tests when pytest is available, commit, push, restart webhook, and
      verify a subsequent cloud job response includes `body.exit_code`.

## 2026-10-07 — transient ESO report investigated

- [x] Ran read-only Hostinger status checks after the screenshot; the short check was healthy and
      the full check confirmed ESO/data-layer recovery (`20/20`, `9/9`, and `4/4 ready`).
- [x] Recorded the exact screenshot symptoms and live evidence in
      `docs/issues/2026-10-07-cluster-status-eso-empty-output-and-thread-followup.md`.
- [x] Classified the ESO parse errors as transient empty/non-JSON probe output pending the
      v1.35.0 diagnostic enhancement; no remediation was applied.
- [ ] Reproduce the Slack command after restart and verify the actual-channel thread path.

## 2026-10-07 — cloud hub snapshot failures triaged

- [x] Mapped five of the six new failures to `scripts/tests/plugins/hub_snapshot.bats`.
- [x] Ran the focused suite locally: 14/14 passed.
- [x] Recorded cloud output and local TAP evidence in
      `docs/issues/2026-10-07-cloud-hub-snapshot-suite-failures.md`.
- [ ] Obtain a focused cloud rerun with complete BATS assertion output before changing snapshot
      behavior; the aggregate failures may share one cloud-only capture failure.

## 2026-10-07 — cloud failure classification fix

- [x] Filed `docs/bugs/2026-10-07-cloud-failure-classification-missing.md`.
- [x] Added `result_classification` to webhook status responses and cloud summary artifacts;
      failed first runs remain `failed_untriaged` until separately triaged.
- [x] Added artifact regression coverage for failed-job classification.
- [ ] Commit, push, restart webhook, and verify the next cloud response exposes the field.

- [x] Full local `make test` verification: 1,384/1,384 BATS passed; the reported case numbers all
      passed locally.

## 2026-10-07 — stale failed-case dashboard rows

- [x] Filed `docs/bugs/2026-10-07-test-metrics-stale-failure-series.md`.
- [x] Changed Pushgateway publication from `POST` to `PUT`, replacing the complete target group
      and preventing old `k3dm_test_failure` series from surviving.
- [x] Fixed the two Python failures exposed by the run: human-readable metric labels remain
      valid, and a new status thread safely falls back to the response URL on channel mismatch.
- [x] Elevated pytest passed `702 passed, 2 skipped`; dashboard BATS passed `36/36`; compile,
      lint, audit, and diff checks passed.
- [x] Committed and pushed as `b5c8ca6a`; run `make test-all` once more to confirm Grafana lists
      exactly the current failures.

## 2026-10-07 — freshness panels made unambiguous

- [x] Filed `docs/bugs/2026-10-07-test-dashboard-freshness-aggregation.md`.
- [x] Aggregated freshness and last-passing queries with instant `max(...)` PromQL.
- [x] Prevented nonzero Make runs with zero parsed failures from updating the last-success metric.
- [x] Metrics pytest passed `21`; Grafana dashboard BATS passed `37/37`; compile, lint, audit,
      and diff checks passed.
- [x] Committed and pushed as `ea896a3d`; ArgoCD reports `Synced Healthy`, and the live ConfigMap
      contains the instant `max(...)` freshness queries.

## 2026-10-07 — successful-run label clarified

- [x] Renamed `Last passing run` to `Last successful run` and added a dashboard contract check.
- [x] Committed and pushed as `1aea506b`; synced and verified the live label as `Last successful
      run` with ArgoCD `Synced Healthy`.

## 2026-10-07 — P0 last-success retention

- [x] Added a separately grouped Pushgateway success marker updated only after successful runs.
- [x] Preserved current-run `PUT` replacement so failed-case series still clear correctly.
- [x] Metrics pytest passed `24`; Grafana dashboard BATS passed `37/37`; compile, lint, audit,
      and diff checks passed.
- [ ] Commit, push, and live-verify success -> failure retention in Grafana.

## 2026-10-07 — test dashboard no-data recovery

- [x] Diagnosed missing localhost:9091 Pushgateway forward; no exporter or dashboard code change
      was needed.
- [x] Ran `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger` and verified Pushgateway `OK`,
      retained success marker, and `passed` classification.
- [x] Recorded the live output in `docs/issues/2026-10-07-test-metrics-no-data-port-forward.md`.

## 2026-10-07 — Grafana run classification

- [x] Added `k3dm_test_run_classification` with explicit `passed` / `failed_untriaged` labels.
- [x] Updated the hub-owned k3dm tests dashboard panel to show the classification and retain the
      raw exit-code metric as supporting data.
- [x] Focused Grafana dashboard suite passed 36/36; `make test-python-unit`, Python compilation,
      metric smoke check, `_agent_lint`, `_agent_audit`, and `git diff --check` passed.
- [x] Committed as `9bf7898f`, pushed to `k3d-manager-v1.42.0`, and synced the hub dashboard;
      ArgoCD reports `Synced Healthy` and the live ConfigMap queries the new metric.
- [ ] Run the next `make test-all` and verify that the panel displays its `passed` or
      `failed_untriaged` classification row.
## 2026-10-07 — test dashboard clean-run clarification

- [x] Confirmed equal freshness ages are expected for a latest passing run.
- [x] Clarified the failure table title and clean-run `No data` description.
- [x] Dashboard contract suite passed 37/37; live ConfigMap verified after `make observability`.
## 2026-10-07 — dashboard elapsed-time labels clarified

- [x] Verified raw timestamps and passed classification explain equal elapsed values.
- [x] Renamed both stat panels to explicitly describe elapsed time.
- [x] Dashboard contract suite passed 37/37; live rollout pending.
## 2026-10-07 — latest-run dashboard semantics corrected

- [x] Changed the first panel from elapsed age to fixed latest-run timestamp.
- [x] Preserved increasing elapsed semantics for the last-success panel.
- [x] Dashboard contract suite passed 37/37; live rollout pending.
## 2026-10-07 — fixed latest-run epoch display

- [x] Recorded the seconds-versus-milliseconds Grafana rendering bug.
- [x] Converted the latest-run timestamp query to milliseconds for `dateTimeAsIso`.
- [x] Dashboard contract suite passed 37/37; live rollout pending.
## 2026-10-07 — P1 stale sandbox cleanup reporting fixed

- [x] Corrected cleanup preview/apply help and local-only scope wording.
- [x] Added truthful per-resource outcomes and nonzero incomplete-cleanup status.
- [x] Persisted webhook terminal status, exit code, and bounded redacted output.
- [x] Focused tests passed: cleanup 4/4, lifecycle 8/8, Slack relay 36/36.
- [ ] Live Slack verification remains pending.
## 2026-10-07 — Slack cleanup thread context fixed

- [x] Preserved `thread_ts` from slash command through cleanup webhook job creation.
- [x] Validated cleanup action names in thread messages.
- [x] Focused validation passed: Slack relay 37/37, cleanup BATS 4/4, webhook pytest 2/2.
- [x] Deployed Cloudflare worker version `6c4509c9-6567-4113-bbcb-b2cc9cd3ed0a`; signed probe returned HTTP 200.
- [ ] Perform live Slack thread verification.
## 2026-10-07 — Slack authorization failures now reply in-thread

- [x] Diagnosed silent cleanup follow-ups as `unallowlisted` user rejection.
- [x] Added a generic in-thread authorization failure response without bypassing the allowlist.
- [x] Focused guard test passed 1/1; full webhook BATS has unrelated connection-refused failures.
- [ ] Add `U0B89H45SUA` to the Slack role map if this operator should be authorized.
## 2026-10-07 — Slack cleanup notification fallback added

- [x] Added response-URL fallback for failed bot-thread notifications.
- [x] Preserved the originating `thread_ts` in the fallback payload.
- [x] Webhook cleanup tests passed 3/3; live Slack verification remains pending.
## 2026-10-07 — Slack response URL preferred for job replies

- [x] Prefer command-specific response URL for threaded job notifications.
- [x] Retain bot posting as fallback and expose response-post success/failure to callers.
- [x] Webhook notification tests passed 4/4; live Slack verification remains pending.
## 2026-10-07 — cleanup now creates threads for top-level Slack commands

- [x] Forwarded Slack channel ID with cleanup requests.
- [x] Created a bot thread for top-level cleanup invocations, matching status/diagnostics.
- [x] Validation passed: webhook cleanup 5/5, Slack relay 37/37.
- [x] Deployed Cloudflare worker version `d44059a2-964b-47d8-8a7b-7e4390b7b623`.
- [ ] Perform live verification.
## 2026-10-07 — top-level cleanup completion now posts into created thread

- [x] Marked webhook-created cleanup threads and posted completion directly into them.
- [x] Kept response URL fallback for existing incoming threads.
- [x] Webhook notification tests passed 6/6; live verification pending.

## 2026-10-07 — three Slack thread command routes implemented

- [x] Routed `cluster-diagnose`, `k3dm`, and `argocd-upgrade` from top-level and threaded messages.
- [x] Preserved originating `thread_ts` and channel for child jobs.
- [x] Added terminal Slack reporting for threaded ArgoCD upgrades.
- [x] Focused Python validation: 55 tests, 90 subtests passed; Slack relay: 37/37 passed.
- [ ] Live Slack verification and webhook restart remain pending.
- [ ] Combined webhook BATS has connection-refused fixture failures; see the validation issue doc.
- [x] Implementation commit `b5cf7272` pushed to `k3d-manager-v1.42.0`.

## 2026-10-07 — ArgoCD infra upgrade confirmation gate

- [x] Filed and fixed the unsafe unconfirmed shared-infra upgrade path.
- [x] `/argocd-upgrade <version> infra` now requires `confirm`; `acg` remains unchanged.
- [x] Webhook focused tests: 17 passed; Slack relay tests: 38 passed.
- [ ] Restart webhook and perform live Slack verification.
- [x] Implementation commit `1f8c09ef` pushed to `k3d-manager-v1.42.0`.

## 2026-10-07 — k3dm thread context and test Slack isolation

- [x] Forwarded and persisted `/k3dm` Slack thread/channel metadata.
- [x] Prevented webhook BATS fixtures from inheriting live Slack delivery credentials.
- [x] Focused webhook tests: 17 passed; Slack relay tests: 39 passed; shellcheck clean.
- [ ] Restart webhook and verify a threaded `k3dm test-all` live.
- [x] Implementation commit `2acbf4cd` pushed to `k3d-manager-v1.42.0`.

## 2026-10-07 — threaded ArgoCD usage de-duplicated

- [x] Suppressed the duplicate channel-level acknowledgement for invalid threaded requests.
- [x] Preserved a single top-level usage response.
- [x] Slack relay tests: 40 passed; shellcheck clean.
- [ ] Restart/deploy and perform live Slack verification.
- [x] Implementation commit `7882f338` pushed to `k3d-manager-v1.42.0`.
- [x] Deployed Cloudflare relay version `92eb6acf-b158-4b7a-aa8f-eafb594348b5`.
- [x] Hardened thread anchors to persist the incoming Slack channel before child dispatch.
- [ ] Restart webhook and retry the threaded `k3dm test-all` job.
- [x] Implementation commit `22208b72` pushed to `k3d-manager-v1.42.0`.
- [x] Added automatic parent-thread creation for top-level `/k3dm` jobs.
- [x] Focused webhook tests: 18 passed.
- [ ] Restart webhook and retry top-level `k3dm test-all`.
- [x] Implementation commit `6c5ef7fb` pushed to `k3d-manager-v1.42.0`.
## 2026-10-08 — k3dm Tests failure history panel

- [x] Added a separate `Failures in selected time range` Grafana table.
- [x] Preserved latest-run table semantics and current failure clearing.
- [x] Deduplicated repeated scrape observations with `max_over_time` and exposed target/origin.
- [x] Dashboard BATS: 38/38 passed; exporter metrics pytest: 24 passed.
- [ ] Verify failed -> passed history and selected-range filtering live in Grafana.
- [x] Commit `448498b5` pushed to `origin/k3d-manager-v1.42.0`; no PR created.
## 2026-10-08 — Slack cleanup thread channel handoff

- [x] Pass the originating Slack channel into threaded cleanup workers.
- [x] Add regression coverage for `cleanup-stale-sandbox apply` thread dispatch.
- [x] Focused webhook tests: 25 passed; Python compilation and diff checks passed.
- [ ] Restart/deploy webhook and perform live Slack preview/apply/failure verification.
- [ ] Commit and push implementation.
## 2026-10-08 — Slack cleanup relay deployment

- [x] Redeployed Cloudflare Slack relay version `f91afb9f-e447-4d6f-897a-1a3122836065`.
- [x] Worker smoke request passed; webhook restart completed.
- [ ] Retry threaded `cleanup-stale-sandbox apply` and confirm queued/completion or failure in-thread.
## 2026-10-08 — Slack cleanup plain-message delivery remains blocked

- [x] Verified the local cleanup handler and thread-channel fix.
- [x] Restarted webhook and redeployed relay version `f91afb9f-e447-4d6f-897a-1a3122836065`.
- [x] Captured exact evidence: no `POST /slack/events` for the plain threaded message.
- [ ] Investigate Slack Events subscription/delivery configuration.
- [x] Slash command inside thread remains the supported workaround.
## 2026-10-08 — Slack cleanup root-event forwarding

- [x] Filed the cleanup-specific P1 bug with exact webhook evidence.
- [x] Forward root JSON Slack Events to the webhook event endpoint.
- [x] Node relay tests: 41/41 passed.
- [x] Deployed relay version `e9d3dfc2-ee92-4444-938f-440b4bcc9aad`.
- [x] Retried plain threaded cleanup; no `/slack/events` request or job was created.
- [ ] Verify Slack Event Subscriptions Request URL and message event subscriptions.
## 2026-10-08 — v1.42.0 three-fix implementation and verification

- [x] Fix 1 committed and pushed: `fedcfcd88a6de92ed0a4f7e0617310029cb41304`.
- [x] Fix 2 committed and pushed: `8aa14053fecd89930c680ce2a6a975069ae9e6d6`.
- [x] Fix 3 committed and pushed: `b2c45ae3c2e8a96c383b943bab242e8a3f0e9d59`.
- [x] Three bug docs now state `FIXED in branch; live verification pending` with their fix SHA.
- [x] `shellcheck bin/k3dm-ask-bash`: clean.
- [x] `pytest scripts/tests/bin -q`: 516 passed, 1 skipped.
- [x] `node --test workers/slack-relay/test/`: 42 passed, 0 failed.
- [x] Focused RED/green checks: Fix 1 old-copy RED 3 failed/4 passed; Fix 2 old-guard RED
  17 failed/35 passed; Fix 3 old wrapper read the canary with rc 0 for absolute `-c`, sibling,
  and `..` cases; new ask-bash BATS 4/4.
- [ ] Full `make test`: one run reached 1,387 cases and exited 2 with four unrelated
  `e2e_remote` failures after two affected fixture failures were corrected and rechecked 2/2.
  Verbatim output and follow-up are in `docs/issues/2026-10-08-v1420-gate-results.md`.
- [x] Remote branch tip verified equal to local HEAD after push.
- [ ] Operator live verification remains pending; no deployment, restart, `/ask`, PR, merge,
  or live-cluster action was performed.

- 2026-10-08 23:44Z: Slack thread replies verified working (bot must be in the channel). Residual: /slack/events 401s from bot-echo events over MAX_BODY=4096 truncating before HMAC; fix proposed in docs/bugs/2026-10-08-slack-cleanup-thread-event-undelivered.md, awaiting go for Codex.

- 2026-10-08 23:55Z: Oversized Slack event 401 fix specced (70d09218) and dispatched to Codex.

- 2026-10-09: Claude verified Codex Slack body-cap fix (f127fd7b, d0eb99e8, 26ae4eb7 on origin): relay node tests 45/45, webhook.bats Slack 8/8, RED on pre-fix worktree 2/2 fail. Operator: make restart-webhook && make deploy-worker.

- 2026-10-08 23:58Z: Slack body-cap fix verified live — job ff32a425 success, /slack/events 3x200, 0x401 after bot posts.

- 2026-10-08: Spec docs/plans/v1.43.0-bug-priority-tracking.md (bug Priority P0-P3, vectordb priority/state columns, ask-doc suffix, k3dm_bug_docs metric + Grafana dashboard, pre-commit check). 4th v1.43.0 spec. Awaiting go; Codex dispatch needs k3d-manager-v1.43.0 branch.

- 2026-10-08: Bug priority tracking added to docs/roadmap.md as v1.43.0 candidate; spec QUEUED, dispatch to Codex when k3d-manager-v1.43.0 opens.

- 2026-10-08: Spec docs/plans/v1.43.0-hermes-r10-delete-superseded-failed-job.md (superseded_jobs sensor + R10 approval-gated, target-pinned). v1.43.0 now at 5-plan cap; roadmap updated.
## 2026-10-08 — September bug-doc triage completed

Added one evidence-backed Status line to each of the 19 requested September bug docs. Counts: 16 FIXED, 2 PARTIAL, 0 OPEN, 1 UNKNOWN. Docs commit `fbdf1c23` is pushed; `make check-doc-links` passed (`19 file(s) OK`). PR URL: none.
2026-10-08: Hub snapshot deletion guard, status freshness, and PV Retain target committed in fa3340bc; live verification pending (Codex).
2026-10-08: Hub teardown guard round 2 fixed in `32395370`; status recorded in `ca8db0d9`; live verification pending (operator).
2026-10-08: Hub snapshot round 3 hostname mapping fixed in `2e8996ae`; live verification pending (operator).
2026-10-08: Hub snapshot round 4 now captures claim trees as in-node tar streams in `fbebe9df`; live verification pending (operator).
2026-10-08: Hub snapshot round 5 fix committed as e3040689; live verification pending (operator). PR URL: none.
## 2026-10-08 — Host disk-space sensor implemented (`fb563727`)

- Implemented the v1.42.0 host disk sensor Changes 1–5 and Tests: local/SSH argv-only `df`, non-fatal Pushgateway PUT retries, Hermes integration, three hub alerts, dashboard, docs, and regression tests.
- RED: archived pre-change commit `5872ba40` with only changed/new tests had 7 failures: four collector tests, two host-disk manifest/dashboard tests, and the Hermes disk publisher test; 61 existing tests passed.
- GREEN: `pytest scripts/tests/bin scripts/tests/hermes -q` → `769 passed, 1 skipped in 126.40s (0:02:06)`; `make validate-manifests FILES="scripts/etc/prometheus/rules/host-disk.yaml scripts/etc/argocd/platform-ops/grafana-dashboard-host-disk.yaml"` → `Summary: 2 resources found in 2 files - Valid: 2, Invalid: 0, Errors: 0, Skipped: 0`.
- Commit 1: `fb563727`; Commit 2: this documentation commit after `fb563727`; PR URL: none. Live verification remains pending (operator). No SSH, remote `df`, kubectl, observability deployment, launchctl, or Hermes restart was run.
## 2026-10-08 — Hub snapshot retention round 6 fixed (`81baeca9f455a94110716d0ccc54fc7c3f969112`)

- Implemented the spec's Fix 1–6 and Tests 1–8 on `k3d-manager-v1.42.0`: newest-first verified pruning, automatic post-capture pruning with incomplete protection, M2 free-space preflight, checked final rename, docs, changelog, and regression coverage.
- RED at `a6a53d7d` with only the updated BATS file: the five required tests failed — prune newest, capture auto-prune, auto-prune failure tolerance, insufficient space, and rename failure.
- GREEN: the eight new hub snapshot tests passed; the required hub snapshot, hub recovery, and cluster-down suites passed; shellcheck was clean; `_agent_audit` passed.
- Pushed fix commit to `origin/k3d-manager-v1.42.0`; `HEAD` and remote both equal `81baeca9f455a94110716d0ccc54fc7c3f969112`. PR URL: none. Live verification remains pending.
