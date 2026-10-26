# Incident: webhook unresponsive while operator offsite — minimal diagnosis and controlled recovery

**Filed:** 2026-10-26, operator report at approximately 07:20 PDT
**Status:** OPEN — unverified incident; live host diagnostics and recovery pending
**Priority:** P2
**Severity:** medium — Slack/cloud-bridge remote management degraded or unavailable; actual host and service state unknown
**Release:** v1.43.9 (bug; no new plan slot)
**Branch:** `k3d-manager-v1.43.9`
**Approval:** operator 2026-10-26: "we also need to do minimal diagnoses and repair to bring back webhook server"
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
lsof -nP -iTCP:9000 -sTCP:LISTEN || true
tail -n 80 "$HOME/Library/Logs/k3dm-webhook.log"
```

Caution: `launchctl print` might contain environment values; redact before sharing. `pgrep`/port 9000 confirm only process/listener existence, not HTTP correctness. Confirm actual local bind and endpoint from the installed plist before using a functional curl probe. A curl result must be interpreted by its documented authentication contract; 401 alone may mean HTTP is alive rather than healthy. No remote public endpoint failure by itself proves the local process is down.

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

- `docs/bugs/2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery.md`
- Existing implementation (not changed in this filing): `Makefile` `restart-webhook`, `scripts/etc/launchd/com.k3d-manager.webhook.plist.tmpl`
- Follow-on recovery/monitoring implementation is separately scoped in the related Healthchecks P2 enhancement.

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
