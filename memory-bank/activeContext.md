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

## 2026-10-08 — v1.42.0 three bug fixes committed and pushed

- Ask Claude argv fix: `7089dd10`; audit pytest isolation: `2f7e0eb5`; Hermes values-branch count fix: `895221cb`.
- Bug status commits: `0753460c`, `71cca587`, `eae01de6`; all pushed to `origin/k3d-manager-v1.42.0`. PR URL: none.
- RED regression runs failed against pre-fix temp copies as specified. GREEN gates: pytest `287 passed, 90 subtests passed`; Python compilation clean; `bats scripts/tests/lib/webhook.bats` `1..68` with all tests `ok`. Live verification remains pending (Claude).

## 2026-10-08 — v1.42.0 bug survey; 2 new bugs filed; 3 fixes queued for Codex

- Filed `docs/bugs/2026-10-08-ask-claude-prompt-parsed-as-cli-option.md` (P1): top-level `/ask claude` dies with `unknown option '---USER QUESTION START---'` (claude CLI 2.1.290 rejects a dash-led positional). Fix: `-- user_prompt` last. Reproduced locally; `--` form verified working.
- Filed `docs/bugs/2026-10-08-webhook-tests-write-real-audit-log.md` (P2): 3 tests in `test_webhook_cluster_status_thread.py` write `actor:"test"` admin rows to the live `audit/remote-operator.jsonl` (72 rows since 10-02). Fix: autouse conftest fixture redirecting `webhook.policy.AUDIT_DIR`.
- Added Fix spec to `2026-10-08-hermes-values-branch-counts-sources-as-apps.md`.
- Stale statuses corrected: slash-role FIXED+live (`8aa14053`), thread routing FIXED+live (`fedcfcd8`), ask-bash FIXED in branch (`b2c45ae3`, live check blocked by the /ask claude bug), plan `v1.42.0-slack-authz-and-ask-scope-fixes.md` IMPLEMENTED.
- Next: dispatch the 3 bug fixes to Codex on `k3d-manager-v1.42.0`; operator: AppSets reapply.

## 2026-10-08 — Slack oversized event verification and bot-echo relay fix

- Implemented the requested bug fix on `k3d-manager-v1.42.0`: full-body Slack signature
  verification with a 65536-byte cap, corrected thread usage text, and edge acknowledgment
  for bot/subtype event callbacks. Code commits: `f127fd7b`, `d0eb99e8`.
- Relay tests passed 45/45; Python compilation passed. BATS had one initial assertion typo in
  the new test, then was corrected; the full rerun and final remote push are pending.
- No PR, deployment, live :7443 change, launchd change, or wrangler deploy. PR URL: none per task.

## 2026-10-08 — operator recovery done; relay redeployed

- Operator ran `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger` + `make restart-webhook`; hub
  `up{job="k3dm-test-pushgateway"}` = 1. `make deploy-worker` first failed (locked login keychain);
  after `security unlock-keychain` it deployed `k3dm-slack-relay` version `7cab1773` (sends
  `slack_user_id`). Signed probe 23:06:03Z = `/cluster-status` allowed as reader. Pending operator
  live checks: unmapped `/cluster-down` refused, thread `cluster-diagnose`, `/ask` shell.
- Live: `/k3dm help` → role admin (audit 23:09:57Z) ✅. Thread reply `cluster-diagnose` → no `/slack/events` at all since 17:00:35Z (Slack stopped delivering after 401 burst); webhook pid 20722 started before keychain unlock, signing secret may be empty. Operator: `make restart-webhook` + re-verify Slack Event Subscriptions. Recurrence logged in `2fdc9b48`.

## 2026-10-08 — cleanup/pushgateway fix VERIFIED by Claude

- Codex `87eef35e` (label fix + regression test), `0c487442` (ask-bash sandbox test rewrite),
  docs `ddbef25d` — on origin, scope matches the bug doc. Claude reran outside Codex: shellcheck
  clean, BATS 9/9; RED: new cleanup test fails vs `50975556` script; mutation: sandbox test fails
  with sandbox-exec disabled. Pending operator: `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger`,
  then confirm hub `up{job="k3dm-test-pushgateway"}` = 1. Live verify of v1.42.0 fixes still pending.

## 2026-10-08 — cleanup-stale-sandbox Hostinger pushgateway fix committed

- Implemented the bug spec Fix items 1–3 on `k3d-manager-v1.42.0`. Commits: `87eef35e` (agent
  label and regression test), `0c487442` (OS-sandbox test rewrite). ShellCheck passed; targeted
  BATS passed 9/9, including the real Darwin `sandbox-exec` test. The final docs commit records
  the fixed status and operator recovery.

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

## 2026-10-07 — P0 last-success retention fixed

The exporter now publishes a separate `-last-success` Pushgateway group only after a successful
run. Failed current-run `PUT` replacement still clears stale failure labels but cannot delete the
prior successful timestamp. Focused metrics tests passed `24`; Grafana dashboard BATS passed
`37/37`; compilation, lint, audit, and diff checks passed. Commit and live success -> failure
Grafana verification remain pending.

## 2026-10-07 — test dashboard no-data state diagnosed

The dashboard temporarily showed no data because the Hostinger Pushgateway LaunchAgent was not
loaded and localhost:9091 refused connections. Ran `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger`;
localhost:9091 now listens and returns `OK`, with the retained success marker and passed
classification present. Recorded exact evidence in
`docs/issues/2026-10-07-test-metrics-no-data-port-forward.md`. This was access-layer downtime,
not a P0 exporter regression.

## 2026-10-07 — k3dm Tests failure-history gap filed (OPEN, v1.42.0)

Filed docs/bugs/2026-10-07-k3dm-tests-failure-history-missing.md and an issue evidence note.
Operator screenshot shows latest passed / zero failures but "No data" in the instant current
failure table despite earlier failures in the six-hour graph. Acceptance adds a separate
time-range history table while preserving PUT replacement/current clearing; deduplicate scrape
samples and avoid invented run timestamps or high-cardinality run labels. Historical sample
availability remains unverified. Documentation only; implementation pending. No PR.
Publication commit is recorded in the git history for these files.

## 2026-10-06 — HIPAA readiness added as an unversioned roadmap theme

The user asked to put HIPAA compliance into the roadmap. `docs/roadmap.md` now records this as
future HIPAA readiness and compliance-gap-assessment work, not a certification claim. The initial
boundary is no PHI by default in development, k3d/k3s sandboxes, automation, external agents,
Slack/AI/webhooks, CI artifacts, logs, and backups until data flows, BAAs, risk analysis, and
control ownership are documented. A dedicated scope document and legal/security review are
required before assigning a release; v1.42.0 is already at its five-plan cap.

## 2026-10-06 — v1.42.0 first high-priority bug fixed

E2E runner mutable-image pull policy fixed in commit `98d2bbcb` on
`k3d-manager-v1.42.0`. `E2E_IMAGE_PULL_POLICY` now defaults to `Always` for `latest` and
`IfNotPresent` for other tags, supports explicit `Always|IfNotPresent|Never`, rejects invalid
values, and applies to both Tier 1 and Tier 2 runner Jobs. `scripts/tests/plugins/e2e.bats`:
66/66 passed; `shellcheck scripts/plugins/e2e.sh` clean; `_agent_audit` passed; doc links passed.
The separate `make e2e` exit-1-after-pass behavior remains open. No PR created yet.

The E2E exit-1-after-pass follow-up is fixed in commit `cb9184b0` on
`k3d-manager-v1.42.0`: result-event stale ConfigMap deletion now uses `--no-exit`, and normal
publication is guarded as best-effort. `scripts/tests/plugins/e2e.bats` is 67/67; ShellCheck,
`_agent_audit`, and the commit doc-link hook pass. The user can now run the full live `make e2e`.

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

## 2026-10-06 — Cloud-bridge Make output selection fixed

Fixed the Make-job output mismatch on `k3d-manager-v1.42.0`: added the shared bounded/redacted
`webhook.job_output.read_job_output` selector, preferring `make.log` for Make jobs and preserving
`log`/`output` precedence for non-Make jobs. HTTP job-status, Slack `logs`, `diagnosis`, and
`ask` context now use it. Focused regression tests: 12 passed; `make test-python-unit`: 7
unittest files passed; `make test-pytest`: 689 passed / 2 skipped. `ruff` was unavailable;
`git diff --check` and Python compilation passed. Live cloud/Slack verification remains for the
operator. Commit `d39ecf9d` is pushed to `origin/k3d-manager-v1.42.0`; no PR was created per
repository instructions.

## 2026-10-07 — v1.43.0 E2E failure-evidence enhancement specified

Added `docs/plans/v1.43.0-e2e-failure-artifacts.md` as a proposed enhancement. It specifies
best-effort pre-teardown capture of E2E summaries, Playwright logs/screenshots/traces, bounded
redacted structured bridge evidence, failure classification, artifact retention, and live
success/failure verification. No runtime code changed.

## 2026-10-07 — ask-docs failure propagation fixed

Fixed `docs/bugs/2026-10-06-ask-docs-model-failure-reported-as-success.md` on
`k3d-manager-v1.42.0`: ask-docs now returns explicit string-compatible result metadata, marks
empty/unavailable/model-exception summaries as failed while preserving sources, records bounded
safe candidate failure details, and reserves a fallback budget between AI candidates. Job status
now propagates the outcome and exposes safe metadata. Focused tests: 40 passed; full pytest:
692 passed / 2 skipped; Python unit suites passed; `_agent_audit`, compile, and diff checks passed.
Live host credential/service verification remains pending.

## 2026-10-07 — ask-docs ISO-date redaction false positive fixed

Filed and fixed `docs/bugs/2026-10-07-ask-docs-redacts-iso-dates-as-phone.md`: the phone scrubber
now excludes `YYYY-MM-DD` while continuing to redact phone-like values. Regression coverage was
added to the ask-docs suite; live Slack verification remains pending.

## 2026-10-07 — ask-docs latency metrics enhancement specified

Added `docs/plans/ask-docs-response-latency-metrics.md` as a release-placement-neutral
observability spec, with v1.43.0 as the candidate milestone. It separates retrieval/model/
delivery/total timing, defines bounded Prometheus labels and Grafana panels, and keeps exact
per-job timing in scrubbed metadata rather than high-cardinality metrics. No runtime changes.

## 2026-10-07 — ask-docs quality observability enhancement specified

Added `docs/plans/ask-docs-quality-observability.md` as a companion, release-neutral spec with
v1.43.0 as the candidate. It defines privacy-safe source usefulness, citation, summary outcome,
feedback, follow-up, and offline groundedness signals, plus human-readable Grafana panels and
table columns. No runtime changes.

## 2026-10-07 — durable test-metrics log enhancement specified

Added `docs/plans/v1.43.0-test-metrics-log-retention.md` as the fifth and final v1.43.0 plan
candidate. It specifies durable user-owned logs under `~/.local/share/k3d-manager/test-metrics`,
immediate path announcement, live tailing, private file modes, bounded retention, safe fallback,
and preservation of the existing exporter/exit-status contract. No runtime changes.

## 2026-10-07 — cloud make-test-all metrics publication fixed

