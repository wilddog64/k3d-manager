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

## Workaround

`AGENT_AUDIT_MAX_IF=15` is set in `~/.zsh/envrc/k3d-manager.envrc` to suppress the false
positive while the real fix is deferred.

## Root Cause

`_run_command` handles multiple orthogonal concerns in a single function:
- sudo probing and escalation (`--probe`, `--prefer-sudo`, `--require-sudo`)
- sensitive flag detection and trace suppression
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

This would bring each function well under the 8 if-block threshold and make the sudo
escalation logic independently testable in BATS.

## Priority

**Low** — workaround is in place. Fix must be applied in lib-foundation first
(`_run_command` originates there), then subtree-pulled into k3d-manager.

## Authoritative Issue Doc

`lib-foundation/docs/issues/2026-03-08-run-command-if-count-refactor.md`

## Related

- `~/.zsh/envrc/k3d-manager.envrc` — `AGENT_AUDIT_MAX_IF=15` workaround
- `scripts/lib/foundation/scripts/lib/system.sh` — subtree copy of `_run_command`
- lib-foundation open items — "Route bare sudo through `_run_command`" (separate issue)
