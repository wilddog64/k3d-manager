# Slack Make job-ID live check still omits IDs

**Date:** 2026-10-20
**Related bug:** `docs/bugs/2026-10-20-slack-make-job-id-missing-from-status-notices.md`
**Result:** Partial / inconclusive deployment verification; no live pass

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

The job was still running at the time inspected; no terminal notice was observed.

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
3. Run another Slack `/make test-all`; verify queued, started, progress if emitted, and terminal notices all contain the same ID, and `logs <job-id>` retrieves the matching output.
4. Only then mark the related bug LIVE-VERIFIED.
