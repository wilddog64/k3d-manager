# Issue: `_run_command` Exceeds Agent Audit if-count Threshold

**Date identified:** 2026-03-08
**File:** `scripts/lib/system.sh`
**Function:** `_run_command`

---

## Problem

`_agent_audit` checks every function in staged `.sh` files for excessive `if`-block nesting
(default threshold: 8). `_run_command` currently contains 12 `if`-blocks, triggering the
audit warning on every commit that touches `system.sh`:

```
WARN: Agent audit: scripts/lib/system.sh exceeds if-count threshold in: _run_command:12
```

This is a false positive — the complexity is real but intentional. Any downstream consumer
(e.g. k3d-manager) that touches `system.sh` gets blocked by their own pre-commit hook.

## Workaround

Consumers raise `AGENT_AUDIT_MAX_IF` in their `.envrc` to suppress the warning:

```bash
# k3d-manager: ~/.zsh/envrc/k3d-manager.envrc
export AGENT_AUDIT_MAX_IF=15
```

## Root Cause

`_run_command` handles multiple orthogonal concerns in a single function:
- sudo probing and escalation (`--probe`, `--prefer-sudo`, `--require-sudo`)
- sensitive flag detection and trace suppression (`_args_have_sensitive_flag`)
- quiet mode / stderr suppression
- actual command dispatch

Each concern adds `if`-blocks, compounding the complexity.

## Proposed Fix

Extract the concerns into focused helpers:

| Helper | Responsibility |
|--------|---------------|
| `_run_command_resolve_sudo` | probe + prefer + require sudo logic |
| `_run_command_suppress_trace` | detect sensitive flags, disable `set -x` |
| `_run_command` | thin dispatcher — calls helpers, executes command |

Each helper would have ≤ 4 `if`-blocks, well under the default threshold of 8.
The helpers are also independently testable in BATS.

## Priority

**Low** — workaround is in place for known consumers. Address in a future minor release
(v0.3.0 or later). Coordinate with all consumers before merging — this is a contract change
for `_run_command`'s internal structure (though its public signature is unchanged).

## Consumers Affected

| Repo | Workaround |
|------|-----------|
| `k3d-manager` | `AGENT_AUDIT_MAX_IF=15` in `~/.zsh/envrc/k3d-manager.envrc` |

---

## Resolution — 2026-03-15

- Extracted `_run_command_resolve_sudo` helper (commit `b7b5411`) per
  `docs/plans/v0.3.0-run-command-if-count-refactor.md`.
- `_run_command` now delegates to the helper and both functions pass
  `AGENT_AUDIT_MAX_IF=8 bash scripts/lib/agent_rigor.sh scripts/lib/system.sh`.
- Added `scripts/tests/lib/system.bats` with coverage for the helper and quiet-mode
  behavior; BATS passes via `env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
  HOME="$HOME" TMPDIR="$TMPDIR" bash --norc --noprofile -c 'bats scripts/tests/lib/*.bats'`.
- PR #5 (`feat/run-command-refactor-v0.3.0` → `main`) open in lib-foundation; awaiting review
  + downstream subtree sync.
- Follow-up (commit `c50e294`): replaced `local -n` with `_RCRS_RUNNER` global for bash 3.2
  compatibility; reran `AGENT_AUDIT_MAX_IF=8 bash scripts/lib/agent_rigor.sh scripts/lib/system.sh`
  and the full env-isolated BATS suite — all still PASS.
