# Issue: `deploy_keycloak` exceeds the Agent Audit if-count threshold

## Status
Open

## What happened
The pre-commit hook blocked the commit after the Keycloak reconciliation fix because `scripts/plugins/keycloak.sh:deploy_keycloak` exceeds the repository if-count budget.

Observed output:

```text
WARN: Agent audit: scripts/plugins/keycloak.sh exceeds if-count threshold in: deploy_keycloak:11
Pre-commit hook: _agent_audit failed — fix violations before committing
```

## Root Cause
`deploy_keycloak` is a legacy, multi-branch bootstrap function that already exceeds the audit threshold before this change.

## Follow-up
Keep it on the temporary allowlist for now and schedule a separate refactor to reduce the branching depth in `deploy_keycloak`.
