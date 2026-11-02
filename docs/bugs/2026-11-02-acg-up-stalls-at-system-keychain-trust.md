# Bug: headless ACG cluster-up stalls at Vault CA trust until timeout

**Status:** OPEN — investigating; exact blocking process and cause unconfirmed
**Priority:** P2
**Severity:** medium — Slack-driven ACG bring-up failed; an interactive CA trust path may be a workaround but has not been verified for this incident
**Filed:** 2026-11-02
**Detected by:** operator screenshot and read-only investigation of job `c38c3855`
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/v1.5.0-bugfix-acg-up-vault-ca-pty-sudo.md`, `docs/bugs/v1.5.3-bugfix-acg-up-vault-ca-trust-no-soft.md`

## Evidence

On 2026-11-01, Slack job `c38c3855` created or updated the CloudFormation stack and proceeded into k3s installation. At step 4c its last meaningful log line was:

```text
INFO: [acg-up] Trusting Vault CA cert in macOS System Keychain (may prompt for sudo password)...
```

The job stayed there until the 3,300-second deadline and was killed. Slack failure analysis hypothesized an interactive sudo prompt; it did not observe the blocking process. The cleanup message says stale connections were removed, and `_run_cleanup` only invokes `pkill` for autossh and deletes a kubeconfig context; it does not delete the AWS stack. Current stack state is unknown: the read-only M5 `DescribeStacks` query returned `InvalidClientTokenId` on 2026-11-02.

The M5 had `/etc/sudoers.d/k3d-manager`, last modified 2026-11-01 09:41 PST, before this run. A current noninteractive sudo policy query for the exact CA trust command returned exit 0. The existing CA's `security verify-cert` returned 1. These observations do not prove the old job's process state or establish why the command blocked. The job's code path calls `_run_command --interactive-sudo --soft`; the checked-in runner selects `sudo -n` if stdin or stdout is not a TTY. The M5 unified log recorded three `sudo true` checks requiring a password at 20:03:52 PST, but a query for `add-trusted-cert` returned no matching entries; this does not identify the blocked process. Other possibilities include `security` or macOS authorization, a TTY/environment difference, or a different running code revision.

The operator states the failed run was before today's pull. Read-only checks on 2026-11-02 show the M5 now matches the release-branch remote head `8d9f5f0f`. Its default `~/.config/k3d-manager/machine-role` is missing; current `bin/cluster-up` requires the `hub` role or an explicit override, so a subsequent run may refuse at that earlier guard. No retry or host configuration change was performed during this investigation.

## Next investigation

Capture the real process tree and TTY/authorization state if this recurs; distinguish `sudo` waiting from `security` waiting, and confirm the deployed webhook and job environment. Establish a bounded, safe failure mode for headless CA trust, preserving certificate verification and not assuming that a pull alone fixes the stall. Verify stack state after sandbox credentials are restored before deciding whether to reuse or clean up infrastructure. See `docs/issues/2026-11-02-acg-up-job-c38c3855.md` for exact diagnostic output.
