# Copilot review findings — PR #149 (v1.43.6)

**Date:** 2026-10-24
**PR:** #149 — feat: v1.43.6 — per-agent dispatch data
**Reviewer:** copilot-pull-request-reviewer[bot]

## Finding 1 — agy section heading is H1 in the dispatch how-to

**File:** `docs/howto/codex-dispatch.md:124`

Copilot flagged that `# agy (Gemini 4 Argon)` is a top-level H1 while every other section in the
file is `##`, which renders a second document title mid-page and leaves the following
`### Record local agy activity` under the wrong level.

**Fix:**

```diff
-# agy (Gemini 4 Argon)
+## agy (Gemini 4 Argon)
```

**Root cause:** the agy dispatcher commit (`2040d546`) appended the section with an H1, and nothing
checks heading levels in how-to docs.

**Process note:** a spec that adds a section to an existing doc should name the heading level of its
siblings. Valid finding; fixed.
