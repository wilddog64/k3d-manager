# Bug: `/k3dm find-similar-docs Q=…` accepts only a one-word query from Slack

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30 by Claude (cloud session), from the operator's question "is this command available
on Slack?"
**Status:** FIXED in `2e0f4bc2` (Claude) and verified live 2026-09-30: after `make deploy-worker`, `/k3dm find-similar-docs Q=mac scheduler cannot find tools` returned the launchd PATH bug at #1.
**Severity:** Medium. Semantic search needs a sentence; one word reduces it to keyword lookup.

## Evidence

`parseK3dm` in `workers/slack-relay/index.js`, run on three inputs:

| Slack text | Result |
|---|---|
| `find-similar-docs Q=launchd` | relayed |
| `find-similar-docs Q=mac scheduler cannot find tools` | usage error |
| `find-similar-docs Q="mac scheduler cannot find tools"` | usage error |

`docs/howto/find-prior-art.md` documented `/k3dm find-similar-docs Q=...` as if a sentence worked.

## Root cause

The relay splits the text on whitespace and requires every token to be `KEY=value` or `confirm`, so
the second word of a query is rejected as a malformed argument. Quotes do not help: the tokens are
still split, and `"` is outside `Q`'s allowed characters. The webhook (`Q` pattern allows spaces,
`make` gets `Q=…` as a single argv element) and the Makefile recipe (`-- "$(Q)"`) already accept a
sentence, so only the Slack parser was in the way.

## Fix

`Q` is a free-text key: after `Q=`, bare words are appended to `Q` until the next `KEY=value` or
`confirm`. A bare word anywhere else is still a usage error, and a joined `Q` over 256 characters
is rejected. Character validation is unchanged and stays in the webhook (`_ARG_PATTERNS["Q"]`,
max 200), so a metacharacter in a multi-word query is still refused there.

Example: `/k3dm find-similar-docs Q=mac scheduler cannot find tools K=10`.

## Tests

`workers/slack-relay/test/relay.test.mjs`: multi-word `Q`; `Q` stops at `K=`; `Q` stops at
`confirm`; a bare word after `confirm` is rejected; bare words after a non-free-text key or before
any key are rejected; metacharacters pass through to the webhook; a joined `Q` over 256 is
rejected. 31/31. Mutations: the old parser fails 4, dropping the length cap fails 1, and not ending
`Q` at `confirm` fails 1. The webhook side is already covered by
`scripts/tests/bin/webhook_make_targets.py` (multi-word `Q` accepted, metacharacters rejected).
