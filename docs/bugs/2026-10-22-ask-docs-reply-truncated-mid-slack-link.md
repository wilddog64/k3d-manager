# Bug: ask-docs reply is cut mid Slack link, and the bug count repeats "(0 deferred)"

**Filed:** 2026-10-22 (Claude, from the operator's Slack screenshots during the ask-docs thread live check)
**Status:** FIXED offline — `ee456c83` (Luna; Claude review: N1 and N2 red on pre-fix, existing '(1 deferred)' test still green, 53 tests green); live E2 pending make restart-webhook + `/ask-docs what is the bug tally`
**Priority:** P3 — cosmetic; the last listed doc renders as raw markup, every other line is correct
**Severity:** low
**Approval:** approved — operator, 2026-10-22: "yes" to filing and dispatching to Luna
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `scripts/lib/webhook/ask_docs.py` (reply truncation); `scripts/lib/webhook/bug_count.py` (summary line)
**Related:** `docs/bugs/2026-10-22-bug-tally-counts-implemented-and-deferred-as-open.md`

## Symptom

`ask-docs what is the bug tally` (top-level and in a job thread, 2026-10-22 ~18:00 PDT) ends with:

`Open: <https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.5/docs/bugs/2026-10-20-hostinger-multi-service-502-kubernetes-api-timeouts.md%7Cdocs/bugs/2026-10-20-hostinger-m`

The line is raw markup instead of a link, and the list stops mid-entry with no sign that it was cut.
Every release line also says `(0 deferred)`, even where there is nothing deferred.

## Root cause

1. `ask_docs.py` builds the final reply with `prose[:available]` (around line 219), where
   `available = MAX_REPLY_CHARS - len(source_lines) - 2` and `MAX_REPLY_CHARS = 3000`. The slice
   cuts at a character count, so it can land inside a `<url|text>` link (made by `_doc_link`). Slack
   then shows the unclosed markup as text. Nothing tells the reader the reply was shortened.
2. `bug_count.py` always rewrites `N open,` to `N open (M deferred),`, including when M is 0.

## Fix

- **F1.** In `ask_docs.py`, when `prose` is longer than `available`, cut at the last newline at or
  before `available - len(marker)` and append the marker line `…(truncated; name a release to see
  the full list)`. A cut never leaves an unclosed `<`…`>` link. If there is no newline in range,
  cut at the last whitespace outside a `<…>` span. Prose that fits is unchanged.
- **F2.** In `bug_count.py`, add ` (M deferred)` only when M > 0; otherwise the line keeps the
  plain `N open,` form.
- **F3.** Tests: a prose longer than the limit made of `_doc_link` lines is cut on a line boundary,
  has balanced `<`/`>` and ends with the marker; a short prose is returned unchanged; a release with
  0 deferred has no `deferred` text, and one with 1 deferred still shows `(1 deferred)`.
- **F4.** `CHANGELOG.md` entry.

## Files

- `scripts/lib/webhook/ask_docs.py`
- `scripts/lib/webhook/bug_count.py`
- `scripts/tests/bin/test_ask_docs.py`
- `scripts/tests/bin/test_bug_tally.py`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: An ask-docs reply whose prose exceeds MAX_REPLY_CHARS is cut on a line boundary, stays within MAX_REPLY_CHARS, and ends the prose with the truncation marker line.
  - id: M2
    text: A bug-count release line shows "(M deferred)" only when M > 0.
  - id: M3
    text: A reply that fits within the limit is returned byte-for-byte as before (no marker).
must_not:
  - id: N1
    text: A truncated reply must not contain an unclosed Slack link — every "<" in the prose has a matching ">" (red on the pre-fix code).
  - id: N2
    text: A release line with 0 deferred docs must not contain the word "deferred" (red on the pre-fix code).
  - id: N3
    text: The Sources block after the prose must not be cut or dropped.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2, N3]
    text: pytest scripts/tests/bin/test_ask_docs.py scripts/tests/bin/test_bug_tally.py; N1 and N2 red on the pre-fix code.
  - id: E2
    kind: live
    proves: [M1, M2, N1]
    text: After make restart-webhook, the operator runs `/ask-docs what is the bug tally`; the last line is a working link or the truncation marker, and lines with no deferred docs read "N open,".
interface:
  - scripts/lib/webhook/ask_docs.py MAX_REPLY_CHARS, _doc_link(path), and the function that returns AskDocsResult with prose + source_lines
  - scripts/lib/webhook/bug_count.py reply(query)
```

## Definition of Done

- [ ] F1–F4 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 and N2 shown red against the pre-fix code.
- [ ] Commit: `fix(ask-docs): truncate replies on a line boundary and drop zero deferred counts`

## What NOT to Do

- Do NOT raise `MAX_REPLY_CHARS` instead of fixing the cut.
- Do NOT change `_doc_link` output or the link format.
- Do NOT edit this bug doc, create a PR, commit to `main`, or use `--no-verify`.