Fixed `docs/bugs/2026-10-06-cloud-bridge-test-all-does-not-publish-grafana-metrics.md` on
`k3d-manager-v1.42.0`: completed `test-all` jobs now invoke the existing
`bin/k3dm-test-metrics` exporter once from the captured `make.log`, passing the original exit
code and elapsed duration. Publication warnings remain separate and cannot rewrite the test
status; unrelated Make targets are unchanged. `make test-python-unit` passed (11 lifecycle
tests plus all other unit files). Live Pushgateway/Grafana verification remains pending.

Updated `docs/bugs/2026-10-06-cloud-bridge-make-job-status-empty-output.md`: operator sees
automatic Slack output but cannot retrieve E2E job 033ceddc via logs. Slack thread logs,
diagnosis, and ask context omit make.log; cloud job-status also omits it. E2E final response
17:36:37Z is failed with empty output; failure cause remains unknown. Exact Slack command/error
not supplied, so thread association versus file lookup must be distinguished in live verification.
Added shared-selector/redaction/regression acceptance; no runtime changes or new test requests.

## 2026-10-06 — Second bridge test job succeeds but returns no log

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

# Active Context — k3d-manager

## 2026-10-07 — stale webhook thread mock fixed and full test-all is green

Fixed `scripts/tests/bin/test_webhook_ask_docs_thread.py`: its `_post_slack_bot` stub now
accepts `channel_id` and verifies the no-channel parent-thread path. Related webhook tests
passed 29/29. Full `make test-all` from tmux passed 2,531 cases with 0 failures; pytest was
718 passed and 2 skipped. Pushgateway connection refusal remained non-fatal during local
metrics publication. Implementation and verification are committed and pushed as `5309ec3a`;
no PR was created.

## 2026-10-07 — full test-all found stale webhook thread mock

Ran `make test-all` from tmux pane `20261004195335:2.1`. All 1,386 BATS cases passed,
including the five hub-snapshot cases and observability case from `fab52a19`; the 332-case
bin suite also passed. Pytest failed one test because
`test_webhook_ask_docs_thread.py` stubs `_post_slack_bot` without the new `channel_id`
keyword accepted by production at `bin/k3dm-webhook:1170`. Filed
`docs/issues/2026-10-07-test-all-webhook-thread-mock-signature.md`; the next fix is a test
stub/contract update, not a production Slack outage. Metrics Pushgateway refusal was
non-fatal.

## 2026-10-07 — cloud `fab52a19` failures classified as test-harness instability

Investigated six failures from cloud `make test-all` job `fab52a19`: case 198 in
`observability.bats` and cases 972, 973, 974, 976, and 983 in `hub_snapshot.bats`.
Both affected suites pass together under the tripwire harness (32/32), and the first
535 cases of a full local run also pass case 198. The full run independently reproduced
webhook fixture failures with curl status `000`/curl status 7, showing order/startup
instability rather than a proven product regression. Filed
`docs/issues/2026-10-07-test-all-fab52a19-order-dependent-failures.md`; no runtime fix yet.

## 2026-10-06 — test metrics imported into hub Grafana

Fixed the dashboard no-data topology in `docs/bugs/2026-10-06-k3dm-tests-dashboard-no-data.md`.
Hub Prometheus now scrapes the laptop Hostinger Pushgateway at `host.internal:9091` and keeps
only `k3dm_test_*` metrics. The hub dashboard ApplicationSet now imports `k3dm-tests`, whose
panels use the hub `prometheus` datasource; the existing hub Grafana port-forward is unchanged.
Dashboard and Pushgateway configuration tests passed 41/41, and doc links passed 1966 files.
Operator live `make test-all` and Grafana refresh verification are still pending.

## 2026-10-06 — test-all case 236 fixed

Fixed `docs/bugs/2026-10-06-makefile-e2e-recorded-fixture-exits-early.md`: the
`makefile_e2e_recorded.bats` extractor now exits only after the `_e2e_recorded`
definition's `endef`, and asserts that `script -q` was captured. The focused test
passes and `bats scripts/tests/bin` passes 328/328. The separate Grafana no-data
topology bug remains open.

## 2026-10-06 — test-all case 236 and Grafana no-data bugs filed

The prompt-hang fix worked: `hub_restore.bats` cases 149–235 passed. The next
`make test-all` run completed 328 cases but failed only case 236,
`recorded output preserves exit status and is mode 600`. Its fixture extractor exits
at the first earlier `endef`, so the generated Makefile omits `_e2e_recorded` and Make
reports `probe` up to date. Filed `docs/bugs/2026-10-06-makefile-e2e-recorded-fixture-exits-early.md`.

The same run published metrics successfully: localhost:9091 contained 1707 total
cases, one failed BATS case, exit code 2, and duration 466 seconds. The Grafana
dashboard still showed no data because its configured ACG datasource UID differs from
the Hostinger Pushgateway receiving localhost:9091 writes. Filed
`docs/bugs/2026-10-06-k3dm-tests-dashboard-no-data.md` with the topology evidence;
deployed Grafana datasource resolution still needs live confirmation.

## 2026-10-06 — `hub_restore` test hang fixed

Fixed `docs/bugs/2026-10-06-hub-restore-test-hangs-on-embeddings-prompt.md`. Added a
`_run_noninteractive_restore` test helper that redirects stdin from `/dev/null` for
restore cases unrelated to prompt behavior, preventing an inherited tmux TTY from
blocking on the embeddings-key prompt. `bats scripts/tests/bin/hub_restore.bats` passed
14/14 normally and 14/14 under a TTY; the agent audit passed. Full `make test-all` remains
for operator verification.

## 2026-10-06 — `make test-all` hang diagnosed

Filed `docs/bugs/2026-10-06-hub-restore-test-hangs-on-embeddings-prompt.md` and the
verbatim live evidence in `docs/issues/2026-10-06-hub-restore-test-hang.md`. The
interactive test run stopped after case 152 because the next `hub_restore.bats` test
inherits the tmux TTY and `bin/hub-restore` waits for the missing embeddings-key prompt
before reaching its Grafana retry assertion. No process was stopped and no code fix has
been made yet.

## 2026-10-07 — Make failure context live-verified

Operator queried failed job `ccc20dc9` after restart. `body.output` now included the
two earlier failing BATS tests and source lines, followed by the final `make: *** [test]
Error 1` tail. The failure-context bug is closed; the underlying observability test
failures are separate follow-ups.

## 2026-10-07 — Make failure context fix implemented

Fixed `docs/bugs/2026-10-07-make-job-tail-omits-failure-context.md`. The shared job-output
selector now preserves an early failure marker/context plus the final bounded tail for
failed Make jobs, while retaining prior behavior for passing and non-Make jobs. Focused
tests passed 24/24; `make test-python-unit` passed; pytest passed 696/2 skipped. Commit and
live deployment remain pending.

## 2026-10-07 — failed Make-job evidence gap queued

Filed `docs/bugs/2026-10-07-make-job-tail-omits-failure-context.md`. Live job `ccc20dc9`
returned a non-empty failed tail, but the bounded response omitted the earlier failing
test name and diagnostics. This is a separate open follow-up; the output-persistence fix
remains live-verified.

## 2026-10-07 — Make-job output retrieval live-verified

Operator restarted the webhook and cloud bridge, then verified job-status retrieval.
Passing job `715265ab` returned `body.status=success` with a non-empty Make log tail;
failed job `ccc20dc9` returned `body.status=failed` with a non-empty tail ending in
`make: *** [test] Error 1`. The output-persistence bug is live-fixed. The bounded tail
still omits earlier failing-test diagnostics; track that as an evidence-quality follow-up.

## 2026-10-06 — long Slack command help standardized

Filed `docs/bugs/2026-10-06-slack-command-help-inconsistent.md`. Audited the relay's
long usage/error messages and converted cluster lifecycle, resume, cleanup, `/k3dm`,
`/ask-docs`, and ArgoCD upgrade help to example-based text. Relay tests passed and
Worker version `1c21d3e7-1e39-4dfc-aeee-b16f5b326233` is deployed; live Slack confirmation
remains pending.

## 2026-10-06 — Slack cluster-diagnose help clarified

Filed `docs/bugs/2026-10-06-slack-cluster-diagnose-help-ambiguous.md`. Replaced the
single dense grammar line with example-based help showing cluster selection, all-pods,
pod, logs, and application forms. `pod <namespace> <pod>` is now the primary example.

## 2026-10-06 — namespace-first Slack pod diagnosis fixed

Filed `docs/bugs/2026-10-06-slack-cluster-diagnose-pod-order.md`. The relay rejected
`/cluster-diagnose hub platform-ops pod acg-expiry-check-29855580-ssvb` because it only
accepted verb-first `describe-pod <namespace> <pod>`. The parser now accepts namespace-first
`pod` as the same read-only describe action. Relay tests passed and Worker version
`0f46f722-0d87-4b86-815b-3f278bc8e9de` is deployed; live Slack retest remains pending.

## 2026-10-06 — Slack status thread context fixed

Filed `docs/bugs/2026-10-06-slack-status-thread-context-dropped.md`. The Slack relay
omitted `channel_id` for `/cluster-diagnose`, and native Slack event dispatch dropped
the event channel before launching status workers. Both paths now preserve channel
context so cluster status/diagnostics can use the existing Slack thread safely.
Focused verification: Python 11 passed, relay Node tests 33 passed, compilation and
diff checks passed. Commit `40591d93` is pushed. The Cloudflare relay was deployed with
`make deploy-worker` as version `432e1dfc-2f5c-4430-9e21-f45c4eb9b3fb`; live Slack
retest remains pending.

## 2026-10-07 — webhook analysis test false failure fixed

Filed `docs/bugs/2026-10-07-webhook-analysis-test-brittle-source-match.md` and fixed the
format-sensitive source assertions in `scripts/tests/lib/webhook.bats`. The ordered-candidate
check now ignores Python whitespace formatting, and the safe-sentinel check matches the semantic
sentinel text used by the current `AIResult` implementation. Focused test passed 1/1; full
`bats scripts/tests/lib/webhook.bats` passed 65 tests with 6 intentional skips; ShellCheck,
`git diff --check`, and `_agent_audit` passed. Commit `c0f5777e` is pushed to
`origin/k3d-manager-v1.42.0`; no PR was created per repository instructions.

> Compressed 2026-10-06 (v1.41.0 release prep). Full pre-compression detail:
> `memory-bank/archive/activeContext-2026-10-06.md`. Kept here: the v1.41.0 sections from
> 2026-10-03 onward, verbatim.

# 2026-10-06 — Current focus: v1.41.0 release prep

- federate-acg scrape timeout FIXED `07385677` and LIVE: hub app Synced `bd146637`, operator restarted PF :19190 (PID 3165) → hub target up, scrape 5.3 s, 23,772 samples.
- Release prep order: memory-bank compression (this) → `make test` + `make test-pytest` (background, no commits mid-run) → docs sweep → CHANGELOG promote `[1.41.0]` → releases rows → AppSet reapply (hub + ACG) + `argocd_check_values_branch` → PR, merge on operator go.
- Operator items outstanding: `make e2e`; confirm the Step 10g sudo fix on a reinstall run; `make index-docs` after quota reset; reinstall acg-watch agent done (30m).
- Unfiled follow-ups: `shopping_cart.sh:1403` `kubectl get nodes` lacks a timeout; `sudo -n true` probe defect; kube-proxy alert spec.

## 2026-10-06 — federate-acg scrape timeout FIXED (`07385677`), rollout pending

