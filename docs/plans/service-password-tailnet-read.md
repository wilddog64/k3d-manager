# v1.45.0 — Service passwords from a Windows or Linux machine: a Tailscale-only SSH key that can only print them

**Status:** PLANNED — operator asked for it 2026-11-07; spec only, dispatch when `k3d-manager-v1.45.0` is cut
**Priority:** P2 (break-glass read of rotated service passwords from a machine that is not one of the Macs; SSO still works)
**Approval:** operator 2026-11-07: "for encrypted service password solution, talescale another function is for non Mac system like windows or linux can reach hub and show service passwords securely". Spec only. Installing Tailscale on the hub or on any client, enabling it, and every live step need a separate operator go.
**Release:** v1.45.0 (branch `k3d-manager-v1.45.0`), plan 3
**Depends on:** none in code. It is a sibling of `docs/plans/v1.45.0-service-password-travel-bundle.md`, which names this as its pull option under "Related, not in this plan". Shares tailnet enrollment of the hub with `docs/plans/v1.48.0-tailscale-break-glass-access.md`; whichever lands first enrolls the hub.

## Problem

The travel bundle (plan 2) gives the Macs an age-encrypted copy of the `make show-service-passwords` output. Its
identity lives in the macOS login Keychain and the bundle travels over iCloud Drive, so it only serves the Macs on the
operator's Apple ID. A Windows or Linux machine cannot read service passwords at all today:

- `make show-service-passwords` runs only on the hub. It reads the Vault root token from `secrets/vault-root`
  through the `k3d-k3d-cluster` context.
- The hub has no route from outside the home network. Cloudflare publishes the apps, never Vault or SSH.

The passwords must never travel in plaintext, and never reach a page, Slack, email or a log (operator, 2026-11-07:
"the exception should not explore on the page ... that's security concern").

## Design

The non-Mac machine **pulls** over the tailnet. The hub runs the existing target and the output goes back through
the SSH channel to the caller's terminal. Nothing is stored, rendered or relayed.

```
Windows / Linux (OpenSSH client, Tailscale)
  → tailnet: identity login with MFA, device approval, a grant to the hub on tcp:22 only
  → hub sshd (macOS Remote Login)
  → authorized_keys line: from=<tailnet range>, restrict, command=bin/k3dm-password-read
  → make -s show-service-passwords → stdout over SSH → the caller's terminal
```

There are two independent gates. The tailnet identity and device must be allowed by the grant. The SSH key must
match a line that is only valid from tailnet addresses and can run only the read command.

### T1 — the read command (hub): `bin/k3dm-password-read`

- `set -euo pipefail`. It ignores `SSH_ORIGINAL_COMMAND` completely: whatever the client asks for, it runs only
  this. It sets its own `PATH` (`/opt/homebrew/bin:/usr/bin:/bin`) and repo root, resolved from its own path, never
  from the current directory.
- It refuses unless `SSH_CONNECTION` is set and the client address is in `100.64.0.0/10` (the tailnet range). This
  backs up the `from=` option.
- It runs `make -s -C <repo> show-service-passwords` and streams its stdout to the caller. It never writes the
  output to a file, a temporary file, a log or a metric.
- It writes one audit line per read to `${K3DM_LOG_DIR:-$HOME/.local/share/k3d-manager/logs}/password-read.log`
  (mode 600). The line holds the UTC time, the key name (T2), the client address and the exit code, never any output.
  It pushes `k3dm_password_read_total{key="<name>",result="ok|refused|error"}` through the existing Pushgateway path.
- It exits with the exit code of `show-service-passwords`, so a hub-side failure is visible to the caller.

### T2 — keys (hub): `make password-read-add-key` / `make password-read-remove-key`

- `make password-read-add-key NAME=<name> KEY="<public key>"` appends one line to `~/.ssh/authorized_keys`:
  `from="100.64.0.0/10",restrict,command="<repo>/bin/k3dm-password-read <name>" <type> <base64> k3dm-password-read:<name>`.
  `restrict` disables the pty and agent, port and X11 forwarding. Only the read command can run.
- `NAME` must match `^[a-z0-9-]{1,32}$`. The key type must be `ssh-ed25519` or `sk-ssh-ed25519@openssh.com` (a
  FIDO2 key; the how-to recommends it), with a base64 body and nothing else. A key already present in
  `authorized_keys` on any line is refused, so a full-access key can never also become a read key, or the reverse.
- It writes through a temp file in `~/.ssh` and `mv`, keeps the mode at 600, and leaves every other line
  byte-for-byte unchanged.
- `make password-read-remove-key NAME=<name>` removes only the line tagged `k3dm-password-read:<name>`.
- `make password-read-list` prints the names, the key types and the SHA256 fingerprints, never the key bodies.

### T3 — tailnet (operator, documented, not automated)

The how-to gives the steps; no code changes tailnet policy:

- The hub (M5) and each client join the tailnet. Identity login uses MFA, and device approval is on.
- A deny-by-default grant: source is the operator's named client devices, destination is the hub, port `tcp:22`
  only. Remove any catch-all rule first, as `docs/plans/v1.48.0-tailscale-break-glass-access.md` D1 requires.
- No Funnel, no Serve, no exit node, no subnet routes. This plan does not use Tailscale SSH: the hub keeps macOS
  OpenSSH, which works the same with any Tailscale variant.
