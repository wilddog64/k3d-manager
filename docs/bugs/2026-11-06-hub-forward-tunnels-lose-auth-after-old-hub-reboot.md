# Bug: the M4's hub tunnels authenticate through an agent that a reboot empties, so its dispatch metrics and logs stop reaching the hub

**Status:** LANDED `8e5f8831`, offline verification recorded 2026-11-06 (independent suite 25/25; 20 red on pre-fix; 13 mutants red). Live E3 and E4 PASSED; E4 2026-11-06 (see below). The P1 hub-cutover fix it followed landed as `76f34498`.
**Priority:** P2
**Severity:** medium. M4 dispatch and test metrics and shipped logs do not reach the M5 until someone loads the key by hand. The dispatch ledger is durable, so the numbers can be pushed again later; nothing is lost from the ledger.
**Approval:** operator, 2026-11-06: "go with your recommendation" (option 1, dedicated forward-only key). Dispatch: operator, 2026-11-06 ("yes you can dispatch tunnel fix to Luna now").
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

1. **Dedicated forward-only key.** A new passphrase-less key on the M4, used only by these two plists through `-i`, with `IdentitiesOnly=yes`. On the M5 its `authorized_keys` options are in "Chosen fix" below, so the key runs no command and reaches only those two ports. Survives a reboot with no one logged in.
2. **Load the existing key from the Keychain at login.** `ssh-add --apple-load-keychain` in a user agent, with `SSH_AUTH_SOCK` pointing at the launchd socket. No new key, but the tunnels depend on an unlocked login Keychain and a login after each boot, and the launchd agent would hold a full-access key.

Either way, the pre-check must test what the launchd job can do, not what a login session can do.

## Chosen fix (option 1)

Claude corrected the options first proposed. `restrict,port-forwarding,permitopen=...` alone still lets the key run a remote command, because `restrict` does not stop commands, and still lets it use `-R`. OpenSSH on both Macs is 10.2p1.

In `bin/hub-cutover`, inside `repoint_forwards`, in a new helper:

1. **Key on the old host.** Over `old_ssh`, if `~/.ssh/k3dm_hub_forward` is absent, run `ssh-keygen -q -t ed25519 -N '' -C k3dm-hub-forward -f ~/.ssh/k3dm_hub_forward`. Reuse an existing key. Read only the `.pub` file back. The private key never leaves the old host.
2. **Validate the public key** against `^ssh-ed25519 [A-Za-z0-9+/]+=* k3dm-hub-forward$` before writing it. Refuse anything else.
3. **Authorize on the new hub.** The script runs there, so edit its own `~/.ssh/authorized_keys`, keeping mode 600 and creating `~/.ssh` as 700 if needed. Append once per key, matching on the key body, so a re-run adds nothing:

   `command="/usr/bin/false",restrict,port-forwarding,permitopen="127.0.0.1:19094",permitopen="127.0.0.1:19100",permitlisten="127.0.0.1:1" ssh-ed25519 <body> k3dm-hub-forward`

   Build the two `permitopen` entries from `hub-push-forwards.list`, not from literals. `command=` blocks commands; `-N` opens no session, so the forward still works. `permitlisten` on privileged port 1 leaves no usable `-R` listener for a non-root user.
4. **Plist arguments.** In `change_forward`, add `-i <absolute path to the key on the old host>`, `-o IdentitiesOnly=yes` and `-o IdentityAgent=none` to `ProgramArguments`. Keep `-F /dev/null` and `BatchMode=yes`.
5. **Pre-check.** Replace the check at `bin/hub-cutover:290`, which runs in a login session, with `env -u SSH_AUTH_SOCK` plus the plist's identity options, run on the old host. The forced command makes an authenticated login exit 1 and failed authentication exit 255, so rc 255 fails the check and any other rc passes. The message names `~/.ssh/k3dm_hub_forward` and the host, and does not suggest `ssh-copy-id`.

Rollback restores the `.pre-cutover` plist as it does today. It leaves the key and the `authorized_keys` line in place, since they can do nothing beyond these two ports; `docs/howto/m5-hub-migration.md` says how to remove them.

**Rollout, after landing.** The operator runs `make hub-cutover-forwards` on the M5 from the release branch. The M4 keeps its login key for all other SSH.

## Correction 1 (Claude review of Luna's first attempt, 2026-11-06)

- If `authorized_keys` has no trailing newline, the new entry is appended to the last line, which breaks both keys and can lock out the existing login.
- The file is rewritten in place even when nothing changes, so an interruption can truncate it. Write a temp file in the same directory with mode 600, then replace; do not write when the key is present.
- `len(ports) != 2` hard-codes the count. Build the entries from the list and refuse only an empty one.
- A failed `for_each_forward install` lost its message. Print the same "rerun make hub-cutover-forwards" message on both failure paths.

