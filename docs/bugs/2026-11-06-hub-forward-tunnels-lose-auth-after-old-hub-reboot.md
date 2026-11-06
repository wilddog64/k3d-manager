# Bug: the M4's hub tunnels authenticate through an agent that a reboot empties, so its dispatch metrics and logs stop reaching the hub

**Status:** OPEN — root cause proven; option 1 chosen; dispatch follows the P1 hub-cutover fix, since both edit `bin/hub-cutover`
**Priority:** P2
**Severity:** medium. M4 dispatch and test metrics and shipped logs do not reach the M5 until someone loads the key by hand. The dispatch ledger is durable, so the numbers can be pushed again later; nothing is lost from the ledger.
**Approval:** operator, 2026-11-06: "go with your recommendation" (option 1, dedicated forward-only key).
**Filed:** 2026-11-06
**Detected by:** Claude (exit 255 in `launchctl list` after the M4 reboot for D3 Part B)
**Affected:** `bin/hub-cutover` (tunnel plist in `:220-251`, pre-check in `:282`), `com.k3d-manager.hub-pushgateway-port-forward`, `com.k3d-manager.hub-loki-port-forward`
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-10-30-hub-cutover-leaves-old-hub-producers-on-old-pushgateway.md` (introduced the tunnels); `docs/bugs/2026-10-26-hermes-launchagent-github-fetch-misses-ssh-agent.md` (same class on another agent); `docs/bugs/2026-11-06-hub-cutover-old-hub-agents-return-on-reboot.md` (same reboot)

## Observed failure

Captured on the M4 (`m4-air.local`), 2026-11-05 20:33 PST:

- `launchctl list`: both agents show no pid and last exit 255. `launchctl print`: `runs = 251`, `state = spawn scheduled`.
- Both logs end in `cliang@m5-air.local: Permission denied (publickey,password,keyboard-interactive).`, 251 times each. The M4 booted at 19:49 PST, about 44 minutes before the capture, so every run since boot has failed.
- `curl http://localhost:19094/metrics` from the M4: http 000. The last M4 `k3dm-dispatch` push the M5 has is 19:45:07 PST, before the reboot.
- `bin/k3dm-dispatch-metrics` logs `dispatch metrics push failed: timed out` and `Connection refused` in `worktrees/metrics.log`.

## Root cause

Proven by reproducing with the agent's own socket:

| Check | Result |
|---|---|
| `launchctl print` environment of the job | `SSH_AUTH_SOCK` = `/var/run/com.apple.launchd.Jc6Zemaos6/Listeners` |
| `ssh-add -l` on that socket | `The agent has no identities.` |
| `ssh -F /dev/null -o BatchMode=yes m5-air.local true` on that socket | `Permission denied` |
| The same command with no agent at all | `Permission denied` |
| The same command from Claude's session (socket under `~/.ssh/agent/`, one key loaded) | rc 0 |
| `ssh-keygen -y -P ''` on `~/.ssh/id_ed25519` | rc 255: the only key has a passphrase |

The plist runs `/usr/bin/ssh -F /dev/null -N -o BatchMode=yes …` with no identity. `-F /dev/null` skips `~/.ssh/config`, so `UseKeychain` is not read either. It can only authenticate through an agent, and after a reboot the launchd agent is empty.

The cut-over pre-check (`bin/hub-cutover:282`) runs `ssh` over a login session, so it reports success with an agent the launchd job does not have. Not yet read: whether that pre-check, run from `old_ssh`, can see an agent at all in the operator's setup.

## Fix

Choose one (operator decision, Claude's recommendation first):

1. **Dedicated forward-only key.** A new passphrase-less key on the M4, used only by these two plists through `-i`, with `IdentitiesOnly=yes`. On the M5 its `authorized_keys` line is `restrict,port-forwarding,permitopen="127.0.0.1:19094",permitopen="127.0.0.1:19100"`, so the key gives no shell and reaches only those two ports. Survives a reboot with no one logged in.
2. **Load the existing key from the Keychain at login.** `ssh-add --apple-load-keychain` in a user agent, with `SSH_AUTH_SOCK` pointing at the launchd socket. No new key, but the tunnels depend on an unlocked login Keychain and a login after each boot, and the launchd agent would hold a full-access key.

Either way, the pre-check must test what the launchd job can do, not what a login session can do.

## Acceptance

```yaml
must:
  - id: M1
    text: "With SSH_AUTH_SOCK unset and -F /dev/null, the command line the installed plist runs authenticates to the hub."
  - id: M2
    text: "After a reboot with no interactive login, localhost:19094 and localhost:19100 on the old hub answer."
  - id: M3
    text: "The cut-over pre-check fails, and names the problem, when the tunnel's own command cannot authenticate without an agent (paired positive control: it passes when it can)."
must_not:
  - id: N1
    text: "No private key, passphrase or token appears in plist values, process arguments, logs or metrics."
  - id: N2
    text: "If a dedicated key is chosen, it cannot open a shell on the hub or forward any port other than 19094 and 19100."
evidence:
  - {id: E1, proves: [M3], kind: offline, text: "BATS on bin/hub-cutover with an ssh stub that fails only when no agent socket is set; plist and pre-check arguments asserted. Red on the pre-fix commit."}
  - {id: E2, proves: [N1], kind: offline, text: "BATS parses the generated plist with plistlib and asserts the identity is a path only and no key material is present."}
  - {id: E3, proves: [M1, N2], kind: live, text: "Claude, on the M4: env -u SSH_AUTH_SOCK with the plist's exact arguments succeeds; ssh with the key and a remote command is refused; -L to a third port is refused."}
  - {id: E4, proves: [M2], kind: live, text: "Operator reboots the M4; Claude checks both ports answer and a dispatch metrics push reaches the M5."}
interface:
  - "bin/hub-cutover (forward install and pre-check)"
  - "env: HOME, SSH_AUTH_SOCK, PATH (ssh, launchctl stubs)"
```
