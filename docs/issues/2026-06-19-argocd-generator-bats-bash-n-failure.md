# 2026-06-19 — `bash -n` on `scripts/tests/plugins/argocd_app_cluster_generator.bats` fails on BATS syntax

## What was tested

After applying the spec-only edit to replace the `rg` dependency with `grep -rF`, I ran:

```bash
bash -n scripts/tests/plugins/argocd_app_cluster_generator.bats
```

## Actual output

```text
scripts/tests/plugins/argocd_app_cluster_generator.bats: line 11: syntax error near unexpected token `}'
scripts/tests/plugins/argocd_app_cluster_generator.bats: line 11: `}'
```

The BATS suite itself still passes:

```text
1..3
ok 1 argocd app cluster generator: no static ubuntu-k3s ApplicationSet destination remains
ok 2 argocd app cluster generator: services-git uses matrix clusters label selector
ok 3 argocd app cluster generator: data-git exists and targets shopping-cart-data
```

## Root cause

`scripts/tests/plugins/argocd_app_cluster_generator.bats` is a BATS test file that uses `@test` blocks. Bash syntax checking does not accept the BATS test syntax, so `bash -n` reports a syntax error on the closing brace.

## Recommended follow-up

If the repo wants `bash -n` coverage for test files, use a BATS-aware lint or restrict `bash -n` to plain shell scripts only. The current test file remains valid for `bats`, and the behavior change requested by the spec is in place.
