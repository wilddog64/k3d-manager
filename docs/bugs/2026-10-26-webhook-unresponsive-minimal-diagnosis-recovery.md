# Incident: webhook unresponsive while operator offsite — minimal diagnosis and controlled recovery

**Filed:** 2026-10-26, operator report at approximately 07:20 PDT
**Status:** OPEN — current local and Slack health confirmed; historical offsite cause remains unknown
**Priority:** P2
**Severity:** medium — Slack/cloud-bridge remote management degraded or unavailable; actual host and service state unknown
**Release:** v1.43.9 (bug; no new plan slot)
**Branch:** `k3d-manager-v1.43.9`
**Approval:** operator 2026-10-26; renewed 2026-10-27 Luna batch for the bounded diagnostic deliverable and later one-at-a-time operator live checks
**Dispatch:** go — model `gpt-6-luna`; task `webhook-incident-doctor-luna`
**Component:** m4 host `com.k3d-manager.webhook` launchd LaunchAgent; associated cloud-bridge
**Related:** `docs/bugs/2026-10-26-independent-heartbeat-healthchecks-monitoring.md`; `docs/bugs/2026-10-23-restart-webhook-kickstart-ignores-plist-env-changes.md`

## Symptom and evidence

Operator observed the webhook server unresponsive while away from home. There is currently **no** direct m4 process output, listener test, journal/log evidence or successful post-failure request. Unknown whether m4 is powered on, launchd has a job, a process exists, the loopback listener responds, the Cloudflare/network ingress fails, or the cloud-bridge is also affected. Do not attribute the incident to the October 23/24 restart fix without evidence.

Repository inspection on `k3d-manager-v1.43.9` confirms that `make restart-webhook` invokes `launchctl bootout`, retries `launchctl bootstrap` up to five times, and then calls `restart-cloud-bridge`. Thus, it is an existing supported recovery action, but can interrupt both webhook and bridge and will not repair a down/offline host.

## Minimal operator-run diagnosis (m4, read-only first)

Run from an authenticated shell on m4 when available. Capture timestamps and redacted output; do not print plist secrets, tokens or credentials.

```bash
date -u
launchctl print "gui/$(id -u)/com.k3d-manager.webhook" | head -60
pgrep -fl 'k3dm-webhook' || true
lsof -nP -iTCP:7443 -sTCP:LISTEN || true
tail -n 80 "$HOME/Library/Logs/k3dm-webhook.log"
```

Caution: `launchctl print` might contain environment values; redact before sharing. `pgrep`/port 7443 confirm only process/listener existence, not HTTP correctness. Confirm actual local bind and endpoint from the installed plist before using a functional curl probe. A curl result must be interpreted by its documented authentication contract; 401 alone may mean HTTP is alive rather than healthy. No remote public endpoint failure by itself proves the local process is down.

Record: launchd job state/last exit status, process PID, port listener, last log timestamp/error and local authenticated functional health result. If local health works but external Slack/Cloudflare does not, **do not restart blindly**: investigate the tunnel/ingress route instead.

## Minimal recovery (operator m4 only)

If webhook is confirmed locally nonresponsive or its LaunchAgent/process is absent and the host is otherwise healthy:

```bash
# From the checked-out k3d-manager repository on m4
make restart-webhook
```

Run once initially. It reloads the webhook LaunchAgent definition and then restarts cloud-bridge; it is not a no-impact probe. Avoid restart loops, `kill -9`, rebooting m4, reinstalling dependencies, modifying Keychain credentials or rebuilding clusters. On failure capture stderr and `launchctl print` state before further actions.

Post-restart: repeat process/listener and log checks, test the local HTTP functional endpoint using the established authenticated health-check procedure, then check a benign Slack command or existing read-only cloud-bridge status request. Confirm end-to-end reply delivery, not merely an accepted/queued job. If recovery succeeds, document exact UTC timestamps, PID/exit evidence, functional request outcomes and whether bridge was restored.

If launchd bootstrapping fails, process dies repeatedly, or an HTTP listener still hangs, stop automatic attempts; classify and triage interpreter, missing file, permissions, bind conflicts and resource exhaustion from logs, without speculative remediation. If m4 itself is unavailable, this mechanism cannot recover it; notify the operator through an independent channel once deployed.

## Files

- `docs/issues/2026-10-28-webhook-incident-luna-review.md`
- `bin/k3dm-webhook-doctor`
- `scripts/tests/bin/test_webhook_doctor.py`
- `scripts/tests/bin/restart_webhook.bats`
- `docs/howto/webhook-doctor.md`
- `docs/tests/webhook-doctor.md`
- `CHANGELOG.md`

