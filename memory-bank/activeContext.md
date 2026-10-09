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
## 2026-10-08 — September bug-doc triage completed

Triaged all 19 requested September bug docs on `k3d-manager-v1.42.0`; status counts: 16 FIXED, 2 PARTIAL, 0 OPEN, 1 UNKNOWN. Docs commit `fbdf1c23` is pushed; `make check-doc-links` passed (`19 file(s) OK`). PR URL: none.
## 2026-10-08 — Hub teardown guard fixed in fa3340bc; live verification pending (Codex)