## Files

- `bin/hub-cutover`
- `scripts/tests/bin/hub_cutover.bats`
- `docs/howto/m5-hub-migration.md`

## Acceptance

```yaml
must:
  - id: M1
    text: "With SSH_AUTH_SOCK unset and -F /dev/null, the command line the installed plist runs authenticates to the hub."
  - id: M2
    text: "After a reboot with no interactive login, localhost:19094 and localhost:19100 on the old hub answer."
  - id: M3
    text: "The cut-over pre-check fails, and names the problem, when the tunnel's own command cannot authenticate without an agent (paired positive control: it passes when it can)."
  - id: M4
    text: "After make hub-cutover-forwards, the new hub's authorized_keys holds the key with the forced command, restrict, a permitopen for each port in hub-push-forwards.list and the permitlisten option."
  - id: M5
    text: "Every line already in authorized_keys is unchanged after the run, including a last line with no trailing newline, and the new entry is on its own line."
must_not:
  - id: N1
    text: "No private key, passphrase or token appears in plist values, process arguments, logs or metrics."
  - id: N2
    text: "The dedicated key cannot open a shell or run a remote command on the hub, forward any port other than 19094 and 19100, or open a remote (-R) listener."
  - id: N3
    text: "A re-run does not add a second authorized_keys line for the same key and does not replace an existing key pair."
  - id: N4
    text: "A public key that fails validation is not written to authorized_keys, and the run fails."
  - id: N5
    text: "A re-run with the key present does not rewrite authorized_keys, and the file is never replaced by a partial write."
evidence:
  - {id: E1, proves: [M3], kind: offline, text: "BATS on bin/hub-cutover with an ssh stub that fails only when no agent socket is set; plist and pre-check arguments asserted. Red on the pre-fix commit."}
  - {id: E2, proves: [N1], kind: offline, text: "BATS parses the generated plist with plistlib and asserts the identity is a path only and no key material is present."}
  - {id: E5, proves: [M4, M5, N3, N4, N5], kind: offline, text: "BATS with HOME in BATS_TEST_TMPDIR (asserted first) and the ssh stub returning a captured-format public key: options asserted, a second run leaves one line, an invalid key leaves the file unchanged and rc non-zero."}
  - {id: E3, proves: [M1, N2], kind: live, text: "Claude, on the M4: env -u SSH_AUTH_SOCK with the plist's exact arguments succeeds; ssh with the key and a remote command runs only the forced command (rc 1, no output from the command asked for); -L to a third port is refused; -R is refused."}
  - {id: E4, proves: [M2], kind: live, text: "Operator reboots the M4; Claude checks both ports answer and a dispatch metrics push reaches the M5."}
interface:
  - "bin/hub-cutover (forward install and pre-check)"
  - "env: HOME, SSH_AUTH_SOCK, PATH (ssh, launchctl stubs)"
```

## Live E3, 2026-11-06, M4 to M5

Run from the M4 at about 07:00 PST with the plist's forward-only key.

| Check | Result |
| --- | --- |
| Remote command | rc 1, no output |
| PTY | refused |
| `-L` to 19094 | 200, no error |
| `-L` to ports 22 and 9091 | `administratively prohibited` |
| `-R` to 19198 and to 1 | rc 255, `remote port forwarding failed`; 0 M5 listeners on 19198 |
| Real tunnels | 19094 200; 19100 buildinfo 200 (`/ready` is 404 on that endpoint) |

`authorized_keys` on the M5 has one `k3dm-hub-forward` entry. An earlier E3 attempt had an invalid positive control because leftover test tunnels held the ports; they were killed and 0 remained before this run. E4 is open: it needs an M4 reboot with no Luna run active, then both ports up without a login and dispatch metrics reaching the M5.

## Live E4 result, 2026-11-06 (Claude, on `m4-air.local`, after the operator's reboot)

PASS. Both agents started at boot (07:33:22 PST, `runs = 1`, never exited). Each `ssh` runs with `-i ~/.ssh/k3dm_hub_forward -o IdentitiesOnly=yes -o IdentityAgent=none`, and `ssh-add -l` on the launchd socket says `The agent has no identities`, so nothing depends on a loaded key. `127.0.0.1:19094/-/ready` returned 200 and `127.0.0.1:19100/loki/api/v1/status/buildinfo` returned 200. `make dispatch-metrics` then moved `push_time_seconds{job="k3dm-dispatch"}` read on the M5 from 1793977826 to 1793979973, against a clock of 1793979974.
