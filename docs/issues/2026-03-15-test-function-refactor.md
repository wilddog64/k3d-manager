# Issue: `test()` exceeded Agent Rigor if-count

## Context
- `scripts/k3d-manager` dispatcher owns the `test` entrypoint.
- Legacy implementation packed argument parsing, smoke routing, suite selection, and BATS logging (27 `if` blocks) into a single function.
- Agent Rigor gate of 8 if-blocks prevented future edits and made manual reasoning difficult.

## Resolution
- Added helpers `_test_run_smoke`, `_test_select_suite`, `_test_execute` inside the dispatcher.
- Slimmed `function test()` to delegate after argument parsing and inline `::case` handling.
- Preserved all behaviour (same CLI flags, logging, artifacts) while meeting the if-count budget.

## Verification
- `shellcheck scripts/k3d-manager`
- `AGENT_AUDIT_MAX_IF=8 bash scripts/lib/agent_rigor.sh scripts/k3d-manager`
- `./scripts/k3d-manager --help`
- `./scripts/k3d-manager test --help`
- `./scripts/k3d-manager test all`
