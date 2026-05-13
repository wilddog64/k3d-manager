# `scripts/lib/test.sh` if-count allowlist follow-up

## What happened

While committing the bin filename normalization, the pre-commit hook failed on the existing if-count budget in `scripts/lib/test.sh`.

## Actual output

```text
WARN: Agent audit: scripts/lib/test.sh exceeds if-count threshold in: test_jenkins:29
test_cert_rotation:14
Pre-commit hook: _agent_audit failed — fix violations before committing
```

## Root cause

`scripts/lib/test.sh` already has legacy functions that exceed the current Agent Audit if-count threshold.

## Follow-up

- Keep the functions on the temporary allowlist until they are refactored.
- Refactor `test_jenkins` and `test_cert_rotation` in a separate task if the budget needs to be reduced later.
