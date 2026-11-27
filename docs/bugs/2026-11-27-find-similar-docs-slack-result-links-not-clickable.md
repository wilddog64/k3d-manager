# Bug: find-similar-docs results in Slack show document URLs as plain text, not links

**Status:** OPEN — captured, not triaged
**Priority:** P3 (proposed; Argon classifies)
**Introduced by:** pre-existing
**Should have been caught by:** none
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-27
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run
**Filed:** 2026-11-27, Claude, from operator report ("hyperlink seems to be turn off" / "but ask-docs can show hyperlinks")
**Component:** webhook make-job final notice (`escape_code_block` output tail) for `make find-similar-docs`;
`scripts/lib/webhook/ask_docs.py:211` (`source_line`) is the working pattern

## Report

The `make find-similar-docs` job reply (job `497709c4`, #acg-automation, 2026-11-27 19:52 PST) lists each match with a
`https://github.com/wilddog64/k3d-manager/blob/…` URL, but the whole output tail is posted inside a code block, where
Slack does not linkify URLs. `ask-docs` replies post their `Sources:` lines outside any code block via `source_line`, so
those are clickable (operator screenshot, Nov 16 ask-docs thread).

## Direction (for triage)

For find-similar-docs jobs, post the matches as `Sources:`-style Slack links (reuse `ask_docs.source_line`) above or
instead of the raw code-block tail; keep the code block for other make targets.