The CRD-discovery bug is MITIGATED, not reproduced today. The real current fault: hub `up{job="federate-acg"}`=0, `context deadline exceeded` at 10 s. k3s exposes apiserver/etcd/scheduler metrics on the kubelet endpoint, so `job=kubelet` federates ~50k histogram buckets (75,583 series, 37.6 MB, 15.6 s). Exclusion measured: 23,777. Hub holds 0 acg control-plane series, so nothing depends on them. Port-forward :19190 (kubectl PID 13954) wedged after the oversized transfers — operator restarts it after the fix syncs. Next after this: v1.41.0 release prep (operator 2026-10-06: compress memory-bank + release activities). Codex commit `07385677` verified by Claude (BATS 14/14, independent RED, scope 4 files). Rollout: hub app sync → operator restarts PF → confirm `up==1`.

## 2026-10-06 — stale Makefile URL default FIXED (`5426de02`)

Codex committed and pushed `5426de02`; Claude verified (BATS 10/10, RED shown, scope 5 files). Spec status set FIXED.

Operator asked for a bug + Codex dispatch. Dedup found `docs/bugs/2026-07-19-makefile-stale-acg-sandbox-url-default.md` (v1.18.0, never implemented — `git log -S` shows `Makefile:16` unchanged since `1a8307c6`); appended a "Recurrence — 2026-10-06" section as the v1.41.0 spec. Impact now cosmetic/latent: lib-foundation rewrites the legacy path (`sandbox.js:68`, `acg_extend.js:23`, `acg_restart.js:246`), so `make up` works. Scope: `Makefile:16`, `docs/howto/makefile.md:252`, three `docs/howto/acg.md` examples, CHANGELOG, new `scripts/tests/bin/makefile_default_url.bats` (3 tests). Keep the `acg-watch acg-watch-check: URL =` reset.

## 2026-10-06 — make acg-watch targets landed (`4c5df25d`)

Spec `docs/bugs/2026-10-06-acg-watch-make-targets.md` (bug follow-up, not a 6th v1.41.0 plan): `acg-watch` / `acg-watch-stop` / `acg-watch-check`, URL= optional, BATS `scripts/tests/bin/makefile_acg_watch.bats` (7 tests), howto + CHANGELOG. Codex implemented; `.git` denied so Claude committed `4c5df25d`. Verified BATS 7/7, RED 7/7, mutation. Spec gap Codex caught: global `URL ?= .../cloud-playground/cloud-sandboxes` (Makefile:16, stale path) would leak into the watcher — fixed with `acg-watch acg-watch-check: URL =`. `acg-restart` still inherits that stale default (out of scope, unverified whether it matters). Done 2026-10-06: operator ran `make acg-watch` (StartInterval 1800, correct URL), `acg-watch-check` = 193 min, killed the orphaned 3.5h in-process watcher 85368/85372. The stale global `URL ?=` default also reaches `make up` (85368 argv showed cloud-playground); possible follow-up bug spec, not filed.

## 2026-10-06 — ACG watcher fix shipping as lib-foundation v0.5.1 (PR #64)

lib-foundation branch `fix/acg-watch-interval-and-expired-ttl`, spec `25e2b75`. Fix: launchd/acg_watch interval 12600s -> 1800s; `_remainingMinsFromShutdown` reads a time >6h ahead as yesterday (expired). Operator restarted ACG via `make up` 2026-10-06 morning; the installed agent stays at 12600s until the fix is subtree-pulled and reinstalled. Codex done; Claude verified and committed `211a3fd` (pushed). Release PR #64 (v0.5.1) opened 2026-10-06 with docs `d86b452`: CHANGE.md promoted, acg.md watcher section, release tables back-filled v0.3.19–v0.5.1. PR #64 MERGED `cb5575c` 2026-10-06; tag v0.5.1 + GitHub release (Latest) published; subtree pulled into k3d-manager `09e8fe37` (tree equal to v0.5.1; ACG BATS 33/33 + subtree acg.bats green). Remaining: operator reinstalls the launchd agent (`acg_watch_start <url>`) and kills the in-process 3h watcher from make up Step 2 (PID 42997); `make up` 2026-10-06 recovered the expired sandbox via restart at Step 1.


# 2026-10-05 — sudo prompt fix landed (`b3b2542a`); next: e2e order assertion failure

