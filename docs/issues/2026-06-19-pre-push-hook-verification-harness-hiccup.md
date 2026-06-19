# 2026-06-19 — Pre-push hook verification harness hiccup

## What was tested

I patched `.githooks/pre-push` in:
- `shopping-carts/rabbitmq-client-python`
- `shopping-carts/rabbitmq-client-java`
- `shopping-carts/rabbitmq-client-go`
- `shopping-carts/observability-stack`

Then I ran `bash -n`, `shellcheck`, and the four direct-invocation checks from the spec in each repo.

## Actual output

First verification pass failed in the harness before the hook checks completed:

```text
feature->main: run_case:5: read-only variable: status
```

One repo also had a shell quoting typo in the harness:

```text
zsh:14: unmatched "
```

After fixing the harness to use `rc` and a temp file, the hook checks passed in all four repos.

## Root cause

The failure was in the local verification script, not in `.githooks/pre-push`:
- `status` is a reserved readonly shell variable in this environment.
- One command string had an unmatched quote.

## Recommended follow-up

Use a non-reserved variable name such as `rc` and keep the per-repo verification harness quoted or wrapped in a temp-file helper when running these direct hook tests.
