# Issue: `vault_app_auth.bats` stale role-policy assertion after P2b `app-cluster-reader` cutover

## What was tested / attempted

Ran the required full validation during v1.11.0 P3 work:

```text
./scripts/k3d-manager test all
```

## Actual output

```text
not ok 381 configure_vault_app_auth calls vault commands with correct args
# (in test file scripts/tests/plugins/vault_app_auth.bats, line 187)
#   `grep -q "policies=eso-reader" "$VAULT_EXEC_LOG"' failed
```

## Root cause if known

The production code in `configure_vault_app_auth` has bound the app-cluster role to
`policies=app-cluster-reader` since the merged P2b change (`91578a0b`), but
`scripts/tests/plugins/vault_app_auth.bats` still asserted the pre-P2b `policies=eso-reader` value.

## Recommended follow-up

Keep the updated assertion aligned with the least-privilege P2b behavior:

```text
grep -q "policies=app-cluster-reader" "$VAULT_EXEC_LOG"
```

Re-run:

```text
bats scripts/tests/plugins/vault_app_auth.bats
./scripts/k3d-manager test all
```
