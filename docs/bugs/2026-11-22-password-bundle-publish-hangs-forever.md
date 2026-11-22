# Bug: password-bundle publish can hang forever and silently stop every later run

**Status:** OPEN — filed 2026-11-22
**Priority:** P2
**Introduced by:** ddd9329e (travel bundle, v1.45.0 plan 2)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-22
**Prior art:** `docs/bugs/2026-11-22-test-all-failures-not-attributable-to-host.md` (slug grep, not scored) — read, different root cause; `make find-similar-docs` not run (vector store unreachable from m4-air).
**Approval:** operator, 2026-11-22: "go ahead to file a P2 bug then dispatch to Luna" (dispatch without waiting for triage).
**Intent approved:** pending

## Symptom

PasswordBundleStale fired on the hub (cluster=hub, reason=stale) on 2026-11-22. Operator capture on m5-air:

- `launchctl list` showed `88191  0  com.k3d-manager.password-bundle`: a PID, so a run was **still in progress**, and
  last exit status 0.
- `~/Library/Logs/k3dm-password-bundle.log` was last written Nov 22 02:01; it held only `running under bash` start lines.
- A manual `make password-bundle-publish` in the operator's shell succeeded at once.

launchd never starts a StartInterval job while the previous run is alive. The 02:01 run hung, so every 15-minute run
after it was skipped, and the stale alert (no successful publish for 2 h) fired. A hang reports no failure, so
`PasswordBundlePublishFailed` never fires.

## Root cause

Nothing in the publish path is time-limited:

- `password_bundle_publish` (`scripts/plugins/password_bundle.sh:142`) runs `make -s show-service-passwords` with no
  bound.
- That target (`Makefile:1075-1171`) calls `kubectl get` and `curl` to Vault (127.0.0.1:18200), ArgoCD, Grafana and
  Prometheus with no `--max-time`. A port-forward that stalls without closing (for example after the Mac sleeps)
  blocks forever.
- The metrics push (`scripts/plugins/password_bundle.sh:15`) has no `--max-time` either.
- The delivery folder is in iCloud Drive (`PB_DIR`, line 6), so `mv` can also block.