## Offline implementation deliverable

Operator selected this incident in the 2026-10-27 Luna batch. The historical
root cause is still unknown; do not invent a code fix or perform recovery to
make the task look complete. Implement a small read-only diagnostic entrypoint
for the operator's later E1/E2 check, with fixture-tested classifications.

- Default/--dry-run explains the probe plan without Keychain/network/process
  access. Explicit --check collects timestamped, bounded, redacted JSON.
- Read the installed webhook job state/PID/last exit, actual bind/port, listener
  presence, and log freshness/error categories without dumping environment, raw
  process argv, token values or unbounded logs. Keep secrets off subprocess argv.
- Probe only the documented reader-authenticated loopback health endpoint, with
  a bounded timeout and in-memory reader token. Validate response schema; separate
  HTTP handler responsiveness from downstream service all_ok. Reject arbitrary
  remote URLs. Auth failure, local timeout, missing job and healthy HTTP with bad
  external delivery are distinct outcomes. No process-only healthy inference.
- Recommend make restart-webhook only when local evidence warrants it; the doctor
  must never restart/kill/reboot/bootstrap or mutate Kubernetes, launchd or secrets.
  Explain that the existing recovery also restarts cloud-bridge and is operator-
  controlled, at most once initially, followed by end-to-end evidence.
- Fixtures prove redaction, timeout/auth/listener classification, healthy local
  versus failed ingress distinction and zero recovery calls. Document the original
  incident as unconfirmed until operator evidence; offline helper tests cannot
  satisfy the original live E1/E2 or mark the incident LIVE-VERIFIED.

## Acceptance

```yaml
must:
  - id: M1
    text: Capture independently verifiable local launchd, process, listener, log and functional health status before classifying the failure.
  - id: M2
    text: If the local webhook is unhealthy, perform at most one initial operator-authorized make restart-webhook invocation on m4 and record its exit/result.
  - id: M3
    text: Verify webhook functional local response plus end-to-end Slack/cloud-bridge operation after recovery, with timestamps and evidence.
  - id: M4
    text: Record the root-cause hypothesis as unconfirmed until correlated log/probe evidence exists and link this incident to independent heartbeat monitoring follow-up.
must_not:
  - id: N1
    text: Do not assert process crash, m4 outage or tunnel failure based solely on offsite unresponsiveness.
  - id: N2
    text: No credentials, token values or secret-bearing launchctl output in repository or shared logs.
  - id: N3
    text: No repeated restart loop, destructive remediation, cluster rebuild or host reboot without distinct approval.
  - id: N4
    text: No false LIVE-VERIFIED status based on offline code inspection or a successful launchctl exit alone.
evidence:
  - id: E1
    kind: live
    proves: [M1, M4, N1, N2]
    text: Timestamped redacted m4 launchd/process/port/log and local HTTP evidence recorded before any restart.
  - id: E2
    kind: live
    proves: [M2, M3, N3, N4]
    text: Operator-run make restart-webhook result, refreshed local HTTP health, and delivered read-only Slack/cloud-bridge response recorded after restart.
interface:
  - make restart-webhook (m4 operator shell)
  - launchctl print gui/<uid>/com.k3d-manager.webhook
  - local webhook HTTP health endpoint (read documented auth and bind configuration first)
```

## Definition of Done

- [ ] E1 collected (or clearly documented as unavailable if process was already restored).
- [ ] Single controlled repair attempt, if indicated, with result documented.
- [ ] Local webhook and external read-only request path independently live-verified.
- [ ] Remaining failure/root-cause investigation linked or split; mark resolved only on evidence.

## What NOT to Do

- Do NOT create a PR or push to `main`; documentation belongs on `k3d-manager-v1.43.9`.
- Do NOT claim any m4 commands were executed by the GitHub connector.
- Do NOT use a cloud-bridge job as evidence of functioning webhook while its transport is down.

## Dispatch rules — operator batch 2026-10-27

The operator explicitly selected this existing bug for implementation by
GPT-6-Luna, independent offline review, and operator live verification one fix
at a time. This is implementation authorization; no worker may deploy, restart
services, contact live clusters/registries/providers, create accounts, rotate
credentials, or run live tests. Work only in the isolated task worktree and the
Files allowlist. Do not edit this spec, memory-bank, or source plan statuses.
Do not stage, commit, push, or create PRs. Preserve DO NOT REMOVE comments.
Add meaningful regressions and show them red on the original behavior before
reporting green. Run focused tests, syntax/lint, and git diff --check; report
actual outputs and any unmet acceptance honestly. Use <=8 if blocks in new or
refactored functions. Report legacy budget conflicts instead of raising limits.
The coordinator will run audit/lint on staged changes before committing.

