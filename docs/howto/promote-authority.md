# Promote authority on the hub

At the physical console, stage the release commit using the verified stage wrapper (see [verified-stage.md](verified-stage.md)):
`/usr/local/libexec/k3dm/k3dm-verified-stage stage <commit> [--ref deploy/hub]`
Compare the printed commit and tips with GitHub on a second device (the iPad), then run:
`/usr/local/libexec/k3dm/k3dm-verified-stage run <commit> k3dm-promote-authority print-plan`
followed by:
`/usr/local/libexec/k3dm/k3dm-verified-stage run <commit> k3dm-promote-authority install OPERATOR_IDS=U0123ABCD,cli`
with your actual Slack IDs.

An empty `INSTALL_REF` now installs the checkout's `HEAD` (the installer no longer fetches `deploy/hub`); a non-empty `INSTALL_REF` must equal `HEAD`. Watch the installation and review the rendered configuration before enrolling. The installer checks the interpreter chain and staged files. Direct runs (such as `make promote-authority-install`) still execute from the checkout without the verified-stage environment scrub; always route installations through `k3dm-verified-stage run`.

Run `make promote-authority-enrol` outside tmux or screen (or `/usr/local/libexec/k3dm/k3dm-verified-stage run <commit> k3dm-promote-authority enrol`). Save the TOTP seed on your authenticator.
On your own device use `wrangler secret put PROMOTE_RELAY_HMAC_KEY` and paste the displayed key at the prompt.
Register the displayed public key as the repository's only write deploy key, enter a read token, and compare
the scanned SSH fingerprint against GitHub's published fingerprint on your own device before typing yes.
A successful first fetch creates the primed marker. Repeat enrol after an interruption.
Use `/usr/local/libexec/k3dm/k3dm-verified-stage run <commit> k3dm-promote-authority enrol --rotate KIND` for totp, relay-key, deploy-key, token or host-key.
Update the corresponding Worker secret or remove the old public key on rotation. Rotate exposed console secrets.
Use `make promote-authority-status` after enrol and after reboot.

For state loss, stop activity, retain the audit files and run:
`/usr/local/libexec/k3dm/k3dm-verified-stage run <commit> k3dm-promote-authority enrol --reset-state`
at the console. This archives state under state.lost.UTC and starts a new serial, replay and rate-limit history.
Credentials and the mirror survive. Uninstall (`/usr/local/libexec/k3dm/k3dm-verified-stage run <commit> k3dm-promote-authority uninstall`) removes the daemon and plist and retains credentials, configuration and state.

## Activation