- Pin the hub host key on the client: the first connection is made on the home LAN, or the fingerprint is compared
  with `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` read on the hub.

### T4 — the client side (any OS with OpenSSH)

`docs/howto/service-password-tailnet-read.md` (new) shows, for Windows PowerShell (the built-in OpenSSH client) and
for Linux:

- Generate the key: `ssh-keygen -t ed25519-sk` with a FIDO2 key, or `ed25519` with a passphrase. Send only the
  `.pub` file to the hub.
- Read: `ssh -T <user>@<hub tailnet name>`. Typing a command changes nothing.
- Do not redirect the output to a file or paste it into chat. Clear the terminal scrollback afterwards.
- Lose a device: remove its key with `password-read-remove-key`, remove the device from the tailnet, and rotate the
  service passwords.

### Related, not in this plan

- A browser path (an HTTP endpoint on the tailnet) is rejected. It adds a server that holds passwords in memory and
  a page that could render them.
- An age bundle for Linux and Windows is rejected for now. It needs a key store per OS and a delivery folder that
  OS can read, and the pull already covers these machines while the hub is up.

## Files

- `bin/k3dm-password-read` (new)
- `scripts/plugins/password_read.sh` (new): `password_read_add_key`, `password_read_remove_key`, `password_read_list`
- `Makefile` (the three targets, with help text)
- `scripts/tests/plugins/password_read.bats` (new)
- `docs/howto/service-password-tailnet-read.md` (new), linked from the README How-To section
- `CHANGELOG.md` (one `### Added` bullet under `[Unreleased]`)

## What NOT to Do

- Do not install, enroll or configure Tailscale, enable Remote Login, or touch the real `~/.ssh/authorized_keys`,
  the hub or the Pushgateway. The operator runs E2 and E3.
- Never write the output of `show-service-passwords` to a file, a log, `/tmp`, a metric label or argv.
- Do not change `show-service-passwords`, any rotator, `sshd_config` or any tailnet policy file.
- Do not add an HTTP endpoint, a Slack, email or webhook path, or a pty.
- Tests use a scratch `HOME` (with its own `.ssh/authorized_keys`), a stub `make show-service-passwords`, and
  `SSH_CONNECTION` values set by the test. The Pushgateway is `127.0.0.1:9`. A fixture first asserts it points at the
  scratch `HOME`, not the real one. `ssh-keygen` is the real binary.
- Write the must_not tests first and show them red on the pre-fix tree.
- Do not edit CLAUDE.md, `memory-bank/` or `docs/roadmap.md`. Do not commit to `main`, create a PR or skip hooks.

## Acceptance

```yaml
interface:
  - "bin/k3dm-password-read <name>  (env: SSH_CONNECTION, SSH_ORIGINAL_COMMAND, HOME, K3DM_LOG_DIR)"
  - "make password-read-add-key NAME=<name> KEY=\"<type> <base64>\"; make password-read-remove-key NAME=<name>; make password-read-list"
  - "env: HOME (scratch, with .ssh/authorized_keys); PATH stub for make show-service-passwords; real ssh-keygen; Pushgateway 127.0.0.1:9"
must:
  - id: M1
    text: "With SSH_CONNECTION from a 100.64.0.0/10 address, bin/k3dm-password-read prints exactly the show-service-passwords output and exits with its exit code."
  - id: M2
    text: "add-key appends exactly one line with from=\"100.64.0.0/10\", restrict and command=\"<repo>/bin/k3dm-password-read <name>\", tagged k3dm-password-read:<name>; every other line stays byte-for-byte; the file stays mode 600."
  - id: M3
    text: "remove-key removes only that name's line; list prints names, types and SHA256 fingerprints and no key body."
  - id: M4
    text: "Each read appends one audit line (time, name, client address, exit code) to password-read.log, mode 600."
must_not:
  - id: N1
    text: "Any SSH_ORIGINAL_COMMAND (for example 'sh', 'cat ~/.ssh/id_ed25519', 'make anything-else') runs only show-service-passwords (paired control: M1, the same call with no SSH_ORIGINAL_COMMAND prints the output)."
  - id: N2
    text: "A client address outside 100.64.0.0/10, or no SSH_CONNECTION, is refused with nonzero exit and show-service-passwords is never called (paired control: M1)."
  - id: N3
    text: "No password string from the stub output appears in any file under HOME, K3DM_LOG_DIR or TMPDIR, or in the argv of any process (paired control: M1 shows the read prints that same string)."
  - id: N4
    text: "add-key refuses a malformed name, a key type other than ssh-ed25519 or sk-ssh-ed25519@openssh.com, extra fields or options in KEY, or a key already present on any line; authorized_keys is unchanged byte-for-byte."
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    kind: offline
    what: "bats with a scratch HOME and a stub show-service-passwords; must_not tests red on the pre-fix tree."
  - id: E2
    proves: [M1, M4]
    kind: live
    what: "Operator: from a Linux or Windows machine on another network, ssh -T over the tailnet prints the same passwords as make show-service-passwords on the hub, and the audit line appears."
  - id: E3
    proves: [N1, N2]
    kind: live
    what: "Operator: 'ssh -T <hub> sh' still prints only the passwords; the same key from the home LAN address is refused; a non-granted tailnet device cannot open tcp:22 on the hub."
```