Focused gates: test_webhook_doctor pytest, restart_webhook BATS, syntax/Ruff,
diff check. The worker must not execute --check against the real host or call
make restart-webhook. Leave the original incident unverified for operator E1/E2.

## Diagnostic deliverable independently verified — 2026-10-27

Helper implementation `e4f6823ed52e8c070ccf516cb000af5fc2f5a6e9` is landed
and pushed. Independent doctor pytest 21/21, restart BATS 5/5, Ruff, direct
dry-run, diff check and staged audit/lint passed; dispatcher reran gates after
rebase. Fixed quick request, redirect/proxy protection, truthful unknown/error
states, command/output bounds, missing-ok schema and Keychain dict-contract
crash before acceptance. No recovery or live diagnostics performed.

The incident remains OPEN; helper completion does not establish an outage
cause or recovery. Full outputs and remaining live steps are in
`docs/issues/2026-10-27-six-bug-luna-batch.md`.

## Live check3 — 2026-10-27

Operator JSON at12:17:20Z reported auth_unavailable and recommended no restart.
Coordinator found diagnostic port9000 was wrong; live PID4295 listens on7443.
Corrected helper/defaults in `2b93434e893ff0417946c550deecbecb1443021d`.
A fresh read-only direct check at12:24:33Z shows loaded PID4295, port7443
listening, authenticated healthy_http/all_ok=true, recovery_recommended=false.
This supersedes the earlier absence of current local evidence; it does not
establish the historical offsite failure cause. No recovery was warranted or
performed. Operator credential-context reason is unknown. Next check is
completed Slack `/k3dm fix-list` delivery, one at a time.

Full exact output and diagnostic regression:
`docs/issues/2026-10-27-webhook-doctor-live-port-mismatch.md`.

## Current end-to-end delivery confirmed — operator job a13d5831

Operator screenshot shows `/k3dm fix-list` queued, started, succeeded, and
returned its actual target list in the same Slack thread (job `a13d5831`).
Current local health and Slack result delivery are confirmed. No restart was
needed or performed. Historical offsite cause and operator reader-credential
context remain unknown; cloud-bridge path was not separately exercised.
This incident stays OPEN for that remaining investigation; diagnostic
deliverable/current Slack functionality is live-confirmed. Full screenshot
and evidence: `docs/issues/2026-10-27-webhook-doctor-live-port-mismatch.md`.

Operator repeat12:42:06Z shows correct7443/listening but credential unavailable.
No outage/recovery inferred. A separately reproduced helper command-exit race
was fixed offline in b591a13c803b44377fcea91207ea68142a9fdf5c; operator
credential recheck remains pending, with no proven causal claim. Evidence:
docs/issues/2026-10-27-webhook-doctor-command-exit-race.md.

Operator22:30:13Z repeat still reports auth_unavailable after b591a13c,
with7443 listening and no recovery recommended. Thus the independently fixed
command race is not established as this symptom's cause. Coordinator lookup
metadata shows reader credential retrievable in its own context (exit0),
without disclosure. Next operator step is a secret-safe lookup exit-status
probe; shell-context cause remains unresolved. Full result in
docs/issues/2026-10-27-webhook-doctor-command-exit-race.md.

Operator targeted lookup returned native exit36 in0.03s at /usr/bin/security.
This is consistent with truncated errSecInteractionNotAllowed(-25308), not
a timeout; exact native error/session cause remains unconfirmed. Fresh local
GUI-tab lookup with password output suppressed is the next single diagnostic.
No token rotation, ACL change, keychain unlock or webhook restart performed.
Full evidence/source distinction in docs/issues/2026-10-27-webhook-doctor-command-exit-race.md.

Operator confirmed the login Keychain was locked. After interactive unlock,
the same reader lookup returned exit0 instead of36, without exposing or
rotating the token. This resolves the operator auth_unavailable lookup
symptom; it does not explain the historical offsite incident or implicate
tmux. A final doctor check in the unlocked session is next. Full terminal
evidence in docs/issues/2026-10-27-webhook-doctor-command-exit-race.md.

Recurring Keychain locks are now handled explicitly by the doctor in
1ff3b09b2bda92fc20125253f5c7b365db320e46: interaction-required classification,
separate missing-credential state, safe action hint and no restart action
for credential access failure alone.31 Python/5 BATS and staged gates passed.
No automatic unlock or policy change. Historical incident status is unchanged.
Full evidence: docs/issues/2026-10-27-webhook-doctor-keychain-aware-auth.md.

