# Slack Make job-ID live check still omits IDs

**Date:** 2026-10-20
**Related bug:** `docs/bugs/2026-10-20-slack-make-job-id-missing-from-status-notices.md`
**Result:** First live notice check failed; follow-up job `c30366d6` showed IDs in queued, started, progress, and terminal-failure notices. Full test command exited nonzero (1,747 cases, 56 failed); explicit `logs <job-id>` retrieval was not tested on this follow-up, so end-to-end live verification remains partial.

## What was tested

After the fix landed on `k3d-manager-v1.43.5` (`abb0a526`), the operator ran `/make test-all` in Slack. Read-only Slack inspection showed the queued and started notices still omitted the job ID. A `logs` reply did return the job transcript under ID `be53f685`.

Verbatim Slack thread content:

````text
THREAD: :hammer_and_wrench: *make test-all* queued [k3d-manager]

> k3d-manager: :hammer_and_wrench: *make test-all* started by slack:wilddog64:U4C9LDQP2
> wilddog64: logs
> k3d-manager: :clipboard: *Last 20 lines* (job `be53f685`)
```scripts/tests/tripwire.sh ./scripts/k3d-manager test all
running under bash version 5.3.20(1)-release```
````

The run later terminated with `make test-all failed (rc 2)`. That terminal Slack notice also omitted the job ID. The full suite reported 1,747 cases with 56 failures; this broad test failure is separate from the notice-ID behavior and was not fully triaged here.

Verbatim terminal output from the job log:

````text
not ok 1171 recover preflight: a failed k3d listing refuses instead of treating the hub as absent
# (from function `make_fixture' in file scripts/tests/plugins/hub_data.bats, line 125,
#  in test file scripts/tests/plugins/hub_data.bats, line 967)
#   `make_fixture; source_plugin' failed with status 127
# /Users/cliang/src/gitrepo/personal/k3d-manager/scripts/tests/plugins/hub_data.bats: line 126: sha256sum: command not found
make[1]: *** [test] Error 1
[k3dm-test-metrics] 1747 cases, 56 failed
[k3dm-test-metrics] metrics pushed: test-all/local
[test-all] metrics log: /var/folders/nc/y0_fv7412472dpg2z7y0yq5w0000gn/T//k3dm-test-all-1792540915.log
make: *** [test-all] Error 2
````

The `sha256sum` fixture failure is already tracked in `docs/bugs/2026-10-19-hub-data-bats-fixture-sha256sum-missing-on-macos.md`. Other failures remain untriaged; the captured local transcript is `scratch/test-logs/all/20261020-170156.log`.

## Follow-up live run: `c30366d6`

The operator reran `/make test-all` in the same Slack conversation. Read-only inspection confirmed the same job ID in every lifecycle notice emitted by this run:

```text
:hammer_and_wrench: *make test-all* queued — job `c30366d6`
:hammer_and_wrench: *make test-all* started by slack-thread:U4C9LDQP2 — job `c30366d6`
:hourglass_flowing_sand: *make test-all* still running — 2m elapsed — job `c30366d6`
:x: *make test-all* failed (rc 2) — job `c30366d6`
```

The local job status became `failed`. Verbatim ending:

````text
Test log saved to scratch/test-logs/all/20261020-171339.log
Collected artifacts in scratch/test-logs/all/20261020-171339
[tripwire] blocked 430 call(s) to host tools; none reached a real binary:
  84 kubectl --context ubuntu-k3s --request-timeout=5s get --raw=/readyz
  84 kubectl --context ubuntu-hostinger --request-timeout=5s get --raw=/readyz
  84 kubectl --context ubuntu-gcp --request-timeout=5s get --raw=/readyz
  84 kubectl --context ubuntu-azure --request-timeout=5s get --raw=/readyz
  37 security find-generic-password -s k3dm-webhook-token-reader -a k3dm -w
  37 security find-generic-password -s k3dm-webhook-token-cloud-runner -a k3dm -w
  7 gh auth token
  5 aws cloudformation describe-stacks --region us-west-2 --stack-name k3d-manager-cluster --query Stacks[0].StackStatus --output text
  4 launchctl list com.k3d-manager.acg-watch
  1 security find-generic-password -s platform-ops-git-writer -a k3dm -w
  1 security find-generic-password -s platform-ops-app-rebuild -a k3dm -w
  1 security find-generic-password -s k3dm-webhook-token -a k3dm -w
  1 kubectl config get-contexts ubuntu-k3s
make[1]: *** [test] Error 1
[k3dm-test-metrics] 1747 cases, 56 failed
[k3dm-test-metrics] metrics pushed: test-all/local
[test-all] metrics log: /var/folders/nc/y0_fv7412472dpg2z7y0yq5w0000gn/T//k3dm-test-all-1792541619.log
make: *** [test-all] Error 2
````

The known macOS fixture failure recurred (`scripts/tests/plugins/hub_data.bats: line 126: sha256sum: command not found`). The full transcript is `scratch/test-logs/all/20261020-171339.log`; the other 55 failures were not triaged. An explicit `logs c30366d6` lookup was not run, so live verification remains partial despite lifecycle ID propagation working.

## Diagnostics and actual output

The LaunchAgent plist's `ProgramArguments` point to:

```text
/opt/homebrew/bin/python3
/Users/cliang/src/gitrepo/personal/k3d-manager/bin/k3dm-webhook
```

`launchctl list | rg 'com\.k3d-manager\.webhook'` produced no matching output. Process inspection was denied by macOS:

```text
zsh:1: operation not permitted: ps
```

The diagnostic plist dump also printed stored Slack credentials into tool output. Secret values are intentionally omitted here; treat the credentials as potentially exposed and rotate them through the established secret-management process.

## Root cause

Not established. The Slack notices prove the process handling this request did not emit the new ID fields. The plist points at the correct checkout, but the process state could not be inspected, so a stale process / missing restart is plausible, not confirmed.

## Recommended follow-up

1. Rotate the potentially exposed Slack bot token and signing secret, then update the secure local store / LaunchAgent using the established rotation procedure.
2. From the updated release checkout, run `make restart-webhook`.
3. Use a successful, safe Slack Make target for the notice retest; the observed `test-all` run itself failed with 56 cases, including a known macOS fixture failure.
4. Verify queued, started, progress if emitted, and terminal notices all contain the same ID, and `logs <job-id>` retrieves the matching output.
5. Only then mark the related bug LIVE-VERIFIED.
