# Bug: `_agent_audit` bare-sudo check has no way to allow a remote `sudo`

**Filed:** 2026-10-04, Claude
**Branch:** `fix/agent-audit-remote-sudo-marker`
**Status:** remote-sudo marker FIXED in `44e7e8d` (#57). Recurrence (2026-10-05, `_run_command` flag false positive) FIXED `16908e5`.
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

## Recurrence — `_run_command`'s own `*-sudo` flags trip the check (2026-10-05)

**Filed:** 2026-10-05, Claude
**Branch:** `fix/agent-audit-sudo-flag-false-positive`
**Status:** FIXED — Codex, verified by Claude 2026-10-05: `_agent_audit` matches `sudo` only as a command word. 46/46 BATS; restoring `\bsudo` turns the new prefix test red.

### Observed

k3d-manager `4547e696` added this line to `scripts/lib/providers/k3s-hostinger.sh`:

```bash
       if ! _run_command --interactive-sudo --quiet --soft -- install -m 644 \
```

The pre-commit `_agent_audit` blocked it as a bare sudo call. In `\bsudo[[:space:]]`, `\b` matches
between `-` and `s`, so `--interactive-sudo ` (and `--prefer-sudo `, `--require-sudo `) match. The
`_run_command` exemption only covers lines that **start** with `_run_command`, so the wrapper call
is flagged whenever something precedes it: `if !`, `x=$(`, `|| `, `&& `. Claude had to reshape the
k3d-manager code to get past the hook.

### Fix

Match `sudo` only when it is a command word, not when it ends a hyphenated flag.

**File 1 — `scripts/lib/agent_rigor.sh`**, in `_agent_audit`'s bare-sudo pipeline. Replace

```bash
            | grep -E '\bsudo[[:space:]]' \
```

with

```bash
            | grep -E '(^|[^-[:alnum:]_])sudo[[:space:]]' \
```

Leave the three `grep -Ev` exemption lines unchanged.

**File 2 — `scripts/tests/lib/agent_rigor.bats`.** Add three tests after
`_agent_audit still flags sudo when the marker is not the trailing comment`, in the same style:

1. `_agent_audit allows _run_command sudo flags after a prefix`. Append three lines, then assert
   `status -eq 0`:
   `   if ! _run_command --interactive-sudo --quiet -- install -m 644 a b; then :; fi`,
   `   _out=$(_run_command --prefer-sudo -- ls)`,
   `   true && _run_command --require-sudo -- mkdir /tmp/x`.
2. `_agent_audit flags sudo after a pipe`. Append `   echo x | sudo tee /etc/x`, then assert
   `status -ne 0` and output contains `bare sudo call`.
3. `_agent_audit flags sudo after a quote`. Append `   ssh host "sudo reboot"`, then assert
   `status -ne 0`.

**File 3 — `CHANGE.md`**, under `## [Unreleased]` → `### Fixed` (create the subsection): one entry
saying the bare-sudo audit no longer flags `_run_command`'s `--prefer-sudo`, `--require-sudo` and
`--interactive-sudo` flags when the call does not start the line, and that a real `sudo` after a
pipe, quote or `&&` is still flagged.

### Rules

- Modify only Files 1–3 and this doc's status line. Do not commit or push; leave changes unstaged.
- Run and paste: `shellcheck scripts/lib/agent_rigor.sh` (no new warnings against `HEAD`) and
  `bats scripts/tests/lib/agent_rigor.bats` (all green).
- Mutation: snapshot `agent_rigor.sh` to `$TMPDIR`, restore the `\bsudo[[:space:]]` pattern, show
  test 1 going red, restore, and prove the restore with `cmp`. Tests 2 and 3 must pass under both
  patterns.

### Done when

All of `agent_rigor.bats` passes, and the mutation turns test 1 red.
