# Bug: Hostinger tunnel logs can't place a drop in time, and reconnect waits on 75-second TCP timeouts

**Filed:** 2026-10-23 (Claude, from the 2026-10-22 Hostinger 502 investigation)
**Status:** FIXED (offline) at `5f9fb209` — live E2 pending
**Priority:** P2 — a tunnel drop causes multi-service 502s, and its evidence is lost or has no timestamps
**Severity:** medium
**Approval:** approved — operator, 2026-10-23: "go ahead"
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `scripts/plugins/tunnel.sh`, `bin/cluster-down`
**Related:** `docs/bugs/2026-10-20-hostinger-multi-service-502-kubernetes-api-timeouts.md`,
`docs/bugs/2026-10-04-ssh-tunnel-autossh-reconnect-blocked-by-orphaned-remote-8200.md`

## Symptom

On 2026-10-22, from about 03:40 to 03:50 PDT, the M4→Hostinger tunnels were down, and every public
service routed through them returned 502. The Hostinger journal shows k3s and Hostinger's uplink
were healthy, so the outage was on the M4/ISP side. Three things made the incident slow to diagnose
and slower to recover:

1. **No timestamps.** `/tmp/k3d-manager-tunnel-vault.err` is 2.3 MB and 36,444 lines of raw `ssh`
   stderr with no timestamps. Its last lines show the keepalive timeout (`Timeout, server … not
   responding`) followed by repeated `connect to host … port 22: Operation timed out`. The file's
   mtime (03:49) is the only clue to when they happened. Most of the file is weeks-old noise from
   earlier host aliases: about 19,000 timeouts to old ACG IPs and 1,012 host-key warnings.
2. **The hub forward tunnel's log is deleted while the tunnel is still running.** `bin/cluster-down`
   (`[acg-down]` /tmp cleanup) removes `/tmp/k3d-manager-tunnel.{out,err}`, even though that tunnel
   belongs to the Hostinger hub and keeps running. launchd keeps writing to the unlinked file, so the
   log on disk shows nothing. On 2026-10-23 both files were 0 bytes, recreated at 04:31.
3. **Each reconnect attempt can block for about 75 seconds.** Neither `ssh` invocation sets
   `ConnectTimeout`, so while the route is down every attempt waits out macOS's default TCP connect
   timeout. Once the route comes back, the tunnel can take that long again before it reconnects.

## Fix

- **F1. Timestamped logs.** Every line written to the tunnel `.err` logs (the forward agent and the
  vault agent, in both hub and sandbox scope) starts with an ISO-8601 UTC timestamp. Do it in the
  generated agent: for example, a wrapper script for the forward tunnel like the existing vault
  wrapper, with stderr piped through a timestamping loop. The launchd `ProgramArguments`
  `pgrep` patterns (`_tunnel_forward_pattern`, `_tunnel_vault_pattern`) must still match the running
  process.
- **F2. Bounded logs.** When `tunnel_start` writes the agents, a log over 5 MB is moved to `<log>.1`,
  replacing any older `.1`.
- **F3. Connect timeout.** Add `-o ConnectTimeout=10` to the forward `autossh` arguments and to the
  vault wrapper's `exec ssh` line. Keep `ServerAliveInterval=30`, `ServerAliveCountMax=3` and
  `ExitOnForwardFailure=yes` as they are.
- **F4. `cluster-down` keeps the hub tunnel logs.** Remove the two `rm -f /tmp/k3d-manager-tunnel.*`
  lines from `bin/cluster-down`. Leave `make clean-tmp` unchanged; it is an explicit operator action.
- **F5. Docs.** `docs/howto/launchd-daemons.md`:
  - The `com.k3d-manager.ssh-tunnel` section says that agent carries `-R 8200`. It doesn't: the reverse
    path is the separate `com.k3d-manager.ssh-tunnel-vault` agent. Correct this.
  - List the vault agent and its log paths.
  - Note that the logs are timestamped and bounded.
- **F6.** `CHANGELOG.md` entry.

## Files

- `scripts/plugins/tunnel.sh`
- `scripts/tests/plugins/tunnel.bats`
- `bin/cluster-down`
- `docs/howto/launchd-daemons.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: The generated forward and vault agents (hub and sandbox scope) prefix every stderr line written to their .err log with an ISO-8601 UTC timestamp.
  - id: M2
    text: Both generated ssh invocations (forward autossh args and vault wrapper exec line) include ConnectTimeout=10, and keep ServerAliveInterval=30, ServerAliveCountMax=3 and ExitOnForwardFailure=yes.
  - id: M3
    text: tunnel_start moves a tunnel log larger than 5 MB to <log>.1 and leaves a smaller log in place.
  - id: M4
    text: tunnel_status / _tunnel_is_running / _tunnel_vault_is_running still detect the agents tunnel_start generates.
must_not:
  - id: N1
    text: bin/cluster-down must not delete /tmp/k3d-manager-tunnel.out or /tmp/k3d-manager-tunnel.err (red on the current script).
  - id: N2
    text: A generated tunnel agent must not write an untimestamped stderr line to its .err log (red on the current tunnel.sh).
  - id: N3
    text: A generated ssh invocation must not omit ConnectTimeout (red on the current tunnel.sh).
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3]
    text: BATS in scripts/tests/plugins/tunnel.bats with stubbed ssh/autossh/launchctl; the N tests fail against the pre-fix tunnel.sh and cluster-down.
  - id: E2
    kind: live
    proves: [M1, M2, M4]
    text: Operator reruns tunnel_start for the hub; Claude confirms both agents are running, the .err lines carry timestamps, and ps shows ConnectTimeout=10.
interface:
  - tunnel_start / tunnel_stop / tunnel_status (scripts/plugins/tunnel.sh), TUNNEL_SCOPE=sandbox
  - TUNNEL_PLIST_PATH, TUNNEL_VAULT_PLIST_PATH, TUNNEL_VAULT_WRAPPER_PATH overrides
  - the generated plist and wrapper files
  - bin/cluster-down /tmp cleanup step
```

## Definition of Done

- [ ] F1–F6; only the Files above change.
- [ ] N1–N3 shown red against the pre-fix code.
- [ ] `shellcheck` reports nothing new; `bats scripts/tests/plugins/tunnel.bats` is green.
- [ ] Commit: `fix(tunnel): timestamp and keep tunnel logs, bound reconnect attempts`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT start, stop or reload any real launchd agent, and do NOT ssh anywhere. Tests stub everything.
- Do NOT change the tunnel ports, the host alias, the `fuser` step in the vault wrapper, or `make clean-tmp`.
- Do NOT modify `scripts/lib/foundation/`.

## Review (Claude, 2026-10-23)

- Luna's change is in scope (5 files). `bats scripts/tests/plugins/tunnel.bats`: 18/18 pass; `shellcheck` reports nothing new.
- Pre-fix red check: the new test file fails 6 tests on the pre-fix tree (6, 7, 13, 16, 17, 18), which covers N1–N3.
- Test 16 only greps the wrapper text, so Claude ran the generated forward wrapper against a stub
  `autossh`. Each stderr line came out as `[2026-10-23T14:38:30Z] …`, and the arguments included
  `ConnectTimeout=10`. `_tunnel_forward_pattern` still matches the exec'd `autossh … -N ubuntu`.
- Landed as `5f9fb209`.
