# Bug: the M5 weekly hub snapshot failed on its only run, M2 auth denied

**Status:** OPEN — one failure observed; next scheduled run Sunday 2026-11-08 02:30 local decides whether a fix is needed
**Priority:** P2
**Approval:** pending
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-10-30-host-disk-labels-the-new-hub-as-m4-and-cannot-reach-m2.md`; `docs/bugs/2026-11-06-hub-forward-tunnels-lose-auth-after-old-hub-reboot.md`

## Symptom

`com.k3d-manager.hub-snapshot` on the M5 shows `runs = 1`, `last exit code = 1`. `~/Library/Logs/k3dm-hub-snapshot.log`, 2026-11-01:

    cliang@m2-air.local: Permission denied (publickey,password,keyboard-interactive).
    ssh command failed (255): ssh -n -o BatchMode=yes -o ConnectTimeout=10 -- m2jump true
    INFO: [hub-snapshot] scheduled capture ended at 2026-11-01T10:30:02Z (exit 1)

So the M5 hub has no snapshot from this agent since it became the hub. `hub-data-export` is separate and last succeeded 2026-11-06 03:39 local.

## Cause

Not established. On 2026-11-06 the same `ssh -n -o BatchMode=yes m2jump true`, run from a login shell, returned 0. The difference may be the LaunchAgent's agent socket or key at 02:30 versus a login shell, or a change since Nov 1.

## Files

- `scripts/plugins/hub_snapshot.sh`
- `scripts/etc/launchd/com.k3d-manager.hub-snapshot.plist.tmpl` (if the cause is the agent's SSH environment)

## Fix direction

Read the 2026-11-08 run first. If it passes, record that and close. If it fails, compare the agent's SSH environment with the login shell, as `docs/bugs/2026-10-26-hermes-launchagent-github-fetch-misses-ssh-agent.md` did for Hermes, and fix through machine setup.

## Acceptance

```yaml
must:
  - id: M1
    text: "The scheduled hub-snapshot LaunchAgent run on the M5 captures a snapshot to the M2 unattended and exits 0."
must_not:
  - id: N1
    text: "The fix does not disable BatchMode or add a password or interactive path (paired with M1)."
evidence:
  - {id: E1, proves: [N1], kind: offline, text: "Test of the generated agent and ssh arguments, N1 red by a mutant; only if a code change is needed."}
  - {id: E2, proves: [M1], kind: live, text: "launchctl print shows last exit code 0 after the Sunday run, and the M2 lists the new snapshot; run by Claude or the operator."}
interface:
  - "launchd label: com.k3d-manager.hub-snapshot"
  - "ssh alias: m2jump"
```
