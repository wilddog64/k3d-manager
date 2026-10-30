# Webhook incident: independent offline review

**Date:** 2026-10-28
**Scope:** Offline review of the existing doctor, bridge follow-up, and retained incident evidence. No code changes or live checks were performed.

## Findings

The current doctor implements a bounded, read-only local snapshot. It uses port `7443` by default, honors a validated `K3DM_WEBHOOK_PORT` from the bounded launchd output, and sends the reader credential from `K3DM_WEBHOOK_TOKEN_READER` or the existing macOS Keychain item (`k3dm-webhook-token-reader`, account `k3dm`) only to the fixed loopback quick-health URL. The credential is not put on subprocess arguments or returned in JSON. The HTTP budget is 15 seconds; the local command budget is 4 seconds. A health timeout with a listening socket is inconclusive and does not recommend a restart. Missing/unavailable credential, HTTP/auth error, missing launchd job, listener state, and downstream check results remain separate facts. The helper never invokes recovery.

`make restart-webhook` bootouts and bootstraps the webhook LaunchAgent, retries bootstrap up to five times, then restarts cloud-bridge. It is an operator recovery action with impact on both services. The bridge follow-up `f046763ff2a45e8fe56b938a8f828658d0b05ebe` adds Apple's bounded `UseKeychain=yes` SSH fallback only when no explicit `GIT_SSH_COMMAND` override is supplied, preserving explicit empty and inherited/caller overrides. Its bug record says offline verification is complete and operator reload/live check is pending.

No remaining code bug was proven by this review. The doctor, bridge, and restart suites passed as recorded below. The historical cause of the October 26 offsite unresponsiveness remains unknown. The retained evidence reports current local doctor health and successful delivery of Slack job `a13d5831`, but does not separately establish cloud-bridge request/reply operation or explain the historical interruption. The incident must remain OPEN; offline tests do not satisfy E1/E2 or establish root cause.

## Documentation discrepancy

The opening diagnosis snippet in `docs/bugs/2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery.md` still tells an operator to inspect TCP port `9000`. The later correction in that same document and current implementation establish `7443` as the server default (with a validated loaded-job override). Treat the early `9000` command and its port claim as stale; use `bin/k3dm-webhook-doctor --check` for the local snapshot and consult the installed configuration before any manual probe. This review is restricted from editing the incident spec or the other existing files.

The current `docs/howto/webhook-doctor.md` matches the implementation's port, credential source, timeout, response classification, and restart semantics. The cloud-session how-to separately documents `make restart-cloud-bridge` and a benign health request. No other stale port or reader-credential contract was found in the reviewed how-to files.

## Operator live checklist (one step at a time)

1. On m4, run `bin/k3dm-webhook-doctor --check` and save its timestamped JSON after reviewing it for secrets. Do not paste raw `launchctl print`, environment values, tokens, or raw logs into shared records. If the reader credential is unavailable, the authenticated health probe did not run; resolve the local credential-access context without rotating credentials or inferring service failure.
2. If local HTTP is healthy, do not restart the webhook. If health is inconclusive (including a timeout while a listener exists), stop and inspect the local evidence rather than treating it as a dead handler. If m4 is unavailable, this procedure cannot recover the host. If the launchd state or port is unknown, resolve that uncertainty before any recovery decision.
3. If local evidence confirms the webhook job is missing or the local handler is not responding, an operator may make at most one initial `make restart-webhook` attempt from the repository on m4. Record UTC time, command exit/result, and refreshed doctor output. This action also restarts cloud-bridge. Stop on bootstrap failure, repeated process exit, or a still-hung listener; do not loop or perform other remediation without distinct approval.
4. When local webhook health is good but evidence points specifically to cloud-bridge, handle a single `make restart-cloud-bridge` as a separate operator decision and record its result. Do not run it merely because an external request failed; inspect the existing bridge evidence first. If `restart-webhook` was just used, it already restarted the bridge, so do not immediately reload it again.
5. After the applicable service action (or with no action if already healthy), send one benign, read-only cloud request. Record the request timestamp and confirm the completed result was delivered, not just accepted or queued. If local health works but delivery fails, keep local and external-path findings separate and investigate the ingress/bridge path.

## Gates run

Python doctor and bridge suites:

```text
$ python3 -m pytest -p no:cacheprovider scripts/tests/bin/test_webhook_doctor.py scripts/tests/bin/test_cloud_bridge.py scripts/tests/bin/test_restart_cloud_bridge.py
============================= test session starts ==============================
platform darwin -- Python 3.15.1, pytest-9.1.1, pluggy-1.7.0
rootdir: /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.9/webhook-incident-evidence-review-luna
collected 142 items

scripts/tests/bin/test_webhook_doctor.py ............................... [ 21%]
....                                                                     [ 24%]
scripts/tests/bin/test_cloud_bridge.py ................................. [ 47%]
......................................................................   [ 97%]
scripts/tests/bin/test_restart_cloud_bridge.py ....                      [100%]

============================= 142 passed in 5.04s ==============================
```

Webhook restart BATS:

```text
$ bats scripts/tests/bin/restart_webhook.bats
1..5
ok 1 restart-webhook reloads the plist with bootout then bootstrap, never kickstarting the webhook
ok 2 restart-webhook continues to bootstrap when bootout reports the job is not loaded
ok 3 restart-webhook still restarts the cloud bridge
ok 4 restart-webhook retries bootstrap twice then reports success
ok 5 restart-webhook fails after five bootstrap attempts and skips cloud bridge
```

Documentation links:

```text
$ make check-doc-links
check-doc-links: 2469 file(s) OK
```

Diff whitespace validation:

```text
$ git diff --check
```

The first no-index check of the newly created (untracked) review file found
trailing spaces after the date, used to create a Markdown hard break. The
diagnostic below renders those two trailing spaces as `␠␠` to keep this note
free of trailing whitespace:

```text
docs/issues/2026-10-28-webhook-incident-luna-review.md:3: trailing whitespace.
+**Date:** 2026-10-28␠␠
```

Removed the trailing spaces and reran the same check. It produced no output;
its exit code was 1 because `--no-index` reports that `/dev/null` and the new
file differ. The normal tracked-file `git diff --check` returned exit code 0
with no output. No test gate failed.

The commands above exercised fixtures and repository documentation only. No `--check`, live host/log, Keychain, launchd, SSH, network/provider request, service restart, or cloud request was performed during this review.