Create a branch ruleset for refs/heads/deploy/hub blocking creation, update, deletion and non-fast-forward,
and a tag ruleset for refs/tags/hub-promote/* blocking creation, update and deletion.
The deploy key is the only bypass actor. Inspect `gh api repos/wilddog64/k3d-manager/keys` for any other write deploy key.
The authority pushes the branch first and the witness tag second. Until activation other writers can still move these refs.

Route ordinary TTY promotes through the authority, using the signed Slack card and /hermes-totp for cli requests.
Wait for the TTY routing follow-up and for Part 2e to land and pass live verification. Part 2e routes CVE pin commits
to a separate branch consumed as Argo CD's second source. A bypass for the CVE token would defeat the control.
Enable the production rules only after one week of authority promotes and the inventory and operation probes below pass.
For rollback, bootstrap, BREAK_GLASS or SKIP_CHECK_RUNS, disable the ruleset in GitHub's web UI from your own device,
run the existing command at the TTY, re-enable the ruleset and run `make promote-authority-status`.

## Credential inventory

Record the host, date, repository, documented scopes, Administration, deploy-key write and identity for the gh token,
SSH push key, Hermes tokens, webhook tokens and CVE GIT_WRITE_TOKEN. Replace the hub gh token with a fine-grained
token without Administration or deploy-key write. Record the replacement's actual permissions. The SSH push key
can still change release branches. Record which hub Cloudflare credentials can update Worker secrets. The two relay key
copies are PROMOTE_RELAY_HMAC_KEY on the Worker and /var/db/k3dm-promote/creds/relay_hmac.key (root:wheel 0600).
For each non-deploy credential, attempt to add a deploy key and change the probe ruleset. Record both HTTP statuses.
403 or 404 passes. Undo any 2xx immediately and resolve excess permissions before activation.

## Probe record

Configure matching probe rules for refs/heads/deploy/hub-ruleset-probe and refs/tags/hub-promote-probe/*.
Run `/usr/local/libexec/k3dm/k3dm-verified-stage run <commit> k3dm-promote-authority probe-deploy-key`. Clear a stale probe branch in the web UI before retrying.
Copy the seven deploy-key rows. Use the printed B, T, S, P and Q during the hold.
For each of gh-token, ssh-push-key and cve-write-token, select its own authenticated Git transport.
Use a credential helper for HTTPS tokens. Never put a token in the URL.
For **each** push, record the named ref with `git ls-remote "$remote" "$ref"` before and after,
the push exit code and the porcelain line for that ref. Run these five commands per credential during the hold:

```sh
git push --porcelain "$remote" "$S:$B"
git push --porcelain --force "$remote" "$Q:$B"
git push --porcelain "$remote" ":$B"
git push --porcelain --force "$remote" "$P:$T"
git push --porcelain "$remote" ":$T"
```

Branch preconditions are P and tag preconditions are S. After the daemon finishes and both refs are absent, run
`git push --porcelain "$remote" "$S:$B"` and `git push --porcelain "$remote" "$S:$T-$credential"` for each credential.
Expect 15 hold rows, six create rows and seven daemon rows. For rejection require the correct precondition, a nonzero exit,
a ref-specific ! with [remote rejected], and identical pre and post. Client refusal or absent update/delete refs are inconclusive.
For acceptance require the expected precondition, exit zero, the requested post and the correct flag (* create, space fast-forward,
+ forced, - deleted). Record absent or the full object ID for pre/post. Use this UTF-8 layout:

```
credential|branch-or-tag|operation|expected|observed|pre|post|porcelain
2e|landed COMMIT|live-verified YYYY-MM-DD
inventory|path-to-inventory|YYYY-MM-DD
```

Replace the first line with all 28 rows. Porcelain words are new, fast-forward, forced, deleted, remote-rejected or other.
Use `/usr/local/libexec/k3dm/k3dm-verified-stage run <commit> k3dm-promote-authority ruleset-verified PROBE_FILE=/absolute/path` and confirm the ruleset ID on the console.
Status shows “not asserted” before recording and “asserted YYYY-MM-DD” afterwards. This is a dated operator assertion.
Record live permissions, uid 501 socket access, denial to other users and denial of secret, state, mirror and code access,
plus status after reboot, on the actual hub.

## Runtime limits

The socket admits the operator UID, including malware running as that user. A stalled connection can occupy the serial
daemon for ten seconds and a promotion for about 220 seconds. After client exit 75 consult show and retry.
The Worker signs the record ID, nonce, approver, check, TOTP and time. A captured approval cannot be retargeted.
Replaying a signed wrong code can exhaust attempts on its record. A successful replay is refused once approved.
A forged unsigned deny can stop a promotion. The Worker asserts the Slack identity. Loss of either relay key
reduces the protection to TOTP and the public check. Root compromise defeats the authority. The integrity checks begin
after Python startup, and the rules protect remote refs while the hub checkout remains writable by its owner.

An install, upgrade or uninstall is a root-trust decision in the checkout: the installers source `scripts/lib/system.sh`
from the working tree, so a process running as the operator can change what runs under sudo.
Installs, enrolments, rotations, and state resets should always go through `k3dm-verified-stage stage` and `run` (see [verified-stage.md](verified-stage.md)).
The fresh-clone workaround only defeats tampering done before the clone; it does not defeat a watcher that edits the clone afterwards, nor does it provide the environment scrub (`CDPATH`, `SCRIPT_DIR`, `DEVELOPER_DIR`, `K3DM_WC_ROOT`, `PATH`, `BASH_ENV`) enforced by `k3dm-verified-stage run`.

### Hub evidence to record

For each GitHub and Cloudflare credential, enter the observed permission set and date. Capture permission names and HTTP status only.

| Credential | Permission to verify | Observed permissions, date and probe result |
| --- | --- | --- |
| Hub gh token | Fine-grained repository contents access, no Administration or deploy-key write | |
| Operator SSH push key | Release branch pushes, protected branch and tag probe refusals | |
| Hermes token(s) | Repository scope, Administration and deploy-key write | |
| Webhook token(s) | Repository scope, Administration and deploy-key write | |
| CVE GIT_WRITE_TOKEN | Pin branch write, protected branch and tag probe refusals after Part 2e | |
| Authority deploy key | Only write deploy key, only ruleset bypass | |
| Worker account credentials readable on the hub | Permission to change Worker secrets or code | |
| Relay signing key | Root file mode 0600, matching Worker secret provisioned from the operator's device | |

Record the host, macOS version and date with the probe output. Verify the operator UID can use
`bin/k3dm-promote-client status`, that another UID cannot connect, and that the operator cannot read the
private keys, list approval state, write the installed modules or read Git history from the mirror.
Reboot and repeat status. Record only exit status and permission diagnostics for secret reads.
