# Issue: v1.11.0 P3 spec-mandated functions exceed the Agent Audit if-count budget

## What was tested / attempted

Attempted the required feature commit after landing the spec blocks for:

- `scripts/plugins/shopping_cart.sh:shopping_cart_seed_sandbox_vault_kv`
- `scripts/plugins/vault.sh:vault_seed_hub_into_context`

Command:

```text
git commit -m "feat(vault): idempotent canonical-source seeding + vault_seed_hub_into_context (Tier 3 P3)"
```

## Actual output

```text
WARN: Agent audit: scripts/plugins/shopping_cart.sh exceeds if-count threshold in: shopping_cart_seed_sandbox_vault_kv:11
WARN: Agent audit: scripts/plugins/vault.sh exceeds if-count threshold in: vault_seed_hub_into_context:10
Pre-commit hook: _agent_audit failed — fix violations before committing
```

## Root cause if known

The v1.11.0 P3 spec requires exact new code blocks for both functions. Those exact blocks push each
function above the repository’s `if`-count threshold of 8.

## Recommended follow-up

Keep both legacy/spec-mandated functions temporarily allowlisted:

- `scripts/plugins/shopping_cart.sh:shopping_cart_seed_sandbox_vault_kv`
- `scripts/plugins/vault.sh:vault_seed_hub_into_context`

Then do a follow-up refactor in a separate task to reduce branch complexity without changing the P3
behavior.
