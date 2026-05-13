# make down preserved the local Hub by default

## What Happened
`make down` expanded to:

```text
bin/acg-down --confirm --keep-hub
```

because `KEEP_LOCAL` defaulted to `1`.

## Why This Was a Problem
The variable name reads like an opt-in preservation flag, but the default already preserved the Hub. That made `KEEP_LOCAL` feel redundant and made the teardown behavior harder to reason about.

## Fix
- Change the `Makefile` default to `KEEP_LOCAL=0`.
- Update the help text and how-to docs to say Hub preservation is now opt-in via `KEEP_LOCAL=1`.

## Follow-Up
- Keep teardown defaults aligned with the least surprising behavior.
- Avoid defaulting preservation flags to enabled when the variable name already implies the choice.
