# Bug: `make find-similar-docs Q="…"` always says "no query given"

**Status:** FIXED (2026-10-24, Claude; offline-verified)
**Priority:** P2 — dedup Pass 2 in CLAUDE.md is broken from the command line; workaround is `python3 scripts/find-similar-docs.py -- "<query>"`.
**Severity:** low
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Filed:** 2026-10-24, by Claude, while filing another bug
**Component:** `Makefile` (`find-similar-docs`)
**Related:** `docs/howto/find-prior-art.md`, `scripts/lib/webhook/lifecycle.py` (`_make_target_argv`)

## Symptom

`make find-similar-docs Q="cloud bridge tests publish to the real cloud-requests branch"` prints
`find-similar-docs: no query given …` and runs no search.

## Root cause

Checkpoint commit 74d79eac (2026-10-21) hardened the Slack path: the webhook now sends the query as
`Q_B64=<base64>`, and the recipe decodes `$(Q_B64)` straight into argv. That change dropped the
local `Q=` form: nothing sets `Q_B64` from `Q`, so a local call decodes an empty string.

## Fix

When `Q_B64` is empty, the recipe reads `Q` from the recipe's environment (GNU Make exports
command-line variables). `Q` never expands into the shell command line, so the injection hardening
stays. The webhook still rewrites `Q=` to `Q_B64=`, so it never reaches the fallback.

## Verification

- `make find-similar-docs Q="… ; \$(id) \`id\`"` searches, and the backticks print literally.
- `make find-similar-docs` with no Q still prints the usage line.
- `make find-similar-docs Q_B64=<base64>` still works.
- `webhook_make_targets.py`: green.