At22:43:40Z operator credential was available but aggregate health timed out
under the former4-second budget while7443 listened. Held recovery. Source
quick endpoint permits8-second dependency probes; independent current401 in
0.146s and authenticated healthy response in3.438s showed current handler
responsiveness without restart. Budget/recovery inference fixed in
eafe42da71f6243f9613dc85f53f92f9e7ae0182;35Python/5BATS gates passed.
Fresh corrected direct check22:49:14Z is healthy/all_ok=true, credential
available, no recovery action. Exact prior timeout cause is not inferred.
Full evidence docs/issues/2026-10-27-webhook-doctor-health-timeout-restart-inference.md.

## Follow-up investigation — 2026-10-27

Current doctor01:59:44Z healthy/all_oktrue and no recovery. Retained bridge60 SSH github.com port22 Undefined error:0 messages correlate with13:50–14:50Z incident window; later Oct27 retained bridge responses HTTP200/202 show subsequent activity. A separate controlled no-agent lookup failspublickey, while UseKeychain=yes succeeds. This confirms unattended-auth gap, not exact historical network cause; [bounded bridge follow-up](2026-10-27-cloud-bridge-unattended-github-ssh-auth.md) dispatched after user authorized investigation/tasks. Original incident remains OPEN; no restart/new remote request performed. [Full sanitized evidence](../issues/2026-10-27-three-open-bugs-investigation-and-luna.md).

Bridge follow-up implementation f046763ff2a45e8fe56b938a8f828658d0b05ebe landed with107Python tests/Ruff/staged gates passed. This addresses the reproducible no-agent Git auth gap, not the un-reproduced historical Undefinederror0 cause. No service reload/remote request yet; incident OPEN pending remaining live evidence. Full outputs in three-open-bugs issue.

## Authorized Luna batch — 2026-10-28 (current instructions)

Operator explicitly requested dispatch of this screenshot bug to GPT-6-Luna,
independent coordinator verification, then operator live checks one at a time.
This authorizes the bounded implementation/review below and supersedes older
filing-only/not-authorized wording. No deployment, live provider requests,
service restarts, Keychain reads/writes, credential changes, screenshot exports,
PRs or main-branch changes are authorized to the worker. Work in the isolated
worktree only. Do not edit memory-bank, this spec or source plan statuses.
Do not stage/commit/push. Preserve DO NOT REMOVE comments. Coordinator owns
staged gates, commit/push/landing and records. New/refactored functions <=8ifs;
never weaken audit or hooks. Report unexpected failures verbatim.

This run is an independent offline review and evidence consolidation, not a
repeat of the implemented helper or an invented historical root-cause fix.
The earlier deliverable is already landed (doctor keychain/timeout fixes,
bridge fallback f046763f). For this review ONLY write
`docs/issues/2026-10-28-webhook-incident-luna-review.md` (the other historical
Files entries are read-only for this task). Read current implementation, related
cloud-bridge-unattended-github-ssh-auth bug and existing incident issue evidence.
Run current doctor/restart and cloud-bridge/restart unit suites; no actual
--check, network/provider/live logs/Keychain/launchctl/SSH access. Record exact
outputs and remaining gaps. Check stale diagnostic documentation against current
port/credential contracts; report discrepancies without expanding code scope.
Provide safe one-at-a-time operator live checklist (local doctor, separately
operator bridge reload if needed, then benign cloud request/delivered result),
conditions to stop or avoid restart, and distinguish current health vs historical
cause. Leave original incident OPEN pending evidence. If no remaining code
bug is proven, say so rather than asserting all fixed. Do not edit any code.
Rules gates: python3 -m pytest -p no:cacheprovider scripts/tests/bin/test_webhook_doctor.py
scripts/tests/bin/test_cloud_bridge.py scripts/tests/bin/test_restart_cloud_bridge.py;
bats scripts/tests/bin/restart_webhook.bats; document-link/diff checks. Report full
actual outputs, existing test failure details and no-live-action boundary.

## Renewed Luna review — 2026-10-28

Task webhook-incident-evidence-review-luna completed a bounded offline review;
landed223bb879. Independent142doctor/bridge Python tests and5restartBATS pass,
also rerun by landing gate. No new code bug or historical cause proven.
[Review and remaining operator checklist](../issues/2026-10-28-webhook-incident-luna-review.md).
Coordinator corrected the opening manual port example9000→7443 based on current
implementation, retaining installed-override caution. Prefer doctor --check;
no new health/restart/credential/provider action executed. Original incident
remains OPEN pending current bridge-path live evidence/historical uncertainty.