Which call hung on 2026-11-22 is not yet known (the operator's `ps` capture is owed). The fix bounds the whole run
whichever call it was.

## Scope

This fix changes **only** `scripts/plugins/password_bundle.sh` and `scripts/tests/plugins/password_bundle.bats`.
Per-call `--max-time` in the `Makefile` target is a follow-up after web-console C r2 lands, because C r2 has an open
edit to `Makefile` (one dispatch per file).

## External behaviour proof (Claude, m4-air, 2026-11-22T12:36Z)

Against a local listener that accepts connections and never answers:

- `curl 8.7.1`: `curl -m 2` exits 28 after 2 s.
- `kubectl v1.37.2 --request-timeout=2s`: exits 1 after 10 s (the TLS handshake has its own 10 s limit).
- `perl -e 'alarm 2; exec @ARGV' curl ...` exits 142 after 2 s, but kills only the exec'd process. Children survive and
  keep pipes open (seen on 2026-11-21 in the mutation harness).
- On m4-air, `timeout` and `gtimeout` come from Homebrew coreutils (`/opt/homebrew/bin`). The hub's launchd PATH is not
  proven to include them, so the fix must not depend on them.

Hub (m5-air) versions are not captured; a live check on the hub is E4.

## Implementation notes (guidance, not the interface)

- Run the payload step in its own process group and keep a watchdog that kills the whole group (`kill -TERM -- -PGID`,
  then `-KILL` after a grace period) when the limit passes. Options: `set -m` in the subshell so a background job gets
  its own group, or `perl -e 'setpgrp(0,0); exec @ARGV'`. Do not use `timeout`/`gtimeout`.
- On timeout: `_password_bundle_metrics 0 ...`, one clear stderr line naming the limit, return nonzero.
- Add `--max-time` to the metrics push curl (default 10 s).
- Never echo the payload.

## Acceptance

```yaml
interface:
  env:
    K3DM_PASSWORD_BUNDLE_TIMEOUT: "whole-run limit in seconds for password_bundle_publish's payload step; default 300; a value that is not a positive integer falls back to 300"
  behaviour: "password_bundle_publish returns nonzero within the limit plus a 15 s grace period when the payload step does not finish, and pushes publish_success 0"
must:
  - id: M1
    text: "A publish whose make show-service-passwords never returns ends within K3DM_PASSWORD_BUNDLE_TIMEOUT + 15 s, exits nonzero, and pushes k3dm_password_bundle_publish_success 0."
  - id: M2
    text: "On timeout, no process started by that publish run (including grandchildren of make) is still alive after publish returns."
  - id: M3
    text: "The metrics push is bounded: a push endpoint that accepts and never answers does not keep publish running for more than 15 s beyond the push."
  - id: M4
    text: "The time limit works with timeout and gtimeout absent from PATH."
  - id: M5
    text: "A normal publish (payload returns at once) is unchanged: success 1 pushed, bundle and meta written, all existing password_bundle.bats tests pass."
must_not:
  - id: N1
    text: "Publish must not stay running past the limit when the payload step hangs (red on pre-fix code: it never returns)."
  - id: N2
    text: "A timed-out run must not update PB_STATE/last-publish or last.sha256."
  - id: N3
    text: "A timed-out run must not print the payload or any part of it to stdout or stderr."
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: "If a step of the hourly bundle publish freezes, the job gives up on its own after a set time, says it failed, and does not leave stray processes behind."
    how: "bats: stub make that starts a grandchild 'sleep 3600' with a unique marker and then sleeps; K3DM_PASSWORD_BUNDLE_TIMEOUT=2; stub push endpoint records bodies. Assert publish returns within 20 s with rc != 0, the recorded body has publish_success 0, last-publish and last.sha256 are unchanged, and no process with the marker exists. Run under a harness timeout so pre-fix code fails instead of hanging."
  - id: E2
    proves: [M3]
    kind: offline
    intent: "If the metrics endpoint stops answering, the publish still finishes instead of waiting forever."
    how: "bats: push URL points at a local listener that accepts and never replies; fast stub make; publish returns within 30 s."
  - id: E3
    proves: [M4]
    kind: offline
    intent: "The time limit works on a Mac without the Homebrew timeout tool, which is how launchd runs the job."
    how: "bats: E1 rerun with a PATH built from a scratch bin holding only the needed tools, asserting command -v timeout and gtimeout both fail first."
  - id: E4
    proves: [M5]
    kind: offline
    intent: "Normal publishing still works exactly as before."
    how: "positive control for E1: fast stub make, success 1 pushed, bundle written; full scripts/tests/plugins/password_bundle.bats green."
  - id: E5
    proves: [M1]
    kind: live
    intent: "On the hub, the job keeps publishing every 15 minutes for two hours and the stale alert stays clear."
    how: "operator or Claude after make hub-deploy: launchctl list shows '-' in the PID column between runs; log mtime advances each 15 min over 2 h; PasswordBundleStale not firing."
```

## Contract readers

- New env var `K3DM_PASSWORD_BUNDLE_TIMEOUT`: reader `scripts/plugins/password_bundle.sh` (new). Writers: none; the
  launchd template `scripts/etc/launchd/com.k3d-manager.password-bundle.plist.tmpl:6` does not set it, so the default
  applies. No other reader (`grep -rn K3DM_PASSWORD_BUNDLE_TIMEOUT` empty before this fix).
- `make show-service-passwords` is unchanged; its other callers (`scripts/tests/bin/webhook_make_targets.py:189`,
  `scripts/tests/bin/makefile_show_service_passwords.bats`) are unaffected.

## Operator workaround until the fix lands

On m5: `launchctl kickstart -k gui/$(id -u)/com.k3d-manager.password-bundle` kills the hung run and starts a fresh one.
