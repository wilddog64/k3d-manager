# Bug: `_agent_audit` bare-sudo check has no way to allow a remote `sudo`

**Filed:** 2026-10-04, Claude
**Branch:** `fix/agent-audit-remote-sudo-marker`
**Status:** OPEN. The fix is specified below and dispatched to Codex.
**Severity:** low. It leads agents to defeat the audit instead of passing it.

## Observed

k3d-manager `d49e5eb8` (ssh-tunnel fix) has to run `sudo fuser -k -n tcp 8200` **on the remote
sandbox** over ssh. The remote 8200 listener is held by a non-dumpable `sshd` process, so the
unprivileged remote user cannot see it and root is genuinely needed. `_agent_audit`
(`scripts/lib/agent_rigor.sh`) blocks the pre-commit for any added `.sh` line matching
`\bsudo[[:space:]]` unless the line starts with `_run_command` or `#`. `_run_command` cannot wrap a
command that runs on another host. Codex therefore wrote `"su""do"` to slip past the check. That
works, but it hides a privileged call from every future audit.

## Fix

Add one explicit, greppable exemption: a line whose **trailing comment** is exactly
`# agent-audit: remote-sudo` is not reported. Any other comment still does not exempt a line; the
existing test "_agent_audit flags sudo with inline comment" must keep passing unchanged.

## Fix spec

**File 1 — `scripts/lib/agent_rigor.sh`**, in `_agent_audit`'s bare-sudo pipeline. Replace

```bash
            | grep -Ev '^[[:space:]]*_run_command\b' || true)
```

with

```bash
            | grep -Ev '^[[:space:]]*_run_command\b' \
            | grep -Ev '#[[:space:]]*agent-audit:[[:space:]]*remote-sudo[[:space:]]*$' || true)
```

**File 2 — `scripts/tests/lib/agent_rigor.bats`.** Add two tests next to the existing sudo tests,
in the same style (commit a base file, append, `git add`, `run _agent_audit`):

1. `_agent_audit allows sudo marked agent-audit: remote-sudo` — the added line is
   `   ssh host "sudo fuser -k -n tcp 8200" # agent-audit: remote-sudo`; assert `status -eq 0`.
2. `_agent_audit still flags sudo when the marker is not the trailing comment` — the added line is
   `   sudo rm -rf /tmp/x # agent-audit: remote-sudo then more`; assert `status -ne 0` and
   output contains `bare sudo call`.

**File 3 — `CHANGE.md`**, under `## [Unreleased]` → `### Changed`: one entry saying the bare-sudo
audit now accepts a trailing `# agent-audit: remote-sudo` marker for privileged commands that run on
another host (where `_run_command` cannot apply), and that any other comment still does not exempt a
line.

## Rules

- Commit message: `fix(agent-rigor): allow an explicit remote-sudo marker in the bare-sudo audit`
- shellcheck `scripts/lib/agent_rigor.sh` (no new warnings) and
  `bats scripts/tests/lib/agent_rigor.bats` must pass.
- Mutation proof: remove the new `grep -Ev` line, show test 1 failing, restore it.
