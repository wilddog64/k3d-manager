# Hermes LaunchAgent cannot fetch GitHub without the interactive SSH agent

**Status:** VERIFIED — offline fix landed in `3aae7adc`; LaunchAgent-context live verification pending
**Priority:** P2
**Fix commit:** `3aae7adc182094630ca4d93a9e439fd262ce5f65`
**Date:** 2026-10-26
**Branch:** `k3d-manager-v1.43.9`
**Approval:** explicit 2026-10-26 (operator: “can you deep dive into it and file a bug if necessary”)
**Related:** `docs/issues/2026-10-26-v1439-retrieval-dashboard-no-data.md`; `docs/bugs/2026-09-30-vectordb-index-never-refreshes-automatically.md`

## Impact

Hermes runs from the macOS LaunchAgent `com.k3d-manager.hermes` on M4. Each poll runs
`git fetch --quiet origin <branch>` before it can refresh the index. When that fetch fails,
`_refresh_index` records a failed run and does not call `_maybe_probe_retrieval`; the retrieval
metrics therefore remain at their previous values even though the Grafana panels are present.
Manual Git access from the logged-in shell works, which provides an operator workaround.

## Evidence collected on m4-air

The launchd domain has no `SSH_AUTH_SOCK`; the interactive SSH shell does:

```text
launchd SSH_AUTH_SOCK=
interactive SSH_AUTH_SOCK=/var/run/com.apple.launchd.hO0afhaYBQ/Listeners
```

`ssh-add -l` in the interactive shell returned 0. A manual remote read succeeded:

```text
$ git ls-remote --heads origin refs/heads/k3d-manager-v1.43.9
92481d8783ae8ab7ba05cbb53e89e63afc852dbd	refs/heads/k3d-manager-v1.43.9
ls_remote_rc=0
```

The same read with the interactive agent removed failed:

```text
$ env -u SSH_AUTH_SOCK GIT_SSH_COMMAND="/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8" git ls-remote --heads origin refs/heads/k3d-manager-v1.43.9
git@github.com: Permission denied (publickey).
fatal: Could not read from remote repository.
Please make sure you have the correct access rights
and the repository exists.
no_agent_ls_remote_rc=128
```

The installed LaunchAgent plist sets `PATH`, repo root, and Hermes options but does not set
`SSH_AUTH_SOCK`. The logged Hermes errors include repeated:

```text
vectordb index refresh skipped: git fetch failed: ssh: connect to host github.com port 22: Undefined error: 0
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
```

The exact historical `Undefined error: 0` was not reproduced during this check; the controlled
no-agent reproduction fails with `Permission denied (publickey)`. This establishes an unattended
authentication gap, while leaving open whether transient network errors also contribute.

Code-path inspection: `_refresh_index` initializes the result as `failed`, raises when `git fetch`
returns nonzero, and only invokes `_maybe_probe_retrieval` from its success/no-op path. The
retrieval probe is therefore suppressed by fetch/authentication failure. On this check, the
Pushgateway still held `k3dm_vectordb_retrieval_probe_last_success_timestamp_seconds` at
`1.793058195187118e+09` (2026-10-26 23:43:15 UTC), while Hermes state had null retrieval attempt
and success fields. The LaunchAgent had been restarted at 2026-10-26 23:47:30 PDT; a fresh probe
after that restart was not confirmed.

## Root cause

The Hermes LaunchAgent does not receive the SSH agent socket available to the interactive shell.
The authenticated GitHub fetch works in the user shell but fails when run without that agent. The
LaunchAgent plist currently has no unattended GitHub credential strategy.

## Recommended follow-up

1. Give the Hermes LaunchAgent a reliable, noninteractive, least-privilege way to read the tracked
   GitHub branch. Do not copy the current session's ephemeral `SSH_AUTH_SOCK` path into the plist,
   and do not put a private key or token in plist values, process arguments, logs, or metrics.
2. Add an installer/preflight check that verifies GitHub read access from the same environment the
   LaunchAgent will use, with a clear failure reason.
