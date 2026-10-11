# PR #139 review findings (v1.43.0)

**Date:** 2026-10-11
**PR:** [#139](https://github.com/wilddog64/k3d-manager/pull/139) — `k3d-manager-v1.43.0`
**Status:** FIXED

Copilot left one comment. CI lint (run `38139110137`, head `9c9292b6`) failed on three tests: one
is the same defect Copilot flagged, and the other two are unrelated to Copilot.

## Finding 1 — `hermes_alert_rules.bats` depends on `rg` (Copilot, CI)

**File:** `scripts/tests/plugins/hermes_alert_rules.bats:6`

Copilot: the suite calls `rg`, but ripgrep is not part of the test toolset; the rest of the suite
uses `grep`. In CI the call exited 127 (`BW01 ... Command not found`), so test 974 failed.

```bash
# before
  run rg -n -A 16 '^        - alert: HermesNotRunning$' "${RULES_FILE}"
# after
  run grep -n -A 16 '^        - alert: HermesNotRunning$' "${RULES_FILE}"
```

The pattern is a basic regex, so `grep` reads it the same way. Checked in `ubuntu:24.04` with no
`rg` installed: the test passes, and fails once the rule is renamed.

**Root cause:** the test was written on the M4, where `rg` is installed. `rg` breaking a Linux CI run
is a known, recurring class here.

## Finding 2 — `precommit_bug_priority.bats` inherits CI's `K3DM_ENABLE_AI=1` (CI only)

**File:** `scripts/tests/plugins/precommit_bug_priority.bats:19`

"new bug doc with P2 is accepted" and "modified legacy bug doc without Priority is accepted"
failed on `[ "${status}" -eq 0 ]`. They pass on macOS and on plain Ubuntu.

The CI lint job exports `K3DM_ENABLE_AI: "1"` for `make test`. The pre-commit hook then runs
`_agent_lint` with the AI reviewer after `_agent_audit`. Only the two "accepted" tests get that far:
the two rejection tests exit at the priority check. The AI reviewer fails on the runner, so the hook
returns non-zero for a valid doc.

```bash
# before
  run env K3DM_SKIP_DOC_LINKS=1 K3DM_SKIP_ROOT_DEBRIS=1 bash "${hook}"
# after
  run env K3DM_ENABLE_AI=0 K3DM_SKIP_DOC_LINKS=1 K3DM_SKIP_ROOT_DEBRIS=1 bash "${hook}"
```

Reproduced in `ubuntu:24.04` through `scripts/tests/tripwire.sh ./scripts/k3d-manager test
precommit_bug_priority` with `K3DM_ENABLE_AI=1`: 2 failures before the change, 4/4 after.

**Root cause:** the suite (added this release in `89cb86c1`) runs the whole hook but pinned only
the bypasses it knew about. The hook also reads `K3DM_ENABLE_AI`, which CI sets and a developer
shell usually does not.

## Finding 3 — unused import in `bug-tally.py` (CI only)

**File:** `scripts/bug-tally.py:9`

With the tests fixed, CI run `38140433416` reached `make lint-python`, which failed:
Ruff F401, `collections.defaultdict` imported but unused. Removed the import. In a
`python:3.12-slim` container with the CI's `ruff==0.15.8`, `make lint-python` passes and
`test_bug_tally.py` passes 5/5. `make validate-manifests` passes locally (78/78).

**Root cause:** Ruff is not installed on the M4, so `make lint-python` refuses to run there and
this was never checked before the PR.

## Process note

- A test that runs `.githooks/pre-commit` must pin every switch the hook reads
  (`K3DM_ENABLE_AI`, `K3DM_SKIP_DOC_LINKS`, `K3DM_SKIP_ROOT_DEBRIS`), not only the ones it is
  testing around.
- Before a PR, run any new suite once in `ubuntu:24.04` with the CI lint job's env, and run
  `make lint-python` with the pinned Ruff. Neither defect
  shows up on the M4.
