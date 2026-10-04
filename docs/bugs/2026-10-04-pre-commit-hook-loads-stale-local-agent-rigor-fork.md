# Bug: k3d-manager's pre-commit hook loads a stale local `agent_rigor.sh` fork, not lib-foundation's

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN. The fix is specified below and dispatched to Codex.
**Severity:** low. Audit fixes made upstream never reach this repo's commits.

## Observed

lib-foundation PR #57 (`44e7e8d`) added the `# agent-audit: remote-sudo` marker to `_agent_audit`,
and k3d-manager pulled it into the subtree (`ce1164eb`, tree-equal to `44e7e8d`). The marker still
does not work here. Every caller loads `scripts/lib/agent_rigor.sh`, a local copy last changed in
v1.8.0 (2026-06-26), not `scripts/lib/foundation/scripts/lib/agent_rigor.sh`:

- `.githooks/pre-commit:60` (the active hook, `core.hooksPath=.githooks`)
- `scripts/hooks/pre-commit:31`
- `scripts/lib/system.sh:29`
- `scripts/tests/lib/agent_rigor.bats:11`

## How the fork differs from upstream

| Behaviour | Local fork | Upstream |
|---|---|---|
| `# agent-audit: remote-sudo` marker | missing | present |
| `_agent_lint` file set | `*.sh` | `*.sh *.js *.md`. Only runs when `ENABLE_AGENT_LINT=1` and `AGENT_LINT_AI_FUNC` is set. |
| BATS audit skips `scripts/lib/acg/*` | yes | no. The directory no longer exists here (lib-acg was absorbed), so the skip is dead code. |

Claude trial (2026-10-04): with `scripts/lib/agent_rigor.sh` replaced by the shim below, all 9 tests in
`scripts/tests/lib/agent_rigor.bats` pass. The file was restored afterwards and checked with `cmp`. The
upstream file reads `${SCRIPT_DIR}/etc/agent/if-count-allowlist` and `lint-rules.md`, and both exist in
`scripts/etc/agent/`. The hardcoded-IP allowlist is passed via `AGENT_IP_ALLOWLIST` in both versions.

Out of scope: `scripts/etc/agent/bare-sudo-allowlist` is read by neither version; leave it.

## Fix spec

### Commit 1 — retire the fork

**File 1 — `scripts/lib/agent_rigor.sh`.** Replace the whole file with:

```bash
# shellcheck shell=bash
# Shim: the agent-rigor library lives in lib-foundation. Edit it upstream, then subtree pull.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/foundation/scripts/lib/agent_rigor.sh"
```

**File 2 — `scripts/tests/lib/agent_rigor.bats`.** Append one test in the file's existing style
(commit a base file, append a line, `git add`, `run _agent_audit`). Name it
`_agent_audit: k3d-manager honours the lib-foundation remote-sudo marker`. The added line is
`   ssh host "sudo fuser -k -n tcp 8200" # agent-audit: remote-sudo`, and the test asserts
`[ "$status" -eq 0 ]`. Add a second test, `scripts/lib/agent_rigor.sh is a shim to the subtree
copy`, that greps the file for `foundation/scripts/lib/agent_rigor.sh` and asserts that
`grep -c '^_agent_audit()' scripts/lib/agent_rigor.sh` prints `0`. Use `run` + `$status`/`$output`;
no bare `!`.

**File 3 — `CHANGELOG.md`**, under `## [Unreleased]`, in the existing `### Changed` subsection (create
it if absent): one entry saying `scripts/lib/agent_rigor.sh` is now a shim to the lib-foundation copy,
which brings in the `# agent-audit: remote-sudo` marker. Say that the local fork had drifted since
v1.8.0, and that `_agent_lint` (opt-in) now also covers staged `*.js` and `*.md`.

Commit message: `fix(agent-rigor): load the lib-foundation audit library instead of a stale local fork`

### Commit 2 — drop the `"su""do"` split in the tunnel wrapper (R3)

The hook must be loading upstream before this commit, so Commit 1 must already be in place.

**File 4 — `scripts/plugins/tunnel.sh`, `_tunnel_write_vault_agent`.** Replace

```bash
  local ssh_bin _sudo_bin="su""do"
```

with

```bash
  local ssh_bin
```

and replace the heredoc line

```bash
  "${_sudo_bin} fuser -k -n tcp ${TUNNEL_VAULT_REMOTE_PORT} >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
```

with

```bash
  "sudo fuser -k -n tcp ${TUNNEL_VAULT_REMOTE_PORT} >/dev/null 2>&1 || true" >/dev/null 2>&1 || true # agent-audit: remote-sudo
```

The heredoc is unquoted, so the marker is also written into the generated wrapper, where it is a
trailing shell comment and harmless.

**File 5 — `scripts/tests/plugins/tunnel.bats`**, test "vault agent clears stale 8200 and owns the
reverse forward". Add:

- `grep -q 'sudo fuser -k -n tcp 8200' "${TUNNEL_VAULT_WRAPPER_PATH}"`
- `run bash -n "${TUNNEL_VAULT_WRAPPER_PATH}"` then `[ "$status" -eq 0 ]`

Add one static test, `tunnel.sh does not disguise sudo`, that runs `run grep -F 'su""do'
scripts/plugins/tunnel.sh` and asserts `[ "$status" -ne 0 ]`.

Commit message: `fix(tunnel): use a marked remote sudo instead of splitting the word`

## Rules

- Modify only Files 1–5.
- Run and paste: `shellcheck -x scripts/lib/agent_rigor.sh scripts/plugins/tunnel.sh` (no new
  warnings vs. `git show HEAD:<file>`), and
  `bats scripts/tests/lib/agent_rigor.bats scripts/tests/plugins/tunnel.bats scripts/tests/lib/bats_negation_lint.bats`.
- Mutations (snapshot, then `cmp` restore):
  - Restore the old fork content of `scripts/lib/agent_rigor.sh` (`git show HEAD:scripts/lib/agent_rigor.sh`)
    and show the marker test red.
  - Remove `# agent-audit: remote-sudo` from the tunnel line, stage `scripts/plugins/tunnel.sh`, and show
    that running `.githooks/pre-commit` directly exits non-zero with `bare sudo call`. Then unstage and
    restore.
- Do not run `make test` (Claude runs it). Do not touch `scripts/lib/foundation/`.