3. Keep failed fetches visible in the ingestion metrics and logs; make the retrieval dashboard's
   last-success age make stale data clear.
4. Add an offline regression test for the selected LaunchAgent credential setup and its missing-
   credential failure path. Verify a live fetch only after a specific fix is implemented.

No credentials were printed, copied, or changed. No live pytest, deployment, or cluster action was
run during this investigation.

## Keychain-backed SSH check

A bounded M4 check showed that the macOS SSH client can read the GitHub branch from Keychain
without the interactive agent when explicitly asked to use Keychain:

```text
$ env -u SSH_AUTH_SOCK GIT_SSH_COMMAND="/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 -o UseKeychain=yes" git ls-remote --heads origin refs/heads/k3d-manager-v1.43.9
fd745ac7275e3638879b47ae5fa77cdf3881957c	refs/heads/k3d-manager-v1.43.9
use_keychain_only_rc=0
```

This narrows the candidate implementation: use Apple's `/usr/bin/ssh` with `UseKeychain=yes`
for the LaunchAgent fetch when no explicit `GIT_SSH_COMMAND` override is supplied. Do not copy the
interactive socket path into the plist. This was a direct remote-read diagnostic, not a Hermes
LaunchAgent-context success test; verify that after the code change is installed.

## Dispatch approval and scope

**Dispatch approval:** explicit 2026-10-26 (operator: “can you dispatch this task?”)

## Files

- `bin/k3dm-hermes`
- `scripts/tests/bin/test_retrieval_probe.py`
- `docs/guides/hermes.md`

## Acceptance

- **must:** On macOS, Hermes' `git fetch` uses `/usr/bin/ssh` with `UseKeychain=yes` and noninteractive behavior when `GIT_SSH_COMMAND` is not already set.
- **must:** Preserve an explicit caller-provided `GIT_SSH_COMMAND`; do not require or embed a session-specific `SSH_AUTH_SOCK` path.
- **must:** Add offline tests proving the fetch environment uses the Keychain option without an agent and that explicit overrides are preserved.
- **must:** Do not pass macOS-only SSH options on non-macOS test/runtime paths.
- **must:** Keep fetch failure advisory to the Hermes cycle and keep its diagnostic concise.
- **must:** Document the unattended Keychain-backed fetch behavior and a safe LaunchAgent-context verification command.
- **must_not:** Put a private key, passphrase, GitHub token, or credential output in plist values, argv, logs, or metrics; tests must not contact GitHub, Keychain, Pushgateway, or a cluster.
- **evidence:** `pytest scripts/tests/bin/test_retrieval_probe.py -q` passes; Ruff passes for changed Python files; operator can verify `git ls-remote` from a LaunchAgent-like environment with `SSH_AUTH_SOCK` unset after install.

No live fetch, LaunchAgent restart, live pytest, deployment, or cluster action is authorized by this dispatch.

## Independent review and landing

Implementation `3aae7adc` is landed on `k3d-manager-v1.43.9` and pushed. It sets
macOS Keychain-backed noninteractive SSH options only for the tracked-branch
fetch and only when `GIT_SSH_COMMAND` is absent. Explicit overrides and
non-macOS behavior are preserved. No session socket, credential, or plist change.

Independent gates after rebase: 369 Python tests passed (retrieval probe, prior
art, and all Hermes tests); Ruff passed. The three new environment regressions
failed on the pre-fix implementation and passed with the fix; the focused suite
passed 11/11. VectorDB/negation BATS passed 17/17. Staged audit/lint, diff checks,
and doc links passed. Full output and recovered tool/environment limitations:
`docs/issues/2026-10-26-dispatch-closeout-review.md`.

No live fetch, LaunchAgent restart, deployment, or live evaluation was performed.
The earlier Keychain read diagnostic is historical evidence, not live verification
of this installed fix. Operator follow-up: after installing/restarting the
approved version, use the guide's no-agent `git ls-remote` check under the normal
LaunchAgent account with an unlocked login Keychain, then confirm a Hermes poll
fetch/index refresh. Keep VERIFIED until that runtime evidence is supplied.