`scripts/lib/system.sh` is now a shim over lib-foundation (bin/*, Makefile, tests get the foundation `_run_command`). Operator to confirm no `Password:` prompt on next `make up` / `refresh-edge`. e2e Failure groups row run `1791168841-15959` = pre-fix run of the order flow-status bug; fix merged (e2e-tests #11 `e5e644d`, image published) — needs a fresh `make e2e`.

# 2026-10-04 — make test 5 reds specced; lib-foundation remote-sudo marker ready for PR

R3 decision (operator): explicit audit exemption, upstream-first. lib-foundation branch
`fix/agent-audit-remote-sudo-marker`: spec `8e339cc2`, fix `5c9b631` (Codex edits; `.git` lock denied,
Claude committed + pushed; shellcheck clean, 27/27 BATS, mutation reds test 9, cmp-restored). PR
#57 MERGED `44e7e8d`; subtree pulled `ce1164eb`. Gap: `.githooks/pre-commit`, `scripts/hooks/pre-commit`,
`scripts/lib/system.sh:29` and `scripts/tests/lib/agent_rigor.bats` all load the stale local fork
`scripts/lib/agent_rigor.sh`, not the subtree, so the marker is not live in k3d-manager yet. Operator chose
retire-the-fork; spec `docs/bugs/2026-10-04-pre-commit-hook-loads-stale-local-agent-rigor-fork.md` — DONE
`e22b7df6` (shim) + `0670b075` (tunnel plain `sudo` + `# agent-audit: remote-sudo`). Codex edits, Claude committed;
Claude verified: shellcheck clean, 23/23 BATS, independent mutation (old fork back) reds both new tests, cmp-restored; make test 5133de03 green (1345/1345 BATS, pytest 621/1 skip);
the live hook accepted the marked sudo on commit 2 (proof the shim loads upstream). Next: full `make test`.
app_health live (healthy at 11:43:35Z).

`make test` at `709aba8d`: 1336/1341. Reds 58 (8 new bare `!`, third recurrence), 197/198 + 1070 (stubs
predate the `3b789adf` jsonpath wait), 972 (keycloak trap count pinned at 2, `d5b986f4` added a third).
All test-only. Spec `docs/bugs/2026-10-04-v1.41.0-make-test-reds-after-sandbox-recovery-fixes.md`.
Codex runs one spec at a time (it cannot write `.git`; Claude commits): make-test reds DONE `9ec4434b`; R1+R2 DONE `98835aac`; app_health DONE `254a291e` (operator: `bin/k3dm-hermes-setup`); full `make test` at `402bd596`: 1342/1342 BATS, pytest 621 passed / 1 skipped.

# 2026-10-04 — Sandbox-recovery fixes landed; review follow-ups; app_health enable spec

Codex landed `f61d3b3b` / `3b789adf` / `d49e5eb8`, Claude-verified (origin, scope, shellcheck, 61/61 BATS,
independent mutation). Review follow-ups appended to the CRD bug doc: R1 (`$!` in the Step 14b warn
expands at print time), R2 (drop the `"su""do"` split from the observability warn). R3: the tunnel wrapper
also splits `"su""do"` for the remote `fuser`; root is genuinely needed (sandbox sshd is non-dumpable), so
the operator decides between an explicit upstream audit exemption and accepting the split. New spec
`docs/bugs/2026-10-04-hermes-app-health-sensor-never-enabled.md`. Next: make test, then dispatch R1/R2 +
app_health to Codex.

# 2026-10-04 — Sandbox recovered; three fix specs dispatched to Codex

Sandbox recovery complete: k3s restart cleared the stuck CRD watch, tunnel kill+kickstart restored 6443,
ArgoCD auto-sync Succeeded, Prometheus 2/2, operator restarted the Step 14b PF (PID 93911), hub
`federate-acg` up=1. Orphan `cluster-up` 1927 killed. Fix specs written in the bug docs (plans are at the
5-spec cap; bugs are exempt) and dispatched to Codex on `k3d-manager-v1.41.0`, three commits:
(1) `docs/bugs/2026-10-03-acg-sandbox-prometheus-crds-missing-from-api-discovery.md` — CRD wait via
`.status.conditions`, discovery WARN, Step 14b svc guard; (2) `docs/bugs/2026-10-04-ssh-tunnel-autossh-reconnect-blocked-by-orphaned-remote-8200.md`
— split `-R 8200` into `com.k3d-manager.ssh-tunnel-vault` with a `fuser -k` wrapper (options 2+3);
(3) `docs/bugs/2026-10-04-cluster-up-exit-trap-kills-port-forwards-it-did-not-start.md` — cleanup kills
only `_ACG_UP_OWNED_PIDS`. Claude verifies SHAs on origin, BATS, scope. Live verify on the next `make up`.


- [x] 2026-10-03 k3dm-tests duration bug filed (`docs/bugs/2026-10-03-k3dm-tests-duration-panel-shows-only-unittest-milliseconds.md`; pulls v1.42.0 §3 offline part forward) — Codex `15f59862` VERIFIED by Claude (7 spec files only; pytest 17 passed; mutation to hardcoded 0 turns 2 tests red, restored green; bats 38/38; dashboard JSON ok; make -n carries --run-duration). Dashboard shows real values only after the next `make test-metrics` + `make observability-acg` (applies the ACG dashboard ConfigMap). LIVE-CONFIRMED 2026-10-03: operator ran both; Pushgateway now holds `k3dm_test_run_duration_seconds{target="test-all"} 440`, pytest suite 83.08s, 2207 cases / 0 failed.
- [x] 2026-10-03 Daily `make test-metrics` launchd stopgap (until v1.42.0): plist `com.k3d-manager.test-metrics` (04:30 daily, log `~/Library/Logs/k3dm-test-metrics.log`) drafted by Claude; install denied to Claude by auto-mode classifier [Unauthorized Persistence] — OPERATOR INSTALLED + kickstarted; first launchd run exit 0, 2207 cases / 0 failed, pushed run_duration 600s, pytest 122s (launchd runs ~35% slower than interactive 440s). Remove when v1.42.0 scheduling lands.
- [ ] 2026-10-03 v1.41.0 features dispatched to Codex ONE AT A TIME, Claude verifies each before the next: (1) find-similar-docs-links — DONE `a4996800` (Claude verified: on origin, 4 scope files, 11+1s / make test-pytest 590+1s, doc-links OK, independent mutation forcing "main" fails the URL test); (2) cloud-bridge round-trip latency bug — `6fc0bc47` pushed (Codex gates: 82 / 599+1s / doc-links OK / 2 mutations); Claude review found a regression (MAX_PER_TICK cap returns own pushed commit as last_tip → requests 11+ stall); follow-up DONE `819e636a` (Claude verified: on origin, 2 files, 68 bridge tests, independent revert-to-break mutation fails the new test); operator restarted 2026-10-03 06:18; live: bridge gap 14 s / 9 s, client round trip ~20 s (was up to ~90 s); Codex cloud session (codex@github) also used it 06:23 — diagnose-apps 7 s, job-status 8 s bridge-side (hand-committed requests, not the helper); old Sep 29 publickey lines still the log tail — log untouched since `docs/bugs/2026-10-03-cloud-bridge-round-trip-latency.md` (adaptive 5s tick, no re-fetch, 5s client poll; operator then `make restart-cloud-bridge`); (3) webhook-log-levels-and-retention — `3f7cf103` M1 / `73d0ef56` M2 / `dc5211de` M3 / `f1d0ec5d` M4 (Claude verified: test-pytest 605+1s, test-python-unit 7 suites OK, cleanup BATS 12/12, shellcheck clean, 0 print(), independent mutation removing ALL redaction fails the token test); review finding: M2 hollowed `test_make_target_passes_timeout_to_transport` (no assertion) → follow-up DONE `cd20fc1b` (Claude verified: on origin, 1 file, test-python-unit 7 suites OK, independent mutation dropping killpg fails the test at 30 s vs <5 s); item 3 COMPLETE — operator to run `make restart-webhook` (restarts bridge too); docs sweep of all v1.41.0 features after the queue (operator ask 2026-10-03); (4) cloud-bridge-e2e-dispatch — split into two runs: part A M1–M6 DONE `a324b6cd` (Claude verified: on origin, 14 files, 100 bridge/capability tests, test-python-unit 7 OK, e2e_remote BATS 81/81, shellcheck clean; independent mutations: capability check→True fails 2 pytest + 3 unittest, dropping lock holder from refusal fails BATS 24; nits: blank line splits the trailers, `removeprefix("make:")` would grant a future non-make route named e2e → fixed in part B; architecture doc lacks cloud-runner token → part B); part B M7–M8 + hardening DONE `c2667b6d` (Claude verified: 8 files, bridge 80 passed, policy unittest OK, independent mutation running slow actions inline fails 1; review: job state `killed` (cluster kill route) is missing from TERMINAL_JOB_STATES → a killed job is watched until timeout+10 min then 'watch expired' — folded into the sandbox spec); item 4 COMPLETE — operator `make restart-webhook` now; operator ask 2026-10-03: let the cloud agent bring the ACG sandbox up/down (not the primary cluster) → spec `docs/plans/v1.41.0-cloud-bridge-sandbox-lifecycle.md` (5th v1.41.0 plan = cap) — DISPATCHED 2026-10-03 (codex-sandbox-lifecycle.log); operator rationale: 4h+ sandbox lets an agent debug without touching live Hostinger; single `make restart-webhook` after it is verified, then operator does the ACG sandbox login (Chrome CDP) so `sandbox-up` can run; operator provisioned Keychain `k3dm-webhook-token-cloud-runner` (account k3dm) 2026-10-03; operator restart-webhook deferred until B verified (shared worktree) (now M1–M8: + M7 slow actions off the serial loop, M8 bridge follows its own jobs → `.final.json` / `--wait-final`); (5) python-agent-rigor (brief A lib-foundation, then B k3d-manager). Sandbox lifecycle DONE `9d527cec` (Claude verified: on origin, 8 files = spec, 83 bridge tests, test-python-unit 7 OK; independent mutation granting any provider fails 8 hostinger/empty/AWS/gcp subtests, cmp-restored). Codex's run wiped Claude's uncommitted memory-bank edits (re-added) — commit memory-bank before a dispatch, never leave it dirty in the shared worktree. NEXT: operator `make restart-webhook`, then a live `sandbox-up` smoke — operator plan 2026-10-03: after the operator's own run completes, the operator asks a cloud agent to run `bin/k3dm-cloud-request --wait-final sandbox-up` (first live use of the cloud-runner lifecycle path); Claude then checks the bridge request/response/.final.json commits and the webhook job. Operator's own `make up CLUSTER_PROVIDER=k3s-aws` 2026-10-03 FAILED: data-layer Application never Synced — hub ArgoCD cannot resolve `host.k3d.internal` (NodeHosts has only the 4 nodes, last written by k3s-supervisor 2026-09-27 hub rebuild). Root cause: `_acg_repair_hub_host_alias` (bin/cluster-up:170) resolves the host IP with `getent`, which rancher/k3s:v1.32.0-k3s1 lacks → empty → WARN + skip, so the repair has been a silent no-op since the rebuild. OrbStack: `nslookup host.docker.internal` in the server container = 0.250.250.254. CloudFormation stack k3d-manager-cluster (us-west-2) left running (billable). Unblocked 2026-10-03: operator patched hub CoreDNS NodeHosts (+`0.250.250.254 host.k3d.internal`); Claude verified busybox nslookup → 0.250.250.254 (~30 s after patch) and `nc -z host.k3d.internal 6443` → TCP_OK from a hub pod; operator to rerun `make up CLUSTER_PROVIDER=k3s-aws`. Hand patch is not durable (k3s rewrites NodeHosts on restart) — code fix (nslookup, not getent; fail loud) still to spec as a docs/bugs/ doc. Rerun 2026-10-03 08:07: data-layer now Synced/Healthy (DNS fix confirmed), but `make up` failed later in `_deploy_pushgateway_acg` (scripts/plugins/observability.sh:736-744): `kubectl apply rules-acg/` ran ~26 s BEFORE ArgoCD (observability-acg AppSet) installed the PrometheusRule CRD on the fresh sandbox (CRD created 15:07:44Z, log last write 15:07:18Z); server dry-run now succeeds. Same class as docs/bugs/argocd-prometheus-operator-unguarded-crd-apply.md, different site — needs a CRD wait (`kubectl wait --for condition=established`) before the apply. Operator to rerun make up (idempotent). Bug doc written 2026-10-03 (operator go): `docs/bugs/2026-10-03-sandbox-make-up-host-alias-and-rules-crd-race.md` — M1 new `scripts/lib/hub_host_ip.sh` nslookup resolver (awk verified on live OrbStack + NXDOMAIN + IPv6 fixtures), M2 cluster-up sources it + fails loud, M3 cluster-refresh (same getent copy) uses it, M4 CRD wait before rules-acg apply. Codex dispatch HELD until no `bin/cluster-up` is running (bash reads the script incrementally; editing it mid-run corrupts the run) — PID 10196 from 07:41 still alive at 08:11 after the reported failure. Sudo prompt during the run = ArgoCD browser HTTPS LaunchDaemon reinstall (wrapper changed); headless runs skip it. No manual ACG login step: operator confirmed 2026-10-03 that `make up` logs in unattended (Keychain `k3dm-acg-pluralsight` auto-login runs before the TTY gate, acg_session_check.js:91-99); how-to corrected.
- [ ] 2026-10-03 QUEUED (operator decision) — cloud-agent sandbox debugging, two separate releases: (1) v1.43.0 (v1.42.0 is already reserved to its 5-plan cap by the Hermes alert-triage scope §5): sandbox-only (`provider=aws`) read-only diagnostics — namespace events, get/describe deploy/svc/ingress/node, logs `previous` + `container` (webhook supports container/tail_lines; the bridge does not pass them); also verify the ACG ApplicationSet values ref tracks the branch a cloud agent pushes to (git push → ArgoCD sync is the agent's only write path). Operator follow-up: "possible to delegate to hermes for investigation and report info (cloud agent <-> hermes)" — Claude proposed building (1) as a Hermes on-demand investigation: bridge action `hermes-investigate` (structured args only, no free text reaching Hermes' LLM) → Hermes runs a fixed read-only evidence bundle on the sandbox context, reusing the v1.42.0 `alert_recipes` engine, + prior art → one report back as a bridge artifact. (2) a LATER release, deep investigation first: a sandbox-bound mutating step (e.g. rollout restart) — natural home is a Hermes Phase-2 allowlisted repair with Slack approval. Awaiting operator's pick on the Hermes route.

- **2026-10-03 sandbox-up hang (third make up run).** `k3sup install` hung from 08:16:59: server node `i-0bf394180ce3a98ba` (t3.medium) saturated (CPU ~64% from 08:04 when monitoring landed, then 96%; SSH banner-exchange timeout, :6443 timeout, EC2 checks ok/ok). Operator reboot did not take within ~8 min; operator ran teardown. Operator: "we need to address this so cloud agent trigger run won't hung forever". Root cause of the unbounded hang: `_run_cluster` waits with `os.waitpid(pid, 0)` (no deadline; 409 blocks sandbox-down), and `_ubuntu_k3s_trust_host` warns and continues into k3sup when SSH never answers. Bug doc `docs/bugs/2026-10-03-sandbox-up-hangs-on-unresponsive-server-node.md` (H1 webhook deadline 3300/1500s < bridge 3600/1800 + SIGKILL escalation; H2 SSH-ready preflight before k3sup + bounded heredoc ssh; H3 howto + CHANGELOG). Follow-up (live, not in fix): measure sandbox memory before/after observability. Codex dispatch pending — together with the host-alias/CRD-race doc; no make up running now.
- 2026-10-04: Hermes Slack-approval make targets committed `2054d058`. Operator set the drain token by hand; remaining: KV binding, `make hermes-approvers APPROVERS=`, `make deploy-worker`, Slack Interactivity, LaunchAgent drain URL (template gap, follow-up spec unanswered).
- 2026-10-04: APPROVALS_KV already existed — bound id ee9eb140… in workers/slack-relay/wrangler.toml; operator reruns `make hermes-approvals-setup APPROVERS=<id>`, then `make deploy-worker`.
- 2026-10-04: setup rerun: KV skipped OK; hermes-drain-token failed 'stored item is too short' — hand-set token < 32 chars (relay rejects it too). Told operator: `ROTATE=1 make hermes-approvals-setup APPROVERS=<id>`.
- 2026-10-04: hermes-approvals-setup SUCCEEDED (ROTATE=1). Guide troubleshooting/recovery added. Next operator: make deploy-worker, Slack Interactivity + /hermes-auth, LaunchAgent drain URL.
- 2026-10-04: operator did deploy-worker + Slack Interactivity//hermes-auth. Gave PlistBuddy Add of K3DM_HERMES_APPROVAL_DRAIN_URL=https://k3dm-slack-relay.k3dm.workers.dev/hermes/approvals to installed plist + bootout/bootstrap; lost on Hermes reinstall until template spec lands.
- 2026-10-04: drain URL set by hand + verified. Spec filed to put it in the LaunchAgent template (opt-in = drain token present); Codex dispatched.
- 2026-10-04: spec filed for index-docs local embedding cache; Codex dispatch queued behind the drain-URL task (same working tree).
- 2026-10-04: drain-URL template change verified + committed; index-docs cache spec now dispatching to Codex.
- 2026-10-04: queued spec for a second copy of the embedding cache (backup/restore targets); dispatch after the embed-cache Codex task is verified.
- 2026-10-04: folded integrity metadata/stats/prune into the second-copy spec (not into the in-flight Codex run).
- 2026-10-04: Grafana question → found Hermes never re-indexes a rebuilt store; spec filed; queue: embed-cache (Codex running) → this → second-copy/metadata.
- 2026-10-04: re-index + dashboard verified and committed (Codex + 2 Claude fixes). Next: dispatch `docs/bugs/2026-10-04-embedding-cache-has-no-second-copy.md` to Codex.
- 2026-10-04: second-copy/metadata spec — Codex done, Claude verified + fixed prune-wipes-legacy-rows defect; committed on k3d-manager-v1.41.0.
- 2026-10-04: specs filed + dispatched to Codex together: embed-cache seed-from-store, Hermes quota pause → Pacific reset. Hermes currently paused until 17:00 PDT (will re-pause to tomorrow 17:00 until fixed).
- 2026-10-04: embed-cache verified + committed. Next dispatch: hermes-index-refresh-ignores-a-rebuilt-store, then embedding-cache-has-no-second-copy.
- 2026-10-04: seed-from-store + Pacific quota reset — Codex done, Claude verified (654 pytest, 3 mutations red, howto reworded), committed + pushed on k3d-manager-v1.41.0. Operator next: `make embed-cache-seed`, then `make embed-cache-backup DEST=…` after Hermes finishes post-reset.
- 2026-10-04: operator ran `make embed-cache-seed` → 1693 seeded, 1 unmatched. Spec filed for remote backup (`DEST=host:path` via scp); dispatching to Codex.
- 2026-10-04: remote embed-cache backup (`DEST=host:path`) — Codex done, Claude added retries + keepalives (operator: M4↔M2 link drops) and fixed scp path quoting; committed + pushed. Operator: `make embed-cache-backup DEST=m2-air.local:~/.local/backup`.
- 2026-10-04: operator ran `make embed-cache-backup DEST=m2-air.local:~/.local/backup` → 1693 vectors on the M2. Re-run after the post-reset Hermes index.
- 2026-10-04: python-agent-rigor brief A specced in lib-foundation (`cbc73bd`, branch `feat/agent-audit-python`) and dispatched to Codex. Brief B (k3d-manager M2–M4) follows after A merges.
- 2026-10-04: brief A DONE `45b9326` on lib-foundation `feat/agent-audit-python` (Claude verified: 4 files, BATS 156/156, shellcheck clean, independent mutation red). PR prepared, waiting on the operator go; v0.5.0 tag after merge, then brief B.
- 2026-10-04: opened wilddog64/lib-foundation#58 (brief A) on the operator go; Copilot requested; CI running.
- 2026-10-04: lib-foundation#58 CI green; added README `_agent_audit` section `af9e534` (operator go). Copilot review not in yet. Brief B must include k3d-manager `docs/howto/agent-audit.md`.
- 2026-10-04: lib-foundation#58 MERGED `dd39a90`. Rulesets only (deletion, non_fast_forward, copilot_code_review), no protection to restore. v0.5.0 untagged: CHANGE.md [Unreleased] holds #57 + #58; promote PR (precedent #51) pending operator go. Next: brief B.
- 2026-10-04: lib-foundation `release/v0.5.0` prepared `2004c7d` (CHANGE.md promote only, precedent #51); PR NOT opened, awaiting operator go. README/docs/releases.md release tables stale since v0.3.17 (no v0.4.x rows) — flagged, not fixed.
- 2026-10-04: opened lib-foundation#59 (v0.5.0 promote) on operator go; Copilot requested.
- 2026-10-04: lib-foundation v0.5.0 RELEASED — #59 merged `b6afd07`, annotated tag v0.5.0 -> b6afd07, GH release live (notes = CHANGE.md [v0.5.0]); retro `e247525` on `docs/v0.5.0-retrospective`. NEXT: brief B — subtree pull v0.5.0 into k3d-manager (`K3DM_SUBTREE_SYNC=1`) + spec M2–M4 + `docs/howto/agent-audit.md`.
- 2026-10-04: brief B started — subtree pull v0.5.0 `c34c5bcb` (0 dangerous-call hits in current non-test Python, 96 Python files); spec `0ab5dc6c` (section of the existing plan; M2 scoped to tripwire's gaps: bare pytest, absolute paths, sockets, remote git; >15 offenders → stop at report mode); dispatched to Codex.
- 2026-10-04: brief B DONE — 4 commits `967b1636`..`a027c70a` pushed; Claude fixed 2 Codex defects (removed webhook re-exports broke test-python-unit; missing `RUFF ?= ruff` would fail CI). Python agent-rigor milestone complete; CI (PR-only trigger) first exercises the new steps at the v1.41.0 PR. Follow-up: hermetic git check misses `git -C dir fetch`.
- 2026-10-04: filed `docs/bugs/2026-10-04-hermetic-guard-misses-git-global-options.md` (guard misses `git -C`/`-c` global options, absolute `/usr/bin/git`, named non-origin remotes; dedup: no slug match, find-similar-docs down on embed quota 429). Dispatched to Codex.
- 2026-10-04: hermetic git-options fix DONE + verified (Claude fixed `cwd=None` regression Codex mislabelled pre-existing; stubbed `_sms_keychain` in test_pager, a real Keychain read the guard exposed).
- 2026-10-04: bug-doc status sweep — 12 docs said OPEN/SPEC but were fixed (make-test reds, app_health, exit trap, ssh-tunnel 8200, sandbox-up hang, host alias/CRD race, ACG SMS→email, LDAP component lookup, promoter override, credential drift, payment Netty, image-promotion newTag); status lines corrected, docs only. Still open: root-owned logs (argocd.sh:83, unspecced), sandbox Prometheus CRD discovery root cause, e2e-harness-dispatch (reopened), hub self-registration duplicate name (owner decision), payment e2e gatewayTransactionId (Java fix 4169430 merged in #80, e2e green not recorded), deploy-worker keychain msg (backlog).
- 2026-10-04: open-bug specs. Hub self-registration doc was stale (FIXED `ac3ebb82` 2026-09-24), status corrected. Specs appended for Codex, dispatched serially in priority order: (1) root-owned logs (argocd.sh:82-83 defaults removed + cluster-up root-owned preflight), (2) e2e dispatch (M2 CPU gate on mean of 5 samples + retry capacity_* refusals), (3) deploy-worker keychain message (`KEYCHAIN_READ`/_kc_read helper). Prometheus CRD discovery root cause NOT Codex-able (needs a live sandbox; k3s pinned v1.32.0+k3s1). Payment e2e rerun (#4) after these.

- 2026-10-04: root-owned-logs fix (Codex) verified by Claude — bats 52/52, shellcheck no new warnings (31=31, 0=0), both mutations red then cmp-restored; no root-owned dirs in live state. Next: e2e dispatch CPU gate spec dispatched to Codex.
- 2026-10-04: e2e dispatch CPU gate (Codex) verified by Claude — 3 files in scope, shellcheck 0=0, e2e_remote.bats 87/87, negation lint ok; Claude mutations red: min-instead-of-mean → "mean CPU" + "dipped sample" tests, retry-every-refusal → "does not retry busy" test; cmp-restored. Commit held until the operator's make e2e (vCluster e2e-1791168841-15959) finishes.
- 2026-10-04 20:08 make e2e run 1791168841-15959: 91 passed, 8 failed (all flows/order-management.spec.ts, CONFIRMED/DELIVERED not in Go enum). Payments green, gatewayTransactionId bug closed. e2e CPU-gate fix committed after the run.
- 2026-10-04 20:20 deploy-worker keychain spec dispatched to Codex (codex exec, unstaged edits expected in Makefile + 3 bats files).
- 2026-10-04 deploy-worker keychain fix verified and committed. makefile_hermes_approvals.bats tests 8/11 red at HEAD since 42c51bf8 bound APPROVALS_KV in the real wrangler.toml: filing a bug.
- 2026-10-04 filed + dispatched hermes-approvals-kv fixture bug to Codex.
- 2026-10-05 Hostinger status FAIL: frontend-browser-http root daemon + pushgateway PF were rewritten to ubuntu-k3s by the Oct 3 sandbox make up; sandbox dead. Bug filed; workaround handed to operator. PR #11 Copilot fixed (6631f64).
- 2026-10-05 e2e-tests PR #11 merged (e5e644d) via --admin; enforce_admins re-enabled (verified true); local main synced. fix/ branch, [Unreleased] only — no tag. Auto-mode classifier denied Claude the enforce_admins DELETE ([CI Bypass]); operator ran it. Next: image rebuild + pin + make e2e (#4).
- 2026-10-05 Hostinger workaround applied; make status HEALTHY. Launchd-label collision fix spec appended to docs/bugs/2026-10-05-sandbox-make-up-hijacks-hostinger-launchd-labels.md (Option A: sandbox-scoped labels, 127.0.0.3, pushgateway 9092; refresh-edge owns frontend plist; cluster-down guarded legacy cleanup); dispatched to Codex.
- 2026-10-05 Hermes data_layer TimeoutError root-caused: stale active-provider=k3s-aws (expired sandbox) → webhook /api/v1/health probes dead ubuntu-k3s (98–159s). Recurrence + spec (pin K3DM_HERMES_PROVIDER=k3s-hostinger) appended to docs/bugs/2026-06-24-hostinger-provider-switch-stale-active-provider.md; queued for Codex after the launchd-scope task. app_health shows healthy in the Hermes log since 2026-10-04 11:43 — the operator's view is stale (source TBD).
- 2026-10-05 Launchd-scope fix verified + committed (see bug doc status). Hermes provider-pin Codex task running.
- 2026-10-05 Hermes provider pin committed; operator to rerun bin/k3dm-hermes-setup.
- 2026-10-05 Open follow-ups specced and dispatched to Codex: (1) Recurrence 4 in docs/bugs/2026-06-24-hostinger-provider-switch-stale-active-provider.md — Makefile status, bin/cluster-status-summary and webhook _resolve_provider trust the active-provider marker without a liveness check (bash _acg_resolve_provider already probes; it was mislabeled as the gap); (2) cluster-down legacy-cleanup dry-run test, follow-up in docs/bugs/2026-10-05-sandbox-make-up-hijacks-hostinger-launchd-labels.md (keycloak/argocd labels closed: hub-only, no collision; status mismatch flag closed); (3) lib-foundation branch fix/agent-audit-sudo-flag-false-positive, spec 46813d8 (Recurrence in 2026-10-04 bare-sudo doc): `\bsudo` matches `--interactive-sudo`.
- 2026-10-05 lib-foundation sudo-flag false positive FIXED 16908e5 + docs a2115d1 (Claude-verified 46/46 + mutation); PR being created (Haiku Phase 1). The earlier uncommitted memory-bank lines were lost while the k3d-manager Codex run was active — restated here.
- 2026-10-05 lib-foundation PR #60 open (head a2115d1): CI green (shellcheck/bats/acg), Copilot reviewed with 0 findings, 0 unresolved threads, CLEAN. Ruleset repo — no enforce_admins lever. Awaiting operator merge, then subtree pull (with v0.5.0). Frontend plist still 3-arg: refresh-edge needs Terminal.app (sudo). Webhook restarted (pid 25885).
- 2026-10-05 Stale-marker liveness (Recurrence 4) + cluster-down dry-run test: Codex, Claude-verified (BATS 45/45, pytest 35/35, 3 independent mutations red, cmp-restored). Operator: `make restart-webhook` to load the webhook resolver; refresh-edge from the `!` shell could not sudo (no TTY), rerun in Terminal.app.
- 2026-10-05 PR #60 MERGED c6876cc; subtree-pulled into k3d-manager 58f27f48 (agent_rigor bats 46/46). refresh-edge rerun in Terminal.app: frontend plist now 2 args (~/.local/share/k3d-manager/bin/frontend-browser-http.sh), 127.0.0.2 → 200.
- 2026-10-05 make up failed exit 127 at step 1: cdp.sh:162 `_antigravity_browser_ready: command not found` — cdp.sh guard sources foundation system.sh only if `_run_command` is undefined; k3d-manager system.sh defines it, so the helper never loads (launch branch only). Spec lib-foundation b731f14 on fix/cdp-browser-ready-host-load (docs/bugs/2026-10-05-cdp-browser-launch-missing-ready-helper-under-host.md), dispatched to Codex. Rerun of make up reused Chrome and got past step 1.
- 2026-10-05 Alert-email deep dive (48h ALERTS history, hub + Hostinger). Not flapping: five distinct defects, each filed + dispatched to Codex in one run:
  - `docs/bugs/2026-10-05-argocd-cve-scan-exits-nonzero-when-no-newer-chart.md`: nightly KubeJobFailed, the scan runs 3x and the 1h TTL "resolves" it.
  - `docs/bugs/2026-10-05-offline-tests-rotted-on-v1-41-0.md`: two tests rotted by our own commits. `hub_pushgateway.bats:52` by `4547e696`, `make_lifecycle.bats:17` by `435c95a1`. This caused Hostinger OfflineSuiteFailing; CaseCountDropped is the same root cause (make stopped before test-bin/pytest).
  - `docs/bugs/2026-10-05-nightly-test-metrics-push-failure-is-silent.md`: the 10-04 red run was lost to a Connection refused on :9091. New `OfflineSuiteRunMissed`.
  - `docs/bugs/2026-10-05-hub-trivy-scans-ephemeral-vcluster-pods.md`: hub excludes `vclusters`.
  - `docs/bugs/2026-10-05-e2e-alert-refires-on-exporter-rollout.md`: `max by` + `exported_service`.
  - Not bugs: E2EVerificationFailing = known order-status run (clears with #4). VectorDBIndexDrift = 10-03/04 embed quota, already fixed.
- 2026-10-05 Alert fixes LANDED `536454bc` (Codex, Claude-verified: new tests RED at HEAD, old rot tests RED at HEAD, 4 independent mutations red + cmp-restored, make test 1362/1362, test-bin 314/314). Live on the next ArgoCD sync (hub platform-ops + trivy-operator); OfflineSuiteRunMissed needs `make observability-acg` on the next sandbox.
- 2026-10-05 `make up` FAILED at Step 10 (ArgoCD controller restart timed out). Root cause: hub agent-0 `k3s agent` at 7.8 GB RSS (others ~114 MB), kube-proxy sync stalled ~35 min, so kube-dns DNAT missing on agent-0 after `_acg_repair_hub_host_alias` restarted CoreDNS (new endpoint IP). Operator `docker restart k3d-k3d-cluster-agent-0`: RSS 172 MB, kube-dns rules back, controller 2/2, no stale host-network IPs. Issue doc `docs/issues/2026-10-05-hub-agent-0-k3s-agent-memory-wedges-kube-proxy.md` (RSS sampling for growth rate before speccing an alert). Bug spec `docs/bugs/2026-10-05-cluster-up-coredns-restart-strands-argocd-controller.md` (skip when alias present, drop the CoreDNS restart; hosts plugin reloads) -> Codex.
- 2026-10-05 Sandbox torn down (CFN k3d-manager-cluster deleted, ubuntu-k3s context gone, hub kept). Claude's `make -n down CLUSTER_PROVIDER=k3s-aws` executed the recipe (`$(MAKE)` line) — never `make -n` a lifecycle target.
- 2026-10-05 CoreDNS-restart fix verified (Codex impl; early return when alias present, restart removed) and committed. Proposed next: `make down` guard should not count long-lived k3s-hostinger (awaiting go).
- 2026-10-05 Operator approved the `make down` guard fix; spec filed (scoped to MAKE_TARGET=down, since bare `make status` resolves to Hostinger first) and dispatched to Codex.
- 2026-10-05 `make down` guard fix committed: bare `make down` ignores long-lived k3s-hostinger; hub-rebuild how-to updated (bare down no longer a safety net there).
- 2026-10-05: ACG extend 'never works' diagnosed — 1st watcher extend succeeds; 2nd wake (~7h) hits ACG's one-extension cap, no button, misleading ERROR. Spec lib-foundation docs/bugs/2026-10-05-acg-watch-retries-extend-after-one-extension-cap.md on branch fix/acg-watch-one-extension-cap (810a4b1, pushed); dispatched to Codex. Needs subtree pull + watcher restart after merge. Side risk noted: acg_extend.js Ghost State recovery deletes+restarts the sandbox when <15m remain and no button.
- 2026-10-05 CORRECTION: one-extension-cap theory is likely WRONG — after the 44m failure the SAME sandbox (creds still valid) had 106m left at the next make up, so it was extended again. Codex dispatch stopped (no changes kept). Real suspect: acg_extend.js checks for the button with a 0ms timeout BEFORE the TTL check; when not instantly visible it falls into the 'Open Sandbox' path, which has had no Extend button since the 2026-05-15 UI redesign. lib-foundation spec 810a4b1 must be rewritten. Awaiting operator: was the sandbox extended manually after the error?
- 2026-10-05 ACG extend re-diagnosed (supersedes the cap spec; old branch fix/acg-watch-one-extension-cap abandoned): (A) acg_extend.js only checks for the button with a 0ms snapshot, then uses Open Sandbox (no button since the redesign); (B) the launchd watcher com.k3d-manager.acg-watch has NEVER worked — its wrapper calls scripts/lib/foundation/scripts/k3d-manager (nonexistent), and launchd PATH has no node; (C) acg_watch waits 3.5h after a failure. New spec lib-foundation docs/bugs/2026-10-05-acg-extend-never-waits-for-button-and-launchd-wrapper-dead.md, branch fix/acg-extend-wait-for-button. Plan: Codex -> verify -> PR (go) -> merge -> subtree pull -> operator reinstalls the launchd job (acg_watch_start) -> watch the next wake live.
- 2026-10-05 make up FAILED at Step 10g: ifconfig lo0 alias 127.0.0.3 permission denied (sudo not cached). Root cause: the call uses --prefer-sudo without --soft, so _run_command exits and the || _warn never runs. Spec docs/bugs/2026-10-05-frontend-loopback-alias-aborts-cluster-up.md. Operator unblock: sudo /sbin/ifconfig lo0 alias 127.0.0.3, then make up again. Also seen this run: istio-ambient generic-CNI-dirs WARN (ApplicationSets are deployed before Step 10 registers the target; check the live ApplicationSet), and 'ArgoCD controller did not reconnect to ubuntu-k3s within 120s'.
## 2026-10-06 — v1.41.0 release PR opened (#135)

PR https://github.com/wilddog64/k3d-manager/pull/135 is open from
`k3d-manager-v1.41.0` to `main`; branch was clean and pushed at `d7ee5520`.
GitHub Actions are in progress. The required Copilot reviewer request returned
no requested reviewer and `gh pr view --json reviewRequests` confirmed `[]`.
This is recorded in `docs/issues/2026-10-06-v1-41.0-pr-copilot-request.md`.
## 2026-10-06 — Ubuntu CI plist test portability bug fixed

PR #135 lint failed at BATS test 313 because `sandbox_launchd_scope.bats` used
macOS-only `plutil` on `ubuntu-latest`. Filed
`docs/bugs/2026-10-06-sandbox-launchd-test-requires-macos-plutil.md` and replaced
the assertion with Python `plistlib`. Focused suite is 8/8 and `make test-bin`
is 328/328; expected tripwire notices still block three Keychain probes without
reaching real tools.
## 2026-10-06 — Ubuntu CI follow-up portability bug fixed

The next lint run exposed two more failures in `hub_restore.bats`: BSD/macOS
`script` argument ordering caused tests 150 and 151 to lose their expected rc=2
under Ubuntu. Added a dialect-detecting `_run_with_tty` helper. `hub_restore.bats`
is 14/14 and `make test-bin` is 328/328; pushed in the follow-up commit below.
## 2026-10-06 — Ubuntu `script` exit propagation fixed

The follow-up lint run still failed tests 150 and 151 because GNU `script`
requires `-e`/`--return` to propagate the child command's rc. Added that flag
to the GNU dialect branch while retaining the macOS fallback. Local
`hub_restore.bats` is 14/14 and `make test-bin` is 328/328.
## 2026-10-07 — direct test-all Grafana publication fixed; Hostinger status transient recorded

Filed `docs/bugs/2026-10-07-test-all-does-not-publish-grafana-result.md` and fixed `make
test-all` so it streams/captures the complete offline run, publishes pass/failure metrics once
through `bin/k3dm-test-metrics`, and preserves the original exit code. `make test-metrics` remains
an always-zero compatibility wrapper. Cloud webhook lifecycle publication skips a duplicate when
the Make target already reports a successful push. Also recorded the non-reproduced Hostinger
ESO/data-layer status report in `docs/issues/2026-10-07-hostinger-status-transient-eso-data-layer.md`.
Current recheck: `make status CLUSTER_PROVIDER=k3s-hostinger` healthy; ClusterSecretStore ready,
ExternalSecrets all synced, PostgreSQL/MinIO 1/1. Commit `c67c3a9a` is pushed to
`origin/k3d-manager-v1.42.0`; no PR was created per repository instructions.
## 2026-10-07 — v1.35.0 health-probe diagnostics enhancement specified

Added `docs/plans/v1.35.0-health-probe-diagnostics.md` as a proposed observability enhancement.
It specifies structured probe outcomes, preserved exit/timeout state, bounded redacted stdout and
stderr, stable reason categories, consistent Slack/JSON rendering, and tests for empty output,
malformed JSON, timeouts, missing CRDs, valid ESO readiness, and data-layer readiness. No runtime
code changed; the plan is the first v1.35.0 plan.
## 2026-10-07 — Slack cluster-status and cluster-diagnose threading fixed

Filed `docs/bugs/2026-10-07-slack-cluster-diagnostics-not-threaded.md` and unified status and
diagnostics delivery through the thread-aware Slack helper. Existing thread commands now reply to
the incoming `thread_ts`; top-level commands retain the parent-header/details-thread layout, and
response-URL fallback remains for channel mismatch or unavailable bot delivery. Focused status,
diagnostics, masking, and pod tests passed 54/54; Python compilation, `git diff --check`, doc
links (1955 files), and `_agent_audit` passed. Runtime commit pending.

## 2026-10-07 — k3dm Tests Grafana no-data fix live-verified

The live no-data issue included duplicate Argo ownership: ACG and hub both managed
`k3dm-test-metrics`, and the ACG copy overwrote the hub dashboard. ACG now excludes the
hub-owned dashboard. Hub Argo is `Succeeded Synced Healthy`; the live ConfigMap uses UID
`prometheus`; the scrape target `host.internal:9091` is up; and Prometheus returned
`k3dm_test_cases_total=2501`. Commit pending.

## 2026-10-07 — v1.44.0 cloud-request Slack routing specified

Added `docs/plans/v1.44.0-cloud-request-slack-notification-routing.md`. The proposal uses
server-controlled notification aliases, validates them before queueing, stores only the alias,
keeps the route fixed for the job lifetime, preserves the default channel, and fails closed on
invalid configuration or delivery failure. No runtime changes.

## 2026-10-07 — v1.44.0 cloud-request submitter authentication specified

Added `docs/plans/v1.44.0-cloud-request-submitter-authentication.md`. The proposal treats branch
write access as transport only and adds Ed25519-signed canonical request envelopes, protected
agent/key capabilities, replay and expiry checks, revocation, migration modes, and audit metadata.
No runtime changes.

## 2026-10-07 — test-all failing-suite table clarified

The cloud `make-test-all` job `195eff6a` published metrics but failed. The bounded failure context
identifies observability BATS cases 198 and 200; complete cloud diagnostics are not available, so
root cause remains unconfirmed and is recorded in `docs/issues/2026-10-07-cloud-test-all-observability-failures.md`.
Updated the k3dm-tests Grafana panel to an instant, transformed table with human-readable
`Test suite`, `Result`, `Failed cases`, and `Target` columns. Focused dashboard tests pass; live
dashboard sync is pending.

## 2026-10-07 — cloud test failure detail and log context improved

The next cloud `make-test-all` report showed 1,383 cases and 34 failures; the bounded response
identified observability BATS cases 198 and 200 as the first actionable failures. Case 198 was
not hermetic after newer ServiceMonitor/API-server scrape helpers were added, and case 200 could
depend on host `htpasswd` while testing the Vault fallback. The focused fixtures now stub those
unrelated dependencies and deterministic bcrypt generation.

`bin/k3dm-test-metrics` now emits bounded `k3dm_test_failure` records containing target, suite,
case number, test name, and first diagnostic reason. The Grafana panel is now an instant table
with human-readable `Test suite`, `Case`, `Test name`, `Failure reason`, and `Target` columns.
Failed cloud responses retain multiple failure summaries plus the final tail within the existing
2,000-character bound and redaction path. Findings are recorded in
`docs/issues/2026-10-07-cloud-test-failure-detail-and-log-context.md`.

Verification: observability BATS 18/18; Grafana dashboard contract BATS 36/36; Python unit
bundle completed with 7/12/33/27/6/6/4 tests all OK; metrics/cloud-log smoke checks, Python
compilation, and `git diff --check` passed. Full cloud rerun is still needed to confirm the
aggregate 34 failures are cleared. Commit and live deployment pending.

## 2026-10-07 — Slack status channel fallback fixed

The operator captured a live `/cluster-status` response posted as one top-level message. Review
found the status helper only considered the configured Slack channel eligible for bot delivery;
an event from another channel fell back to a non-threaded response. Status delivery now uses the
incoming channel for both new status threads and replies to existing threads, while retaining the
empty-channel response-URL fallback. Regression coverage was added in
`scripts/tests/bin/test_webhook_cluster_status_thread.py` and the finding is recorded in
`docs/issues/2026-10-07-slack-status-channel-fallback-not-threaded.md`. Commit pending.

## 2026-10-07 — cloud Make response now exposes exit code

Cloud job `470f0304` returned failure status and detailed bounded diagnostics but omitted the
numeric exit code from both the body and summary artifact. The webhook persisted status/logs but
not the Make return code, so cloud-bridge had nothing to relay. Make jobs now persist `exit_code`
and `/api/v1/status/{job_id}` includes the integer while the existing summary artifact contract
stays unchanged. Finding recorded in
`docs/issues/2026-10-07-cloud-job-response-missing-exit-code.md`. Commit pending.

## 2026-10-07 — transient ESO status report recorded

A Slack screenshot reported empty/non-JSON ESO probe output and two data-layer readiness failures,
but the subsequent read-only `make status-full CLUSTER_PROVIDER=k3s-hostinger` check returned
`ESO ClusterSecretStore: Ready=True`, `ESO ExternalSecrets: 20/20 synced`, hub ESO `9/9 synced`,
`Data layer: 4/4 ready`, and `Overall: HEALTHY`. This is recorded in
`docs/issues/2026-10-07-cluster-status-eso-empty-output-and-thread-followup.md`; no live ESO
remediation was performed. The screenshot still does not prove the channel-aware threading fix
because no matching status job metadata was present locally.

## 2026-10-07 — cloud failure classification made explicit

Filed `docs/bugs/2026-10-07-cloud-failure-classification-missing.md`. Cloud terminal responses and
summary artifacts now distinguish `passed`, `failed_untriaged`, and `in_progress` while retaining
the authoritative original status and exit code. This prevents a locally passing focused rerun
from being mistaken for proof that the original cloud failure was harmless.

## 2026-10-07 — cloud hub snapshot failures not locally reproducible

Cloud job `5cda3d09` reported six failures, including five `hub_snapshot.bats` cases sharing the
snapshot capture setup. The focused local suite passes 14/14, so no production patch is justified
without the cloud assertion diagnostics. Findings and the exact local TAP output are recorded in
`docs/issues/2026-10-07-cloud-hub-snapshot-suite-failures.md`; next action is a focused cloud rerun
with complete output.

The complete local BATS dispatcher subsequently passed all `1,384` cases, including cloud cases
198, 970, 971, 972, 974, and 981. No code change was made because the reported failures remain
cloud-only and lack assertion diagnostics.

## 2026-10-07 — test dashboard freshness semantics fixed

Filed `docs/bugs/2026-10-07-test-dashboard-freshness-aggregation.md`. Grafana freshness panels
were evaluating raw Pushgateway vectors, exposing scrape labels and potentially selecting an
ambiguous stat value. They now use instant `max(...)` queries. The exporter also only writes the
last-success timestamp when both parsed failures and Make exit code are zero. Metrics regression
tests passed `21`; the Grafana dashboard contract passed `37/37`; compilation, lint, audit, and
diff checks passed. Commit `ea896a3d` is pushed, and the live hub dashboard is `Synced Healthy`
with both freshness panels verified as instant `max(...)` queries.

## 2026-10-07 — successful-run panel label clarified

Renamed the Grafana panel from `Last passing run` to `Last successful run` to make its meaning
explicit. The dashboard contract test now guards the label. Commit `1aea506b` is pushed, and the
live ConfigMap verifies `Last successful run` with ArgoCD `Synced Healthy`.

## 2026-10-07 — stale failed-case metrics fixed

The latest `make test-all` published `2,509` cases with `2` failures, but Grafana mixed current
and older failed-case rows. Filed `docs/bugs/2026-10-07-test-metrics-stale-failure-series.md`.
The exporter now uses Pushgateway `PUT` replacement semantics, so omitted old failure series are
removed. Updated the metrics label contract to preserve human-readable names and restored the
safe Slack response-URL fallback for a new thread when the supplied channel mismatches the
configured channel. Elevated pytest verification passed `702 passed, 2 skipped`; Grafana
dashboard BATS passed `36/36`; compilation, lint, audit, and diff checks passed. Commit
`b5c8ca6a` is pushed to `origin/k3d-manager-v1.42.0`.

## 2026-10-07 — test-run classification published to Grafana

Added `k3dm_test_run_classification` to the test metrics payload. It publishes `passed` only for
Make exit code 0 and `failed_untriaged` for any nonzero terminal exit code, while preserving the
raw `k3dm_test_exit_code` metric. Grafana panel 7 now shows the classification and explains its
meaning, so the next `make test-all` metrics push can be verified without treating every failure
as a confirmed defect. Focused dashboard tests (36/36), Python unit target, compilation, smoke
check, lint, audit, and diff checks passed. Commit `9bf7898f` is pushed; ArgoCD reports the hub
dashboard `Synced Healthy`, and the live `k3dm-test-metrics` ConfigMap contains the new panel.
## 2026-10-07 — test dashboard clean-run state clarified

Live metrics show the latest test-all run passed with zero failed cases, so Suite freshness and
Last successful run intentionally display the same elapsed age. Clarified the failure table as
`Failing test cases (latest run)` and documented that `No data` means the latest run has no
failed-case details; operators should confirm `Failed cases` is 0. Dashboard contract tests pass
37/37. Dashboard source commit `c2009c06` is pushed; `make observability` completed and Argo
reports `Synced Healthy`. The live ConfigMap now has the clarified title and description.
## 2026-10-07 — dashboard elapsed-time labels clarified

Verified live Pushgateway data: latest and last-success timestamps are both `2026-10-07
16:02:42 PDT`, classification is `passed`, and failed cases are `0`; the matching 43-minute
values are therefore correct. Renamed the stat panels to `Time since latest run` and `Time since
last successful run` so the displayed elapsed duration cannot be mistaken for a timestamp.
Dashboard contract tests pass 37/37; live rollout pending.
## 2026-10-07 — latest-run dashboard semantics corrected

The operator clarified that `Last run` must remain a fixed run timestamp, while `Time since last
successful run` should continue increasing until a newer successful build. Panel 1 now queries
`max(k3dm_test_last_timestamp_seconds)` with an absolute ISO datetime unit; panel 2 retains the
elapsed-time query. Dashboard contract tests pass 37/37. Live rollout pending.
## 2026-10-07 — fixed latest-run epoch display

The first absolute timestamp rollout displayed January 1970 because Grafana's `dateTimeAsIso`
unit expects milliseconds while the Prometheus metric is in seconds. Recorded the finding in
`docs/issues/2026-10-07-grafana-latest-run-epoch-unit.md`; the query now multiplies by `1000`.
Dashboard contract tests pass 37/37. Live rollout pending.
## 2026-10-07 — P1 stale sandbox cleanup reporting fixed

Fixed `cleanup-stale-sandbox`: preview/apply help now matches parser behavior, cleanup reports
stopped/removed/already-absent/failed resources, preserves real command errors, and returns
nonzero for incomplete cleanup. The webhook now persists terminal status, exit code, and bounded
redacted output for status/log retrieval. Focused cleanup tests pass 4/4, webhook lifecycle
tests 8/8, and Slack relay tests 36/36. Live Slack verification remains pending.
## 2026-10-07 — Slack cleanup thread context fixed

The cleanup slash relay dropped Slack `thread_ts`, so a follow-up `cleanup-stale-sandbox apply`
message could not reliably associate with the originating cleanup job. The relay now forwards
the thread timestamp, the webhook persists it, and thread dispatch validates preview/confirm/apply
arguments. Slack relay tests pass 37/37; cleanup BATS 4/4 and webhook cleanup pytest 2/2 pass.
Worker deployment completed as Cloudflare version `6c4509c9-6567-4113-bbcb-b2cc9cd3ed0a`; the
signed health probe returned HTTP 200. Operator thread verification remains pending.
## 2026-10-07 — Slack authorization failures now reply in-thread

Live logs showed cleanup follow-ups were rejected before dispatch because Slack user
`U0B89H45SUA` was absent from the webhook role map. Added a generic denial reply for recognized
commands from unallowlisted users; authorization remains fail-closed. Focused authorization
guard test passes 1/1; full webhook BATS remains blocked by unrelated local connection-refused
fixtures. Role-map configuration still needs the operator's explicit update.
## 2026-10-07 — Slack cleanup notification fallback added

The cleanup job persisted the correct `thread_ts` and completed, but the bot notification path
could fail silently when its configured channel/thread target was unavailable. `_notify_job` now
falls back to the stored Slack response URL with the same thread timestamp. Webhook cleanup tests
pass 3/3; live Slack verification remains pending.
## 2026-10-07 — Slack response URL preferred for job replies

The cleanup job's bot post could return success while targeting the webhook's configured channel,
not the command's channel. `_notify_job` now prefers the stored Slack response URL with its
`thread_ts`, using bot posting only as fallback; response posting returns success/failure instead
of being silent. Webhook notification tests pass 4/4; live Slack verification remains pending.
## 2026-10-07 — cleanup now creates threads for top-level Slack commands

Unlike status/diagnostics, cleanup previously used only the slash response URL and did not create
a bot thread when invoked at channel level. The relay now forwards `channel_id`; the webhook
creates a thread for top-level cleanup requests and retains existing thread context. Webhook
cleanup tests pass 5/5 and Slack relay tests 37/37. Cloudflare worker version
`d44059a2-964b-47d8-8a7b-7e4390b7b623` is deployed; live Slack verification remains pending.
## 2026-10-07 — top-level cleanup completion now posts into created thread

The latest retry proved the top-level bot thread was created, but completion still used the
response URL and appeared at channel level. Newly created cleanup threads are now marked as bot
threads and completion uses `chat.postMessage` with the originating channel/thread; response URL
remains fallback for existing incoming threads. Webhook tests pass 6/6; live verification pending.

## 2026-10-07 — three Slack thread command routes implemented

Added event routing for `cluster-diagnose`, `k3dm`, and `argocd-upgrade` in top-level messages,
orphan threads, and existing job threads. Child jobs inherit the originating Slack thread and
channel; ArgoCD upgrade jobs now post terminal status/output. Focused Python tests pass 55 tests
and 90 subtests; Slack relay Node tests pass 37/37. Combined webhook BATS remains blocked by
connection-refused fixture startup, documented in `docs/issues/2026-10-07-slack-thread-routing-validation.md`.
Live Slack verification and webhook restart remain pending.
Implementation commit pushed: `b5cf7272`.

## 2026-10-07 — ArgoCD infra upgrade confirmation gate

Filed and fixed `docs/bugs/2026-10-07-argocd-infra-upgrade-needs-confirm.md`. The Slack relay,
webhook thread dispatcher, and direct API now require explicit confirmation for `infra`; `acg`
remains confirmation-free. Focused webhook tests pass 17/17 and Slack relay tests pass 38/38.
Live deployment/restart remains pending.
Implementation commit pushed: `1f8c09ef`.

## 2026-10-07 — k3dm thread context and test Slack isolation

Filed and fixed `docs/bugs/2026-10-07-k3dm-thread-context-and-test-slack-leak.md`. `/k3dm`
now forwards and persists `thread_ts`/`channel_id`, so threaded slash jobs can report progress
and completion in the originating thread. The webhook BATS fixture unsets live Slack delivery
variables, preventing stubbed cluster tests inside `make test-all` from posting misleading
cluster-up/down messages. Focused webhook tests pass 17/17; Slack relay tests pass 39/39;
shellcheck is clean. Live restart/verification remains pending.
Implementation commit pushed: `2acbf4cd`.

## 2026-10-07 — threaded ArgoCD usage de-duplicated

Filed and fixed `docs/bugs/2026-10-07-argocd-thread-usage-duplicated.md`. Invalid threaded
ArgoCD requests now use one thread-aware response-URL post and suppress the duplicate immediate
in-channel acknowledgement; top-level validation still returns one normal response. Slack relay
tests pass 40/40 and shellcheck is clean. Live verification remains pending.
Implementation commit pushed: `7882f338`.
Cloudflare relay deployment completed as version `92eb6acf-b158-4b7a-aa8f-eafb594348b5`;
the local webhook had already been restarted. Live Slack retry is now ready.
The subsequent live run showed a thread timestamp without channel metadata; the webhook now
persists the incoming event channel on the anchor before dispatching a child job. Focused webhook
tests remain 17/17; another webhook restart and live retry are required.
Implementation commit pushed: `22208b72`.
The next live run showed the top-level `/k3dm` job had a channel but no thread. The Make route now
creates a bot parent thread for top-level jobs when Slack bot credentials are available. Focused
webhook tests pass 18/18; another webhook restart and live retry are required.
Implementation commit pushed: `6c5ef7fb`.
## 2026-10-08 — k3dm Tests historical failure table implemented

Implemented the P1 dashboard fix from `docs/bugs/2026-10-07-k3dm-tests-failure-history-missing.md`.
The existing latest-run table remains current-state only; new panel 8, `Failures in selected
time range`, queries `max_over_time(k3dm_test_failure[$__range])`, deduplicates scrape samples,
and exposes target/origin, suite, case, name, and bounded reason. Dashboard BATS passed 38/38
and exporter metrics pytest passed 24/24. Live failed-then-passed Grafana verification remains
pending. Implementation commit `448498b5` is pushed to `origin/k3d-manager-v1.42.0`; no PR was
created.
## 2026-10-08 — Slack cleanup thread channel handoff fixed

The P1 cleanup reporting follow-up found that `_handle_thread_command` started
`_run_stale_sandbox_cleanup` without passing the originating `channel_id`. Fixed the handoff
and added a regression test. Focused webhook tests passed 25/25 and Python compilation passed.
Live Slack verification and commit/push remain pending.
## 2026-10-08 — Slack cleanup relay redeployed for live verification

After the local webhook fix, the top-level cleanup preview reached the server but the threaded
reply produced no `/slack/events` request. Redeployed the current Cloudflare relay successfully:
version `f91afb9f-e447-4d6f-897a-1a3122836065`; its smoke request passed. The webhook was already
restarted. Operator retry of the threaded cleanup command remains the live acceptance check.
## 2026-10-08 — plain threaded cleanup message still not delivered

The operator retried `cleanup-stale-sandbox apply` as a plain thread message after webhook
restart and Cloudflare relay redeploy; it still received no response. The webhook log showed
the slash-command API POSTs but no `POST /slack/events`, proving the remaining blocker is Slack
Events subscription/delivery rather than cleanup execution. Immediate workaround: invoke
`/cleanup-stale-sandbox apply` with the slash prefix inside the thread.
## 2026-10-08 — Slack cleanup root-event forwarding fixed

Filed `docs/bugs/2026-10-08-slack-cleanup-thread-event-undelivered.md`. Root cause was a relay
compatibility gap: JSON Slack Events posted to the worker root (the slash-command URL) were not
forwarded to `/slack/events`; only the explicit path was recognized. The worker now forwards root
JSON events while preserving form-encoded slash commands. Node relay tests pass 41/41. Deployed
Cloudflare relay version `e9d3dfc2-ee92-4444-938f-440b4bcc9aad`; the retry still produced no
`/slack/events` request, so Slack app Event Subscriptions configuration/delivery is now the
remaining blocker.
## 2026-10-08 — v1.42.0 Slack authz, thread dispatch, and ask-bash fixes complete

- Three fix commits are pushed to `origin/k3d-manager-v1.42.0`:
  `fedcfcd88a6de92ed0a4f7e0617310029cb41304`,
  `8aa14053fecd89930c680ce2a6a975069ae9e6d6`,
  `b2c45ae3c2e8a96c383b943bab242e8a3f0e9d59`.
- Remote verification: `git rev-parse origin/k3d-manager-v1.42.0` equals local HEAD
  `b2c45ae3c2e8a96c383b943bab242e8a3f0e9d59`.
- Fix 1 changes only the thread dispatch fallthrough and adds 7 focused tests. Fix 2 carries
  `slack_user_id` through every slash relay and caps every route at the mapped caller role.
  Fix 3 adds shell-string scope enforcement, Darwin OS read boundary, and `$SHELL` injection.
- Gates: `shellcheck bin/k3dm-ask-bash` clean; `pytest scripts/tests/bin -q` = 516 passed,
  1 skipped; `node --test workers/slack-relay/test/` = 42 passed, 0 failed; focused ask-bash
  BATS = 4/4 and affected legacy BATS = 2/2.
- The single required `make test` reached 1,387 BATS cases but exited 2: two fixture failures
  were corrected and rechecked; four `e2e_remote` failures remain and are documented in
  `docs/issues/2026-10-08-v1420-gate-results.md`.
- Relay call-site audit: all 12 slash-handler `relay(...)` calls already pass the shared `meta`;
  there were no Events/thread forwarding `relay(...)` call sites left unchanged.
- Live verification remains pending. No worker deployment, webhook restart, `/ask`, PR, merge,
  or live-cluster operation was performed.

- 2026-10-08 23:44Z: Slack thread replies verified working (bot must be in the channel). Residual: /slack/events 401s from bot-echo events over MAX_BODY=4096 truncating before HMAC; fix proposed in docs/bugs/2026-10-08-slack-cleanup-thread-event-undelivered.md, awaiting go for Codex.

- 2026-10-08 23:55Z: Oversized Slack event 401 fix specced (70d09218) and dispatched to Codex.

- 2026-10-09: Claude verified Codex Slack body-cap fix (f127fd7b, d0eb99e8, 26ae4eb7 on origin): relay node tests 45/45, webhook.bats Slack 8/8, RED on pre-fix worktree 2/2 fail. Operator: make restart-webhook && make deploy-worker.

- 2026-10-08 23:58Z: Slack body-cap fix verified live — job ff32a425 success, /slack/events 3x200, 0x401 after bot posts.

- 2026-10-08: Spec docs/plans/v1.43.0-bug-priority-tracking.md (bug Priority P0-P3, vectordb priority/state columns, ask-doc suffix, k3dm_bug_docs metric + Grafana dashboard, pre-commit check). 4th v1.43.0 spec. Awaiting go; Codex dispatch needs k3d-manager-v1.43.0 branch.

- 2026-10-08: Bug priority tracking added to docs/roadmap.md as v1.43.0 candidate; spec QUEUED, dispatch to Codex when k3d-manager-v1.43.0 opens.

- 2026-10-08: Spec docs/plans/v1.43.0-hermes-r10-delete-superseded-failed-job.md (superseded_jobs sensor + R10 approval-gated, target-pinned). v1.43.0 now at 5-plan cap; roadmap updated.

2026-10-08: Hub teardown guard round 2 fixed in `32395370`; status recorded in `ca8db0d9`; live verification pending (operator).
2026-10-08: Hub snapshot round 3 hostname mapping fixed in `2e8996ae`; live verification pending (operator).
2026-10-08: Hub snapshot round 4 now captures claim trees as in-node tar streams in `fbebe9df`; live verification pending (operator).
2026-10-08: Host disk-space sensor implemented in `fb563727` on `k3d-manager-v1.42.0`: executable Python collector, Hermes tick publisher, host-disk PrometheusRule, Grafana dashboard, focused tests, and docs. RED against archived `5872ba40`: 7 failed; GREEN: `769 passed, 1 skipped`; manifest validation: 2 valid, 0 invalid. Live verification remains pending (operator); PR URL: none.
## 2026-10-08 — September bug-doc triage completed

Triaged all 19 requested September bug docs on `k3d-manager-v1.42.0`; status counts: 16 FIXED, 2 PARTIAL, 0 OPEN, 1 UNKNOWN. Docs commit `fbdf1c23` is pushed; `make check-doc-links` passed (`19 file(s) OK`). PR URL: none.
## 2026-10-08 — Hub teardown guard fixed in fa3340bc; live verification pending (Codex)
2026-10-08: Hub snapshot round 5 fix committed as e3040689; live verification pending (operator). PR URL: none.
## 2026-10-08 — Hub snapshot retention round 6 fixed (`81baeca9f455a94110716d0ccc54fc7c3f969112`)

- Implemented the spec's Fix 1–6 and Tests 1–8 on `k3d-manager-v1.42.0`: newest-first verified pruning, automatic post-capture pruning with incomplete protection, M2 free-space preflight, checked final rename, docs, changelog, and regression coverage.
- RED at `a6a53d7d` with only the updated BATS file: the five required tests failed — prune newest, capture auto-prune, auto-prune failure tolerance, insufficient space, and rename failure.
- GREEN: the eight new hub snapshot tests passed; the required hub snapshot, hub recovery, and cluster-down suites passed; shellcheck was clean; `_agent_audit` passed.
- Pushed fix commit to `origin/k3d-manager-v1.42.0`; `HEAD` and remote both equal `81baeca9f455a94110716d0ccc54fc7c3f969112`. PR URL: none. Live verification remains pending.
